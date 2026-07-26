//
//  LanguageCode.swift
//  LearnWords
//
//  How a language is spelled in the store, and what happens to the rest of a BCP-47 tag.
//
//  **The stored code is a bare language subtag, Wiktionary-shaped** — `en`, `ru`, `zh`,
//  `haw`. Two letters where ISO 639-1 has a code, three where it does not; that mix is
//  BCP 47's shortest-code rule, not an inconsistency. Region and script are *not* part of
//  a language's identity here: `en-US`, `en-GB` and `en` are one language, and so are
//  `zh-Hans` and `zh-Hant`.
//
//  **Why Wiktionary rather than Apple** (owner, 2026-07-26): the enrichment corpora we
//  intend to read speak it, and it is internally consistent. Verified against the live
//  registry (`Module:languages/data/2`, 177 two-letter codes) rather than assumed — which
//  caught two cases Apple would have got wrong for us:
//
//  * `iw`, `in`, `ji`, `jw`, `mo` do not exist in Wiktionary, so they must resolve to
//    `he`, `id`, `yi`, `jv`, `ro`. Left alone they would be *second rows* for languages we
//    already have — the duplicate-row problem this type exists to prevent.
//  * `no`, `nb` and `nn` are three distinct Wiktionary languages. `Locale`
//    canonicalises `no` → `nb`; doing the same here would merge two of them.
//
//  **One deliberate divergence.** Wiktionary folds Bosnian, Croatian and Serbian into
//  Serbo-Croatian (`m["sh"]`, `wikimedia_codes = "sh, bs, hr, sr"`). We keep `hr`, `sr`
//  and `bs` apart: iOS, the keyboard and the learner all call them separate languages, and
//  showing someone "Serbo-Croatian" for their own word set is a worse outcome than a
//  slightly harder enrichment lookup. Wiktionary's registry marks that seam itself — it
//  records `ietf_subtag = "hbs"` because `sh` is ISO-deprecated. When enrichment lands
//  (TD-22), the mapping belongs on the `Language` row, which is where a per-language
//  `wiktionaryCode` can live.
//
//  **Why a table of our own rather than `Locale`.** The stored code is an identity that
//  syncs between devices, so it must not depend on which OS computed it. `Locale`'s
//  answers come from the ICU/CLDR data bundled with the system — they differ by iOS
//  version, and its three entry points disagree with each other today: for `iw`,
//  `canonicalLanguageIdentifier` says `he`, `components(fromIdentifier:)` says `iw`, and
//  `Locale.Language.languageCode` says `iw`. `Locale` is for *display names* and *voice
//  lookup*; identity is decided here.
//

import Foundation

enum LanguageCode {

    /// A BCP-47 tag taken apart: the language we store, and the rest.
    struct Parsed: Equatable {
        /// The stored language code — Wiktionary-shaped, lowercased.
        let language: String
        /// The script, region and variant subtags that are not part of the language's
        /// identity: "US", "Hans", "Latn-RS". `nil` when the tag was bare.
        ///
        /// Nothing reads this yet. It is returned rather than discarded because dropping
        /// part of the input silently is how "en-US" and "en" became two rows in the first
        /// place — and because it is what a `Variety` row will be built from.
        let variety: String?
    }

    /// Codes Wiktionary does not use, mapped to the ones it does.
    ///
    /// Only genuine absences: every entry here was confirmed missing from the live
    /// registry. Codes that merely *look* redundant (`no`/`nb`, `tl`/`fil`, `sh`) are
    /// absent from this table on purpose — Wiktionary keeps them distinct.
    private static let aliases: [String: String] = [
        "iw": "he",     // ISO 639-1 withdrew iw for Hebrew
        "in": "id",     // ...and in for Indonesian
        "ji": "yi",     // ...and ji for Yiddish
        "jw": "jv",     // ...and jw for Javanese
        "mo": "ro",     // Moldovan is catalogued as Romanian
        "cmn": "zh",    // Mandarin entries live under ==Chinese== (wikimedia_codes = "zh")
    ]

    /// Splits a tag into the language we store and the variety we do not.
    ///
    /// Accepts anything the system might hand us: `en-US`, `en_US`, `EN-us`, `zh-Hans`,
    /// `sr-Latn-RS`, `ar-001`. An unrecognised language subtag is kept as-is rather than
    /// rejected — a word in a language this build has never heard of is still a word.
    static func parse(_ tag: String) -> Parsed {
        let subtags = tag.split { $0 == "-" || $0 == "_" }
        guard let first = subtags.first else {
            return Parsed(language: tag.lowercased(), variety: nil)
        }
        let subtag = first.lowercased()
        let variety = subtags.dropFirst().map(normalized).joined(separator: "-")
        return Parsed(language: aliases[subtag] ?? subtag,
                      variety: variety.isEmpty ? nil : variety)
    }

    /// The language a tag names. The only thing that reaches the store.
    static func canonical(_ tag: String) -> String {
        parse(tag).language
    }

    /// BCP-47 casing, so the same variety spelled two ways compares equal: script is
    /// title case (`Hans`), region upper (`US`, `001`), variant lower (`valencia`).
    private static func normalized(_ subtag: Substring) -> String {
        switch subtag.count {
        case 4: return subtag.prefix(1).uppercased() + subtag.dropFirst().lowercased()
        case 2, 3: return subtag.uppercased()
        default: return subtag.lowercased()
        }
    }
}
