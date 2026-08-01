//
//  WordTableViewController.swift
//  LearnWords
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//
//  The words in the selected set. A row is a **meaning**, not a word pair: synonyms share
//  one row, because they are one thing to learn and one thing to score.
//

import UIKit

final class WordTableViewController: UITableViewController, UISearchResultsUpdating {

    private let library = Library.shared
    private var lexicon: Lexicon { library.lexicon }

    /// The meanings on screen, read once per appearance. A snapshot rather than a live
    /// fetch: the table must get the same answer from `numberOfRows` and `cellForRow`.
    private var senses: [Sense] = []
    private var filtered: [Sense] = []
    private var progress: ProgressIndex?

    private var rows: [Sense] { isSearching ? filtered : senses }

    /// Which languages the rows are displayed in — left column is the prompt side.
    private var languages: LanguagePair {
        library.selectedSet.map(LanguagePair.forSet) ?? .current
    }

    private let searchController = UISearchController(searchResultsController: nil)

    private var isSearching: Bool {
        searchController.isActive && (searchController.searchBar.text?.isEmpty != true)
    }

    // TODO: refactor to a factory func `uiImage(systemName: String)`
    private let resetProgressActionImage = UIImage.systemImage(["memories.badge.xmark", "memories"])
    private let editImage = UIImage.systemImage("pencil")
    private let deleteImage = UIImage.systemImage("trash")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupSearchController(placeholder: NSLocalizedString("Search words in sets",
                                                             comment: "placeholder"))

        // Import shared text on foregrounding and on the deep link too (see
        // consumePendingImport). Without these, a share made while the app was running
        // warm waited for an app relaunch (TD-3).
        NotificationCenter.default.addObserver(self, selector: #selector(pendingImportMayHaveArrived),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pendingImportMayHaveArrived),
                                               name: AppRoot.shareActionReceived, object: nil)

        // Words arriving from another device change the store, not this screen's snapshot.
        NotificationCenter.default.addObserver(self, selector: #selector(storeChangedRemotely),
                                               name: LWPersistence.storeDidChangeRemotely, object: nil)

        navigationItem.rightBarButtonItems?.insert(editButtonItem, at: 0)
        checkInstalledLocales()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Dynamic Type in the nav bar; the table's own fonts come from the cell.
        navigationController?.navigationBar.titleTextAttributes =
            [.font: UIFont.preferredFont(forTextStyle: .headline)]
        consumePendingImport()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reload()
        // Tapping a row speaks it, so ready the synthesiser now rather than making the
        // first tap pay for loading a voice and activating the session.
        SpeechManager.shared.prewarm(language: languages.secondary)
    }

    /// Adds a word and its meaning, as two steps of the **same** screen the meaning editor
    /// uses.
    ///
    /// It used to be a storyboard segue to `SearchWordViewController`, which meant the two
    /// ways into the app's vocabulary looked and behaved differently: a different accent
    /// colour, no dictation button, and a first section listing the original word that
    /// committed it *as its own translation* when tapped. One screen, so none of that can
    /// diverge again (TD-28).
    @IBAction func addWordTapped(_ sender: Any) {
        beginAddWord(prefilled: "")
    }

    private func beginAddWord(prefilled: String) {
        guard let set = library.selectedSet else { return }
        let pair = LanguagePair.forSet(set)
        let screen = WordInputViewController(.add(language: pair.secondary),
                                             initialText: prefilled) { [weak self] word in
            self?.askMeaning(of: word, in: set, pair: pair)
        }
        navigationController?.pushViewController(screen, animated: true)
    }

    /// Step two. Replaces step one on the stack rather than sitting on top of it, so Back
    /// returns to the word list — going back to "which word?" after answering it is a
    /// question nobody asked.
    private func askMeaning(of word: String, in set: WordSet, pair: LanguagePair) {
        // The word stays on screen while its meaning is typed. Without it the two steps are
        // visually identical and there is nothing to say which one you are on — the job the
        // old search screen's first section was doing (owner).
        let context = WordInputViewController.Context(
            caption: String(format: NSLocalizedString("Word in %@", comment: "Caption; a language"),
                            LanguageCode.displayName(pair.secondary)),
            term: word)
        let screen = WordInputViewController(
            .add(language: pair.primary),
            context: context,
            title: NSLocalizedString("Add meaning", comment: "Screen title")) { [weak self] meaning in
            guard let self else { return }
            do {
                try self.lexicon.addSense(to: set.id,
                                          terms: [Term.Draft(word, in: pair.secondary),
                                                  Term.Draft(meaning, in: pair.primary)])
                self.reload()
            } catch {
                debugLog("Could not add \(word): \(error)")
            }
        }
        guard let navigation = navigationController else { return }
        var stack = navigation.viewControllers
        if stack.last is WordInputViewController { stack.removeLast() }
        stack.append(screen)
        navigation.setViewControllers(stack, animated: true)
    }

    @IBAction func unwindSegue(segue: UIStoryboardSegue) {}

    // MARK: - Reading the set

    private func reload() {
        senses = (try? library.selectedSenses()) ?? []
        progress = try? ProgressIndex(lexicon: lexicon, senses: senses)
        if isSearching { filterRows(for: searchController.searchBar.text ?? "") }
        tableView.reloadData()
    }

    /// Reads one row's state back without disturbing the rest of the table.
    private func refreshRows(_ indexPaths: [IndexPath]) {
        progress = try? ProgressIndex(lexicon: lexicon, senses: senses)
        if #available(iOS 15.0, *) {
            tableView.reconfigureRows(at: indexPaths)
        } else {
            tableView.reloadRows(at: indexPaths, with: .automatic)
        }
    }

    // MARK: - Share-extension import (TD-3)

    /// Consumes text shared via the ImportAsDictAction extension, if any is pending.
    /// Idempotent (reads and clears the App-Group key), so it is safe to trigger from
    /// every path that can bring pending text: first load / tab switch (`viewWillAppear`)
    /// and foregrounding a warm app (`willEnterForegroundNotification` — the deep link
    /// `learnWords://shareaction` lands here after `AppRoot` selects this tab).
    private func consumePendingImport() {
        guard let text = userDefaultsGroup.string(forKey: "ImportedText") else { return }
        userDefaultsGroup.removeObject(forKey: "ImportedText")

        if text.aproxWordCount > 1 {
            guard let set = library.selectedSet else { return }
            let pair = LanguagePair.forSet(set)
            do {
                try lexicon.importPlainText(text, into: set.id,
                                            first: pair.secondary, second: pair.primary)
            } catch {
                debugLog("Shared-text import failed: \(error)")
            }
            reload()
        } else {
            // Async: navigating mid-appearance-transition is unreliable.
            let word = lemmas(from: text).first ?? text
            DispatchQueue.main.async { [weak self] in
                self?.beginAddWord(prefilled: word)
            }
        }
    }

    /// Re-reads when another device's changes land. Only while on screen — `viewDidAppear`
    /// covers every other case, and reloading a table nobody is looking at is wasted work.
    @objc private func storeChangedRemotely() {
        if viewIfLoaded?.window != nil { reload() }
    }

    /// Foreground / deep-link trigger. Only when visible: the single-word path segues,
    /// which needs an on-screen VC. If another tab is up, the pending import waits for
    /// this tab's next viewWillAppear (the deep link selects this tab, so that's imminent).
    @objc private func pendingImportMayHaveArrived() {
        if viewIfLoaded?.window != nil {
            consumePendingImport()
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "Word", for: indexPath)
                as? WordTableViewCell else { return UITableViewCell() }

        // A row already on screen is being *updated*, so its ring should spring; a row
        // being dequeued is being *configured*, so it should simply appear.
        let animated = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
        let sense = rows[indexPath.row]
        let pair = languages
        // Synonyms are one meaning, so they share a row rather than multiplying it.
        cell.leftTextLabel?.text = sense.terms(in: pair.secondary).map(\.text).joined(separator: ", ")
        cell.rightTextLabel?.text = sense.terms(in: pair.primary).map(\.text).joined(separator: ", ")
        let state = progress?[sense.id] ?? .unseen
        // Not animated on dequeue: the ring would travel from the recycled row's value.
        // `refreshRows` re-runs this after an answer, and *that* is where it springs.
        cell.progressView.setProgress(mastery: state.mastery, effort: state.effort,
                                      retention: state.retention, animated: animated)

        // Remove any existing gesture recognizers to avoid duplicates when cells are reused
        cell.gestureRecognizers?
            .filter { $0 is UILongPressGestureRecognizer }
            .forEach(cell.removeGestureRecognizer)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        cell.addGestureRecognizer(longPress)
        cell.isUserInteractionEnabled = true

        return cell
    }

    @objc private func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else { return }
        let touchPoint = gestureRecognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: touchPoint),
              let cell = tableView.cellForRow(at: indexPath) as? WordTableViewCell,
              let word = cell.leftTextLabel?.text else { return }
        lookUp(term: word, sender: self, location: touchPoint)
    }

    // MARK: - Table view delegate

    /// Speaks the word, and toggles the translation so the row can be used as a flashcard.
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let cell = tableView.cellForRow(at: indexPath) as? WordTableViewCell else { return }

        let pair = languages
        if let word = cell.leftTextLabel?.text {
            SpeechManager.shared.speak(NSAttributedString(string: word), language: pair.secondary)
        }
        let sense = rows[indexPath.row]
        cell.rightTextLabel?.text = (cell.rightTextLabel?.text?.isEmpty == false)
            ? ""
            : sense.terms(in: pair.primary).map(\.text).joined(separator: ", ")
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard !isSearching, let set = library.selectedSet else { return nil }
        let sense = rows[indexPath.row]

        let delete = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: "swipe action")) { [weak self] _, _, done in
                guard let self else { return done(false) }
                // Out of *this* set. The meaning may live in others, and its history is
                // evidence of work done — `deleteOrphanedSenses` collects the rest.
                try? self.lexicon.removeSense(sense.id, from: set.id)
                self.senses.removeAll { $0.id == sense.id }
                tableView.deleteRows(at: [indexPath], with: .automatic)
                done(true)
            }
        delete.image = deleteImage

        let edit = UIContextualAction(
            style: .normal,
            title: NSLocalizedString("Edit", comment: "swipe action")) { [weak self] _, _, done in
                self?.editMeaning(sense)
                done(true)
            }
        edit.backgroundColor = .systemTeal
        edit.image = editImage

        let config = UISwipeActionsConfiguration(actions: [delete, edit])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    override func tableView(_ tableView: UITableView,
                            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard !isSearching, let set = library.selectedSet else { return nil }

        let reset = UIContextualAction(
            style: .normal,
            title: NSLocalizedString("Reset", comment: "Swipe action: reset this word's learning progress"),
            backgroundColor: .systemOrange,
            image: resetProgressActionImage) { [weak self] _, _, done in
                guard let self else { return done(false) }
                // Appends a marker; the answers already given stay in the log.
                try? self.lexicon.resetProgress(ofSense: self.rows[indexPath.row].id, in: set.id)
                self.refreshRows([indexPath])
                done(true)
            }

        return UISwipeActionsConfiguration(actions: [reset])
    }

    /// Opens the meaning editor.
    ///
    /// Replaces an alert with two text fields, which could only edit the *first* word on
    /// each side and had no way to add or remove a synonym at all — so the model's
    /// headline feature was reachable only from the seed.
    private func editMeaning(_ sense: Sense) {
        let editor = MeaningEditorViewController(sense: sense,
                                                 languages: languages,
                                                 lexicon: lexicon) { [weak self] in
            self?.reload()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - Search

    /// Hands the search bar to the navigation item rather than parking it in the table
    /// header (TD-21).
    ///
    /// As a `tableHeaderView` it was scrolled just out of sight by nudging
    /// `contentOffset` — which worked while navigation bars were opaque. Under iOS 26 the
    /// bar is transparent and content flows beneath it, so the search field showed
    /// *through* the bar and collided with the floating "Settings" / "+" / "Edit"
    /// capsules. `navigationItem.searchController` lets UIKit place and collapse it,
    /// correctly on every version, and `hidesSearchBarWhenScrolling` replaces the offset
    /// hack. Both are iOS 11+, so they clear the 12.1 floor without a check.
    private func setupSearchController(placeholder: String = "", hideWhenAppear: Bool = true) {
        definesPresentationContext = true
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = placeholder
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = hideWhenAppear
    }

    /// Filters the loaded set, matching **inflected forms** through the store — typing
    /// "made" finds "make", which is why `WordForm` rows exist and what an in-memory
    /// `contains` could never do.
    ///
    /// Still scoped to the selected set: this screen is that set's list. `findTerms`
    /// searches every set, so its results are intersected with what is on screen.
    func filterRows(for searchText: String) {
        let needle = searchText.lowercased()
        let matched = Set((try? lexicon.findTerms(matching: searchText))?.map(\.id) ?? [])
        filtered = senses.filter { sense in
            sense.terms.contains { $0.text.lowercased().contains(needle) || matched.contains($0.id) }
        }
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        filterRows(for: searchController.searchBar.text ?? "")
    }

    // MARK: - Navigation

    // MARK: - Keyboards

    private func checkInstalledLocales() {
        let languageIDs = UITextInputMode.activeInputModes.compactMap { $0.primaryLanguage }
        let installed = Set(languageIDs.map { String($0.prefix(2)) })

        var message: String?
        let pair = LanguagePair.current
        if !installed.contains(String(pair.secondary.prefix(2))) {
            message = String(format: NSLocalizedString("Keyboard for language to study (%@) is not installed now. ", comment: "Alert message, langID inside"), pair.secondary)
        }
        if !installed.contains(String(pair.primary.prefix(2))) {
            message = (message ?? "") + String(format: NSLocalizedString("Keyboard for native learner's language (%@) is not installed now. ", comment: "Alert message, langID inside"), pair.primary)
        }
        guard var message else { return }
        message.append(NSLocalizedString("You may add Keyboards from system General Settings pane.", comment: "Alert message: how to add a missing keyboard, appended after the sentence above"))

        // If the user only has English and Emoji they won't be able to add translations.
        let ac = UIAlertController(
            title: NSLocalizedString("Check installed languages", comment: "Alert title"),
            message: message + NSLocalizedString("Looks like you only have those keyboards:", comment: "Alert message, langID appended") + languageIDs.joined(separator: ", "),
            preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""),
                                   style: .default) { _ in gotoAppSettings() })
        ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"),
                                   style: .cancel))
        present(ac, animated: true)
    }

    func lemmas(from str: String) -> [String] {
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType, .lemma], options: 0)
        let options: NSLinguisticTagger.Options = [.omitPunctuation, .omitWhitespace]
        let range = NSRange(location: 0, length: str.utf16.count)
        tagger.string = str
        var l = [String]()
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: options) { tag, _, _ in
            if let lemma = tag?.rawValue {
                l.append(lemma)
            }
        }
        return l
    }
}
