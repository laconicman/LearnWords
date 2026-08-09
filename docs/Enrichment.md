# Enrichment — prefilling words from open lexical data (TD-22)

How the app fills in transcription, part of speech, forms and sense annotations when a word
is added, without asking the learner to type them and without telling a third party what
they are studying.

Research and design only. **No code exists for any of this.** Read
[TechDebt § TD-22](TechDebt.md) for why kaikki/Wiktionary won the source comparison, and
[Design](Design.md) for the decisions this builds on (language codes, variety, managed
objects never escaping the store).

## What is proven, and what is assumed

Following [Handoff](Handoff.md)'s convention, because this document's whole value is being
right about someone else's data format.

| Claim | Status |
|---|---|
| English extract is 3.19 GB, Russian 0.94 GB, German 1.07 GB (uncompressed JSONL) | ✅ measured — `Content-Length` from kaikki.org, 2026-07-27 |
| `lang_code` is language-level; region/script is never a `lang_code` | ✅ verified in the README's own `thrill` record |
| `uppercase_tags` holds 2,062 dialect tags; `valid_tags` holds 1,337 categorised tags; `valid_topics` holds 227 | ✅ counted from live `master` |
| `SoundData` never carries both `ipa` and `audio` in one object | ⚠️ asserted by wiktextract's test suite, not re-measured against real output |
| A reduced per-language pack fits in tens of MB | ❌ **estimated, not built.** The reduction ratio is the first thing a fork must measure |
| FTS5 is available in the system SQLite at the iOS 12.1 floor | ❌ **unverified** — needs a run on the owner's old device (TD-8 territory) |
| Wiktionary's gloss-headed translation tables give usable sense-to-sense links | ⚠️ true in the format; quality in practice is unmeasured |

### Corrections to the DeepWiki consult

The consult ([share link](https://deepwiki.com/search/i-am-designing-an-ingestion-pa_3f9a471d-3b6e-48e8-ab2e-e7e8050d7f71?mode=deep))
ran against an index **206 days / 159 commits** behind `master`. Four of its numbers were
wrong; every figure in this document was re-read from live `master` instead. Recorded so
the next reader trusts the right column:

| Claim from the index | Live `master` |
|---|---|
| `SoundData` is a class in `en/type_utils.py` | It is a functional-syntax `TypedDict` at `type_utils.py:106` |
| `uppercase_tags` ≈ 1,500 | **2,062** |
| `valid_tags` ≈ 600–700, from line 5089 | **1,337**, from line **5122** |
| `valid_topics` ≈ 250 | **227** |

The structural answers it gave — the tag/topic split, the form-vs-alt-spelling
discriminators, no per-word addressing — all held up. Numbers drifted; architecture did not.

## The source

**kaikki.org**, the pre-built wiktextract output. One JSON object per line, one object per
(word, part of speech, etymology number). **No index and no per-word addressing** — a
consumer streams the whole file. Files are pre-split per language.

The tool is MIT; the data is Wiktionary's, so CC BY-SA and GFDL (see *Licence*, below).

### The record shapes we care about

Read from `src/wiktextract/extractor/en/type_utils.py` on live `master`.

```
WordData     word, pos, lang, lang_code, senses[], forms[], sounds[],
             translations[], synonyms[], etymology_text, …

SoundData    ipa, enpr, audio, audio-ipa, ogg_url, mp3_url, homophone,
             rhymes, hangeul, zh-pron, other, note, text, tags[], topics[]

FormData     form, tags[], raw_tags[], topics[], ipa, roman, ruby,
             source, head_nr, links[]

SenseData    glosses[], raw_glosses[], tags[], topics[], alt_of[], form_of[],
             examples[], synonyms[], antonyms[], categories[], senseid[], …
```

`SoundData` is a bag of alternatives, not a record: one entry carries an IPA string *or* an
audio file *or* a rhyme, never several. Ingestion should therefore filter, not destructure.

### How wiktextract itself classifies a tag

This is the part that maps cleanly onto our schema, and it is wiktextract's own
classification rather than one we invent. Three disjoint vocabularies:

| Vocabulary | Size | Contents | Where |
|---|---|---|---|
| `uppercase_tags` | 2,062 | **Dialect tags** — `US`, `UK`, `Received-Pronunciation`, `General-American`, `Australia`, `Scotland`, and 2,000 more down to `Abung/Kotabumi` | `tags.py:658` |
| `valid_tags` | 1,337 | Linguistic tags, each mapped to a category | `tags.py:5122` |
| `valid_topics` | 227 | Subject domains — `medicine`, `law`, `computing`, `botany` | `topics.py` |

`valid_tags`' own category histogram, which tells us what a tag *is* before we decide where
to put it:

```
misc 507 · with 131 · case 114 · script 86 · class 84 · mood 78 · detail 42
tense 40 · non-finite 37 · object 27 · register 21 · aspect 18 · number 15
pos 14 · person 13 · gender 10 · voice 6 · mod 5 · transitivity 4 · dialect 4 · …
```

Note `dialect` appears here with only **4** entries: the other 2,062 live in
`uppercase_tags`. Any ingestion that reads only `valid_tags` will miss essentially every
regional annotation.

Two more discriminators, both read live:

- **`form_of_tags`** (152: `plural`, `past`, `participle`, `genitive`, `aorist`, …) marks an
  **inflected form**.
- **`alt_of_tags`** (18: `abbreviation`, `capitalized`, `contracted`, `dialectal`,
  `obsolete`, `initialism`, …) marks an **alternative form of the same word**.

## Mapping onto our schema

| wiktextract | LearnWords | Notes |
|---|---|---|
| `lang_code` | `Term.language` | through `LanguageCode.canonical`; `hr`/`sr`/`bs` need the bridge below |
| `word` | `Term.text` | find-or-create by (text, language), as today |
| `pos` | `Term.partOfSpeech` | 14 `pos`-category tags refine it |
| `sounds[].ipa` + its dialect tags | **`Pronunciation`** (new) | see below — `Term.transcription` cannot hold two accents |
| `sounds[].ogg_url` / `.mp3_url` | `Pronunciation.audioURL` | remote URL, like `Illustration` already does |
| `sounds[].enpr` / `.rhymes` / `.homophone` | — | out of scope |
| `forms[]` ∩ `form_of_tags` | `WordForm` | exists; `formType` takes the tag |
| `forms[]` ∩ `alt_of_tags` / `alternative` | sibling `Term` in the same `Synset` | this is how `color`/`colour` become one meaning, two words |
| `forms[]` with `romanization` | `WordForm` | `formType = "romanization"` |
| `senses[].glosses` | `Synset.note` | our note *is* the disambiguating gloss |
| `senses[].tags` ∩ `uppercase_tags` | **`Variety`** (new) | on the `Term`, not the `Synset` |
| `senses[].tags` ∩ `register` | `Tag` | `slang`, `formal`, `archaic` — the folksonomy we have |
| `senses[].topics` | `Tag` with a category | `medicine`, `law` — see below |
| `translations[].sense` | candidate `Synset` links | gloss-*text* keyed, so fuzzy; the reason DBnary stays on the table |

### Three schema additions this implies

**1. `Pronunciation`, replacing `Term.transcription`.** A single optional string cannot hold
both /ˈskedʒuːl/ and /ˈʃedjuːl/, and `SoundData` proves the source has both. A child of
`Term` with `ipa`, `audioURLString`, and a relationship to `Variety`.

**2. `Variety`.** A lookup row on `Term`, per [Design](Design.md). **One correction to that
decision's reasoning:** it argued variety is a "closed, registry-backed set" as against the
open `Tag` folksonomy. With 2,062 dialect tags upstream, "closed" is not a useful property —
we cannot ship or validate against that list any more than we can a folksonomy, so `Variety`
must be find-or-create exactly like `Tag` and `Language`. The decision still stands, on the
two stronger legs: variety belongs to the **`Term`** (which spelling) and the
**pronunciation** (which accent), never to the `Synset`, so it cannot share `Tag`'s
relationship; and it is one dimension shared by three owners.

**3. `Tag.category`.** `senses[].tags` and `senses[].topics` are different vocabularies
upstream (`register` vs `medicine`), and we currently plan to smuggle the difference into
the name as `domain:medicine` — a prefix convention doing a column's job, which is the exact
thing the variety decision rejected.

*Why a `category` column is right here when `Tag.kind` was wrong for variety:* the test is
whether the kinds differ in **owner, cardinality, or attributes**. Register and topic differ
in none — both attach to `Synset`, both are open-ended, both are just a name. Variety
differs in owner. So this is not a reversal; it is the same test giving a different answer
on different facts.

### The CloudKit timing window — closed, and the three landed anyway (2026-08-07)

**This section used to describe a deadline. It had already passed when it was written.**
The production schema exported from the CloudKit Console carries
`CD_Term.CD_transcription`, so the deploy this warned about was history, and
`transcription` was permanent before anyone read the warning. Kept here rather than
deleted, because the reasoning is right and only its tense was wrong.

CloudKit lets you *add* record types and fields to a deployed production schema, at any
time, for ever. It does not let you remove or retype them. **The asymmetry is only about
removal** — which means `Pronunciation`, `Variety` and `Tag.category` were never on a clock;
retiring `Term.transcription` was, and that clock had run out.

The additions were nevertheless made on 2026-08-07 (owner), for a reason that has nothing
to do with the deadline: **one production schema deploy before App Store submission is
worth more than a second one later.** The risk that buys — designing entities from a source
format rather than from a working consumer, with CloudKit making *their* mistakes permanent
too — is recorded with the rest of the decision in
[TechDebt § TD-48](TechDebt.md), along with the accepted cost of `transcription` and the
fourth addition (`Language.wiktionaryCode`) that this document implies but the Roadmap's
list of three omitted.

**What shipped, against the design above:** `Pronunciation` takes `ipa` and
`audioURLString`, both optional — upstream a sound entry carries one or the other, never
both, so requiring either would make half the source unrepresentable. `Term.varieties` is
**many-to-many**, not to-one: upstream marks a spelling with an array of dialect tags, and
cardinality cannot be widened later without a schema change. `Tag.category` and
`Language.wiktionaryCode` are optional, because "a tag the learner invented" and "this
language needs no bridge" are the ordinary cases, not missing data.

### The `hr`/`sr`/`bs` bridge

Wiktionary has no `hr`, `sr` or `bs` — they fold into `sh` (Serbo-Croatian), and we
deliberately do not ([Design](Design.md)). Enrichment is where that seam is crossed: a
`wiktionaryCode` attribute on `Language`, so a Croatian word set looks its data up under
`sh` while still being labelled Croatian. Wiktionary's registry marks the same seam from its
side (`ietf_subtag = "hbs"`).

## Delivery: how the data reaches the device

The measured sizes rule out the obvious answer. 3.19 GB of English cannot ship in a bundle,
cannot be downloaded onto a phone, and — critically — **must never enter the Core Data
store**, which is mirrored to the learner's iCloud and counts against their quota. Reference
data is not user data.

| Option | Verdict |
|---|---|
| Bundle the raw JSONL | ❌ 3.19 GB |
| **Build-time reduction → read-only SQLite in the bundle, top-N lemmas per language** | ✅ **recommended start.** Offline, private, works at the 12.1 floor, no hosting, no network permission. Covers ordinary learner vocabulary; misses the long tail |
| On-demand download of a fuller per-language pack | Natural second step once someone hits the tail. Needs hosting and a refresh story |
| Live per-word API (dictionaryapi.dev, Merriam-Webster) | ❌ as the default — it sends the learner's vocabulary to a third party, against TD-22's privacy note. Acceptable only as an explicitly user-initiated, per-word action |

Concretely, the recommended path is a **build-time pipeline** — a script, not app code —
that streams the kaikki JSONL once and emits a small read-only SQLite keyed by
(text, language), holding only IPA, part of speech, forms and sense tags. It lives beside
the Core Data store, never inside it, and is replaced wholesale on update rather than
migrated.

**The first thing to measure** is the reduction ratio on a real file. Every size claim
downstream of that number is currently a guess, including whether "top-N lemmas" is even the
right axis (frequency lists are themselves a licensing question).

## Licence and attribution

- **wiktextract**, the tool: MIT.
- **The extracted data**: Wiktionary's, therefore **CC BY-SA and GFDL**. The owner has
  already accepted this ([TechDebt § TD-22](TechDebt.md)).
- **Obligations if we ship a derived pack:** attribute Wiktionary contributors, state the
  licence, and release the derived data share-alike. A settings/about screen naming
  Wiktionary and CC BY-SA, plus the licence text in the repo, discharges this.
- **Audio from Wikimedia Commons carries per-file licences** — mostly CC BY-SA or CC BY,
  some public domain. Linking to a URL is not redistribution; bundling the files is, and
  needs a per-file check. Prefer linking.
- kaikki asks, without requiring, for a citation to *Tatu Ylonen: Wiktextract: Wiktionary as
  Machine-Readable Structured Data* (LREC 2022) and a link to the relevant kaikki.org pages.
  Cheap courtesy; do both.

## Open questions for whoever builds this

1. **The reduction ratio.** Stream one real file, emit the reduced schema, measure. Every
   delivery decision depends on it.
2. **FTS5 at the 12.1 floor.** Needed for prefix search over the pack; unverified on an
   actual iOS 12 device.
3. **Does enrichment write to the synced store?** Enrichment *results* on the learner's own
   `Term` are their data and should sync. But a bulk prefill would push a lot of rows through
   CloudKit at once — worth a rate-limit test before enabling it by default.
4. **Enrich when?** At add-time (one word, immediate, no UI) or as a review screen over
   several candidates (accurate, but a screen to design). Start with the former.
5. **Sense-to-sense quality.** The translation-table linkage is by gloss text, not stable
   IDs, and is occasionally broken upstream. Measure the hit rate on a real language pair
   before designing anything on top of it. DBnary is the same data pre-modelled as
   OntoLex-Lemon if the linkage proves too noisy.

## Appendix — DeepWiki re-index request

The index is 206 days behind, which cost four wrong numbers in this document alone. To
request a refresh: open <https://deepwiki.com/tatuylonen/wiktextract>, use the re-index
control, and confirm by email. Suggested note:

> Requesting a re-index of `tatuylonen/wiktextract`. The current index is pinned at
> `96027d6e` (2026-01-02), ~159 commits behind `master`. Tag and topic vocabularies have
> grown substantially since — `uppercase_tags` is 2,062 (indexed as ~1,500), `valid_tags`
> 1,337 (indexed as ~600–700) — so answers about the tag system are quantitatively wrong.

The owner has offered to supply a confirmation address. Worth doing before anyone
implements against this document.
