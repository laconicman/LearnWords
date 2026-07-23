# Lexical model research — terms, senses, multilingual sets

Research pass behind the TD-13 schema redo (owner request, 2026-07-23): "research how
that task is solved instead of just replicating a very naive and limited solution."
Sources: the owner-provided Apple *Creating Dictionaries* guide and NSHipster's
*DCSDictionaryRef* piece, plus the standard lexical-resource models and the one shipping
product whose data model matters here (Anki).

## What the prior art agrees on

Every serious lexical system separates **three things the word-pair model conflates**:

1. **The word as an atomic entry** (lexeme), carrying its own language, pronunciation,
   part of speech, and inflected forms.
2. **The sense** — one *meaning* of that word. A word has many senses; a sense can be
   shared by several words (synonyms).
3. **Cross-language links, which connect senses — never words.**

### Apple Dictionary Services (owner's PDFs)

An entry (`d:entry`) is one lexeme with:
- **`d:index` variants** — every searchable representation points at the *same* entry:
  inflections (`make/makes/made/making`), alternate scripts, and Japanese **yomi**
  readings (工夫 indexed by both くふう and its kanji). The atomic-word-with-forms
  shape, exactly as proposed.
- **Multiple pronunciations** per entry (`d:pr="US" / US_IPA / UK_IPA`) — transcription
  is entry-level data, potentially multi-valued.
- **An ordered list of senses**, each with its own definition and examples — the
  entry/sense split is native to the format.

### OntoLex-Lemon (W3C) and LMF (ISO 24613)

The linguistics-standard shape: `LexicalEntry` → `LexicalSense`; a sense points at a
language-neutral concept. **Translations are `vartrans:Translation` relations between
two senses** — the standards explicitly reject word-to-word translation links because
words are polysemous ("bear" the animal vs "bear" the verb translate differently).
LMF's interlingual `SenseAxis` is the same idea. References:
[W3C OntoLex community report](https://www.w3.org/2016/05/ontolex/),
[bilingual-dictionary modelling guidelines](https://bpmlod.github.io/Bilingual_Dictionaries_Report/),
[OntoLex lexicography module](https://jogracia.github.io/ontolex-lexicog/).

### WordNet / BabelNet

The **synset** — a set of words sharing one meaning — is WordNet's core unit, and
BabelNet extends it multilingually: one synset holds synonyms *across languages*.
The owner's "language tuple" **is** a multilingual synset. This also gives synonyms
for free: «бегать» and «бежать» in one synset are both correct answers, which is the
principled version of today's comma-separated-definitions hack.

### Anki (notes / cards / revlog)

The one shipping model worth copying from: a **note** holds the fact (fields), **cards**
are generated practice units (note × direction), and **revlog** is an append-only review
log per card. LearnWords already mirrors revlog (`ReviewEvent`); the synset plays the
note's role, and (synset × direction × language pair) plays the card's — computed at
practice time rather than materialised, which suits a schema where languages per set
can grow.

## Mapping the owner's asks onto the schema

| Owner's ask | Schema element |
|---|---|
| Word as atomic entity, per language | `Term` (text, languageCode, transcription, partOfSpeech) |
| Lexical attributes, extensible | attributes on `Term`; `WordForm` rows (additive, mirrors `d:index`) |
| Comments for context during testing | `Comment` → term; `Synset.note` for sense disambiguation (see below) |
| Illustrations, local or remote URLs | `Illustration` (urlString) → term |
| Share a word among sets | `Term` ↔ `Synset` and `Synset` ↔ `WordSet` are many-to-many |
| Language tuples, not only pairs | `Synset` links any number of terms in any languages |
| Several definitions, any accepted | several same-language terms in one synset — all valid answers |
| Answer from another thematic: right-with-warning | judged at answer time against *other* synsets of the prompt term; recorded as `correctJudged` with a verdict coefficient — policy, not schema |
| Multilingual sets, choose study language | `WordSet.languageCodes: [String]`; the session picks (primary, secondary) |
| "primary/secondary" over "native/foreign" | renamed in `LanguagePair` and `ReviewDirection` (receptive/productive) |

**Why `Synset.note` exists alongside `Comment`:** a comment hangs off a *term* (usage,
register, etymology). But "which meaning do I want here?" is a property of the *sense* —
a term-level comment cannot disambiguate two synsets sharing the term. Apple's format
makes the same split: sense-level definitions vs entry-level syntax notes.

**Why sets do not name a primary language:** roles are assigned by the practice
session, not the data — the owner's own observation ("when you switch practice
direction you don't switch your native language"). A set declares what languages it
covers; *whose* primary is primary is the user's setting at practice time. This also
survives future set-sharing, where two users of one set have different primaries.

## Event-log consequences (append-only — decided now or never)

- `ReviewEvent` links to the **synset** (the fact practised), not a word pair.
- New snapshot fields, impossible to backfill later: **`promptLanguage`**,
  **`answerLanguage`** (direction alone is meaningless once a tuple holds >2
  languages), **`promptTermID`** (which synonym cued the question — prompt text can be
  edited later), **`wordSetID`** (which thematic framed the question — the
  different-set coefficient judging depends on it).
- `direction` becomes **receptive/productive** (Nation's terms, already the semantic
  content per `ProgressResearch.md` §1.4) instead of foreignToNative/nativeToForeign.
- **Nothing cascades into the log.** Deleting a synset or set nullifies the event's
  relationship; the event keeps its text/language snapshots and stays judgeable.
  The log outlives edits by design ("history heals").

## Deliberately store-level, not schema (iteration 2+)

- **Term dedup** on insert/import (uniqueness lives in code — CloudKit forbids unique
  constraints).
- **Orphan collection** — terms/synsets left unreferenced after set deletion; only
  collectable when they carry no events.
- **Parity check** when attaching a synset to a set (does it cover the set's languages)
  — validation, not constraint.
- **Illustration sync**: URL strings don't travel across devices for local files;
  the CloudKit-era answer is `CKAsset`/binary-with-external-storage — an additive
  schema change when needed.
- **Dictionary enrichment** — see TD-22 in [TechDebt](TechDebt.md). *(Correction,
  2026-07-23: an earlier version of this doc suggested `DCSCopyTextDefinition` — that
  API is **macOS-only**. On iOS, `UIReferenceLibraryViewController` displays system
  dictionaries but returns no data, and the owner's past experience confirms Apple
  pushes back on reflection-based extraction. Enrichment therefore comes from open
  data or a future macOS companion, not from the iOS system dictionary.)*

## Sense weights, domains and register (owner question, 2026-07-23)

What Apple's format actually has: senses are **ordered** (conventionally by frequency),
and `d:priority` marks what survives in the condensed lookup pane — display concerns,
not weights. Domain ("Medicine") and register ("slang", "informal", "dated") appear as
*labels on senses* in real dictionaries; wiktextract exposes the same as per-sense
topical/dialectal annotations. Lexicography keeps the two facets distinct — **register
is a characteristic of usage, not a theme**, which matches the owner's instinct — and
neither is a closed taxonomy.

Decision: a **`Tag` entity, many-to-many with `Synset`** — a folksonomy with an optional
facet convention ("slang" vs "domain:medicine"), not an enum the schema would have to
chase. No numeric sense weights (YAGNI): ordering emerges from the scoring policy and
set membership, and the wrong-thematic coefficient already keys off `wordSetID` + tags
at judge time.

*(Corrected the same day, owner review — Codd's information rule / 1NF.)* The first cut
was `tags: [String]` as a transformable attribute. That is a binary blob in one column:
SQLite predicates cannot see inside it (`ANY tags.name == "slang"` is impossible),
nothing can index it, and renaming a tag means rewriting every blob — an update anomaly.
Tags exist precisely to *filter* senses, so they are a **query dimension** and therefore
rows. The working rule for this schema, recorded for future fields:

> **If it will ever appear in a WHERE clause, it is a row. If it is opaque payload, a
> transformable is acceptable.**

Audit of the remaining transformables under that rule: `ReviewEvent.judgmentErrorTags`
stays — diagnostic payload on immutable events, read by `ScoringPolicy` over fetched
history, never a store-level filter. `WordSet.languageCodes` stays — display/validation
data over tens of sets, derivable from synset terms; revisit only if sets are ever
queried by language at scale. (Core Data itself is an object graph, not an RDBMS —
Codd's rules about ad-hoc query languages and views don't apply to it — but
normalization discipline does, because the SQLite store only optimises what the model
exposes.)

## Rejected alternatives

- **Word-pair entity (the first iteration-1 schema).** No synonyms, no third language
  ever, duplicates a word across sets, and encodes direction in the pair. Rejected by
  every source above; translation is a sense relation.
- **Per-language entry with embedded translation list.** Asymmetric (one language is
  privileged), and the same pair exists twice depending on entry language.
- **Materialised per-direction practice units (Anki cards as rows).** Right for Anki's
  fixed templates; wrong here, where directions multiply with set languages — computed
  practice units keep the schema stable.
