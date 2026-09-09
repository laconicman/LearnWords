//
//  UIViewController+ImportSummary.swift
//  LearnWords
//
//  What an import did, said out loud (TD-59).
//
//  **Both import paths report through here, so they cannot drift.** Text arrives from a
//  picked file and from the share extension, and until now each finished by reloading a
//  table and saying nothing — so a file whose every line was a heading looked exactly like
//  one that imported cleanly. That silence is what let a parser bug that deleted every
//  hyphenated word survive unnoticed.
//

import UIKit

extension UIViewController {

    /// Reports an import, and stays quiet only when there is genuinely nothing to report.
    ///
    /// **Silent on a clean import**, because the list visibly grows behind the alert and a
    /// confirmation nobody needs is a tap nobody wanted. Anything else — a word already
    /// present, a line that could not be read, or an empty file — is the case the learner
    /// cannot see for themselves, and is worth interrupting for.
    func presentImportSummary(_ summary: Lexicon.ImportSummary) {
        guard summary.duplicates > 0 || summary.unreadable > 0 || summary.added == 0 else { return }

        var lines: [String] = []
        if summary.added > 0 {
            lines.append(String.localizedStringWithFormat(
                NSLocalizedString("ImportAddedCount", comment: "Import summary; words added"),
                summary.added))
        }
        if summary.duplicates > 0 {
            lines.append(String.localizedStringWithFormat(
                NSLocalizedString("ImportDuplicateCount",
                                  comment: "Import summary; already in the set"),
                summary.duplicates))
        }
        if summary.unreadable > 0 {
            lines.append(String.localizedStringWithFormat(
                NSLocalizedString("ImportUnreadableCount",
                                  comment: "Import summary; lines that are not a word pair"),
                summary.unreadable))
        }
        // An empty file parses to nothing at all, so neither branch above fires and the
        // alert would have a title and no body.
        if lines.isEmpty {
            lines.append(NSLocalizedString("Nothing in the file could be read as a word.",
                                           comment: "Import summary; empty result"))
        }

        let alert = UIAlertController(
            title: summary.added > 0
                ? NSLocalizedString("Imported", comment: "Import summary; alert title")
                : NSLocalizedString("Nothing imported", comment: "Import summary; alert title"),
            message: lines.joined(separator: "\n"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }
}
