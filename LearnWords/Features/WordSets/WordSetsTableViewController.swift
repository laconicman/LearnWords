//
//  WordSetsTableViewController.swift
//  LearnWords
//
//  Created by  Paul on 18.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//
//  The sets: pick one to study, add, delete, and move words in and out as plain text.
//

import UIKit
import MobileCoreServices

final class WordSetsTableViewController: UITableViewController, UIDocumentPickerDelegate {

    private let library = Library.shared
    private var lexicon: Lexicon { library.lexicon }

    /// The rows, read once per appearance. A snapshot rather than a live fetch: the table
    /// must not ask the store for a different answer between `numberOfRows` and
    /// `cellForRow`, which is how a background merge turns into an index crash.
    private var sets: [WordSet] = []

    private let renameImage = UIImage.systemImage("pencil")
    private let deleteImage = UIImage.systemImage("trash")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = false
        // A set created on another device should appear here without leaving the tab.
        NotificationCenter.default.addObserver(self, selector: #selector(storeChangedRemotely),
                                               name: LWPersistence.storeDidChangeRemotely, object: nil)
    }

    @objc private func storeChangedRemotely() {
        if viewIfLoaded?.window != nil { reload() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reload()
    }

    private func reload() {
        sets = (try? lexicon.wordSets()) ?? []
        tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sets.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "wordSetsCell", for: indexPath)
        let set = sets[indexPath.row]

        cell.textLabel?.text = set.name
        cell.detailTextLabel?.text = summary(of: set)

        let isSelected = set.id == library.selectedSet?.id
        cell.accessoryType = isSelected ? .checkmark : .none
        if isSelected {
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        return cell
    }

    /// "Total 12 words. Learned 3." — the count comes off the set itself; "learned" is
    /// `ScoringPolicy`'s mastery reaching the horizon.
    private func summary(of set: WordSet) -> String {
        let learned = (try? lexicon.senses(in: set.id))
            .flatMap { try? ProgressIndex(lexicon: lexicon, senses: $0) }?
            .learnedCount ?? 0

        return NSLocalizedString("Total ", comment: "Label total words")
            + pluralizedWordCount(set.senseCount) + ". "
            + NSLocalizedString("Learned ", comment: "Label learned words")
            + pluralizedWordCount(learned) + "."
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        library.select(sets[indexPath.row])
        tableView.reloadData()          // the checkmark moved off another row too
        tabBarController?.selectedIndex = 0
    }

    /// Delete and rename on swipe.
    ///
    /// **Both, because providing this method replaces the default swipe-to-delete** that
    /// `commit editingStyle:` gives for free. Adding rename alone removed delete — and
    /// this screen has no Edit button, so there was no other way to reach it.
    ///
    /// `Lexicon.renameWordSet` existed from the start and no screen called it; a set's
    /// name was fixed at creation until now.
    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let set = sets[indexPath.row]

        let delete = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: "swipe action")) { [weak self] _, _, done in
                self?.deleteSet(at: indexPath)
                done(true)
            }
        delete.image = deleteImage

        let rename = UIContextualAction(
            style: .normal,
            title: NSLocalizedString("Rename", comment: "Swipe action: rename this word set")) { [weak self] _, _, done in
                self?.promptForRename(of: set)
                done(true)
            }
        rename.backgroundColor = .systemTeal
        rename.image = renameImage

        let config = UISwipeActionsConfiguration(actions: [delete, rename])
        // Unlike a single meaning, a whole set is not something to lose to an overshot
        // swipe — the gesture has to land on the button.
        config.performsFirstActionWithFullSwipe = false
        return config
    }

    private func promptForRename(of set: WordSet) {
        let ac = UIAlertController(
            title: NSLocalizedString("Rename set", comment: "AlertController title"),
            message: nil, preferredStyle: .alert)
        ac.addTextField { $0.text = set.name; $0.clearButtonMode = .whileEditing }
        ac.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: "AlertAction title"),
                                   style: .default) { [weak self, weak ac] _ in
            guard let self,
                  let name = ac?.textFields?.first?.text?
                      .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { return }
            try? self.lexicon.renameWordSet(set.id, to: name)
            self.reload()
        })
        ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"),
                                   style: .cancel))
        present(ac, animated: true)
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        deleteSet(at: indexPath)
    }

    /// The meanings survive: they may live in other sets, and their history is evidence of
    /// work done. `Lexicon.deleteOrphanedSenses` collects the rest, deliberately (TD-26).
    private func deleteSet(at indexPath: IndexPath) {
        try? lexicon.deleteWordSet(sets[indexPath.row].id)
        sets.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        tableView.reloadData()          // the selection may have fallen back to another set
    }

    // MARK: - Adding

    @IBAction func addNewWordSet(_ sender: UIBarButtonItem) {
        let ac = UIAlertController(
            title: NSLocalizedString("Add new word set", comment: "AlertController title"),
            message: nil, preferredStyle: .alert)

        ac.addTextField { $0.placeholder = NSLocalizedString("Name of set", comment: "") }

        let submit = UIAlertAction(
            title: NSLocalizedString("Add", comment: "AlertAction title"),
            style: .default) { [weak self, weak ac] _ in
                guard let self, let name = ac?.textFields?.first?.text, !name.isEmpty else { return }
                // A new set covers the languages the user is studying; adding a word in a
                // third language widens it on its own.
                let pair = LanguagePair.current
                try? self.lexicon.addWordSet(named: name,
                                             languages: [pair.primary, pair.secondary])
                self.reload()
            }
        ac.addAction(submit)
        ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"),
                                   style: .cancel))
        present(ac, animated: true)
    }

    // MARK: - Export

    /// Two formats: ours, which imports back losslessly, and Anki's, which does not come
    /// back at all. Asking is the honest way to present that — a single button would have
    /// to pick one, and neither is the obvious default.
    @IBAction func exportToFile(_ sender: UIBarButtonItem) {
        guard let set = library.selectedSet,
              let senses = try? lexicon.senses(in: set.id), !senses.isEmpty else { return }
        let pair = LanguagePair.forSet(set)

        let sheet = UIAlertController(
            title: NSLocalizedString("Export as", comment: "Action sheet title, export format"),
            message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Plain text", comment: "Export format"),
            style: .default) { [weak self] _ in
                self?.share(PlainText.render(senses, from: pair.secondary, to: pair.primary),
                            named: set.name, from: sender)
            })

        // Not localised: Anki is a product name.
        sheet.addAction(UIAlertAction(title: "Anki", style: .default) { [weak self] _ in
            self?.share(AnkiText.render(senses, from: pair.secondary, to: pair.primary,
                                        deck: set.name),
                        named: set.name, from: sender)
        })

        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"),
                                      style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = sender
        present(sheet, animated: true)
    }

    private func share(_ text: String, named name: String, from sender: UIBarButtonItem) {
        // A set named "Travel/Food" would otherwise build a path into a directory that
        // does not exist, and the write would fail silently.
        let fileName = name.replacingOccurrences(of: "/", with: "-")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(fileName).txt")
        guard let data = text.data(using: .utf8), (try? data.write(to: url)) != nil else { return }

        let shareSheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        shareSheet.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        shareSheet.popoverPresentationController?.barButtonItem = sender
        present(shareSheet, animated: true)
    }

    // MARK: - Import

    @IBAction func importFromFile(_ sender: UIBarButtonItem) {
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeText as String],
                                                    in: .import)
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first, let set = library.selectedSet else { return }
        debugLog("importing: \(fileURL)")
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let pair = LanguagePair.forSet(set)
            try lexicon.importPlainText(text, into: set.id,
                                        first: pair.secondary, second: pair.primary)
            reload()
        } catch {
            debugLog("Import failed: \(error)")
            let alert = UIAlertController(
                title: NSLocalizedString("IMPORT_FAIL_TITLE", comment: "Title for failed import"),
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            present(alert, animated: true)
        }
    }
}
