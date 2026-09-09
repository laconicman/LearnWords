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
        let screen = WordInputViewController(
            .add(language: pair.secondary),
            initialText: prefilled,
            existingUsages: { [weak self] typed in
                (try? self?.lexicon.usages(ofTerm: typed, in: pair.secondary)) ?? []
            }) { [weak self] word in
            self?.askMeaning(of: word, in: set, pair: pair)
        }
        navigationController?.pushViewController(screen, animated: true)
    }

    /// Step two, **pushed** on top of step one.
    ///
    /// It used to replace step one via `setViewControllers`, on the reasoning that going
    /// back to "which word?" after answering it is a question nobody asked. In use it is:
    /// Back from the meaning threw away the word too and returned to the list, so a typo in
    /// the word — noticed exactly when you write its meaning — cost the whole entry. Back
    /// now returns to the word, which is what the storyboard-wired app did (owner,
    /// 2026-08-09).
    private func askMeaning(of word: String, in set: WordSet, pair: LanguagePair) {
        let screen = WordInputViewController(
            .add(language: pair.primary),
            context: meaningContext(for: word, pair: pair),
            title: NSLocalizedString("Add meaning", comment: "Screen title")) { [weak self] meaning in
            guard let self else { return }
            self.storePair(word, meaning: meaning, in: set, pair: pair)
        }
        navigationController?.pushViewController(screen, animated: true)
    }

    /// The word, pinned above the field while its meaning is typed.
    ///
    /// Without it the two steps are visually identical and there is nothing to say which one
    /// you are on — the job the old search screen's first section was doing (owner). Shared
    /// with `resumeEntry`, so a rebuilt step two looks like the one it replaces.
    private func meaningContext(for word: String, pair: LanguagePair) -> WordInputViewController.Context {
        WordInputViewController.Context(
            caption: String(format: NSLocalizedString("Word in %@", comment: "Caption; a language"),
                            LanguageCode.displayName(pair.secondary)),
            term: word)
    }

    /// Stores what was typed — after asking, when what was typed is ambiguous.
    ///
    /// Two different questions can arise here, and only one of them at a time:
    ///
    /// * **A comma put more than one word on a side** (TD-53). `лиса, лисица` is one meaning
    ///   with two synonyms and `берег, банк` is two meanings, and nothing in the text tells
    ///   them apart — so the proposal is laid out on `SenseEntryViewController`, as synonyms
    ///   by default, with one control to separate them. The duplicate question below is not
    ///   also asked there: the learner is already being shown what will be stored, and is
    ///   the one saying how many meanings it is.
    /// * **The word is already in the library.** The store deduplicates *words*: adding
    ///   "bear" twice links the existing row rather than making a twin. It does not
    ///   deduplicate **meanings**, so adding bear/медведь twice produced two meanings sharing
    ///   both words — one word listed twice, with its review history split between them.
    ///   Nothing below the UI can tell a mistake from a word that genuinely has two
    ///   meanings, so the question is asked here and the store stays free of policy.
    private func storePair(_ word: String, meaning: String, in set: WordSet, pair: LanguagePair) {
        let proposed = SenseEntry.proposals(SenseEntry.Side(word, in: pair.secondary),
                                            SenseEntry.Side(meaning, in: pair.primary))
        // Punctuation and nothing else — "a word with no letters is not a word", and there
        // is nothing here to store or to ask about.
        guard let only = proposed.first else { return }
        guard !only.hasSynonyms else { return confirmMeanings(proposed, in: set, pair: pair) }

        // **The word as it will be stored, not as it was typed.** `SenseEntry` trims and
        // drops empty parts, so "bank," is stored as "bank" — and asking the store about
        // "bank," matches nothing, which silently skipped the duplicate question for the
        // one word it exists to ask about.
        let typed = only.words(in: pair.secondary).first ?? word
        let existing = (try? lexicon.usages(ofTerm: typed, in: pair.secondary)) ?? []

        guard let clash = existing.first else {
            commit([only], in: set)
            return unwindToList()
        }
        // Asked *after* unwinding: this screen is two pushes down while the entry is being
        // typed, and presenting from a view that is not in the window is how an alert
        // becomes a line in the log instead.
        unwindToList { [weak self] in
            self?.askAboutDuplicate(only, word: typed, meaning: meaning,
                                    in: set, pair: pair, existing: clash)
        }
    }

    /// Puts the learner back where they were typing, with both words still in place.
    ///
    /// **Cancelling must not cost the entry.** Because the flow is torn down before the
    /// duplicate question is asked — it has to be, or the alert has no visible screen to
    /// come from — backing out of that question would otherwise land on the word list with
    /// everything typed silently gone. Rebuilding both steps is what makes Cancel mean
    /// "let me change it" rather than "throw it away".
    private func resumeEntry(word: String, meaning: String, in set: WordSet, pair: LanguagePair) {
        guard let navigation = navigationController else { return }
        let wordStep = WordInputViewController(
            .add(language: pair.secondary),
            initialText: word,
            existingUsages: { [weak self] typed in
                (try? self?.lexicon.usages(ofTerm: typed, in: pair.secondary)) ?? []
            }) { [weak self] entered in
            self?.askMeaning(of: entered, in: set, pair: pair)
        }
        let meaningStep = WordInputViewController(
            .add(language: pair.primary),
            initialText: meaning,
            context: meaningContext(for: word, pair: pair),
            title: NSLocalizedString("Add meaning", comment: "Screen title")) { [weak self] entered in
            self?.storePair(word, meaning: entered, in: set, pair: pair)
        }
        // Both steps at once, so Back from the meaning still reaches the word.
        navigation.setViewControllers(
            navigation.viewControllers + [wordStep, meaningStep], animated: true)
    }

    /// Takes the entry screens off the stack, and runs `then` once they are actually gone.
    ///
    /// The add flow is `list → word → meaning` since Back started returning to the word
    /// (TD-53). Storing used to be the end of it because the meaning step popped itself onto
    /// the list; now it pops onto the *word* step, which greets the learner with the word
    /// they just filed and a live Save button — tapping it a second time files it twice.
    /// Finishing an entry has to unwind the whole flow, not one screen of it.
    ///
    /// **This runs inside a screen that is about to pop itself**, and the two do not fight
    /// only because `viewControllers` updates synchronously: by the time
    /// `WordInputViewController.commit` re-checks `topViewController === self`, this has
    /// already taken it off the stack, so its own pop is skipped. `SenseEntryViewController`
    /// ends the same way. Said out loud because it is the kind of thing a later edit can
    /// quietly break, and the symptom would be the word list popping off its own tab.
    private func unwindToList(then: @escaping () -> Void = {}) {
        guard let navigation = navigationController, navigation.topViewController !== self else {
            return then()
        }
        navigation.popToViewController(self, animated: true)
        guard let coordinator = navigation.transitionCoordinator else {
            // No coordinator to wait on — a pop coalesced with another transition, say.
            // Still not *this* turn of the runloop: running `then` here would present from a
            // view that has just been told to leave the window, which is the exact symptom
            // waiting was added to remove.
            return DispatchQueue.main.async(execute: then)
        }
        coordinator.animate(alongsideTransition: nil) { _ in then() }
    }

    /// Shows the proposed split and stores whatever comes back from it.
    ///
    /// Returns to the word list rather than to the meaning step: the entry is finished, and
    /// the two screens that asked for it have been answered.
    private func confirmMeanings(_ proposed: [SenseEntry], in set: WordSet, pair: LanguagePair) {
        let screen = SenseEntryViewController(
            proposals: proposed,
            languages: pair,
            existingUsages: { [weak self] typed, language in
                (try? self?.lexicon.usages(ofTerm: typed, in: language)) ?? []
            }) { [weak self] confirmed in
            guard let self else { return }
            self.commit(confirmed, in: set)
            self.unwindToList()
        }
        navigationController?.pushViewController(screen, animated: true)
    }

    private func commit(_ entries: [SenseEntry], in set: WordSet) {
        do {
            try lexicon.addSenses(to: set.id, terms: entries.map(\.terms))
            reload()
        } catch {
            debugLog("Could not add \(entries.flatMap { $0.terms.map(\.text) }): \(error)")
        }
    }

    /// Asked, not decided — nothing below the UI can tell a mistake from a word that
    /// genuinely means two things. The wording and the answers live in
    /// `DuplicateWordPrompt`, shared with the meaning editor.
    private func askAboutDuplicate(_ entry: SenseEntry,
                                   word: String,
                                   meaning: String,
                                   in set: WordSet,
                                   pair: LanguagePair,
                                   existing: Lexicon.TermUsage) {
        DuplicateWordPrompt.ask(
            on: self, word: word, existing: existing,
            offering: [.replaceExisting, .addAnother],
            onCancel: { [weak self] in
                self?.resumeEntry(word: word, meaning: meaning, in: set, pair: pair)
            }) { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .replaceExisting:
                do {
                    try self.lexicon.replaceTerms(
                        ofSense: existing.senseID,
                        in: pair.primary,
                        with: entry.words(in: pair.primary).map { Term.Draft($0, in: pair.primary) })
                    self.reload()
                } catch {
                    debugLog("Could not replace the meaning of \(word): \(error)")
                }
            case .addAnother:
                self.commit([entry], in: set)
            case .useExisting:
                break   // not offered here
            }
        }
    }

    @IBAction func unwindSegue(segue: UIStoryboardSegue) {}

    // MARK: - Reading the set

    private func reload() {
        senses = (try? library.selectedSenses()) ?? []
        progress = try? ProgressCache.shared.index(for: senses, in: lexicon)
        if isSearching { filterRows(for: searchController.searchBar.text ?? "") }
        tableView.reloadData()
    }

    /// Reads one row's state back without disturbing the rest of the table.
    private func refreshRows(_ indexPaths: [IndexPath]) {
        progress = try? ProgressCache.shared.index(for: senses, in: lexicon)
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
            var summary = Lexicon.ImportSummary()
            do {
                summary = try lexicon.importPlainText(text, into: set.id,
                                                      first: pair.secondary, second: pair.primary)
            } catch {
                debugLog("Shared-text import failed: \(error)")
            }
            reload()
            presentImportSummary(summary)
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

        // **Only below iOS 13.** From 13 the same press opens a context menu, and two
        // recognisers for one gesture means whichever fires first wins (TD-50).
        if #available(iOS 13, *) {} else {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.3
            cell.addGestureRecognizer(longPress)
        }
        cell.isUserInteractionEnabled = true

        // **A gesture VoiceOver cannot make.** A long press is invisible to it, and the
        // context menu is reachable only through the rotor, so both destinations are named
        // here as well (docs/MasteryAndProgressUI.md §2.1).
        cell.accessibilityCustomActions = [
            SenseAction(name: NSLocalizedString("Statistics", comment: "Context menu action"),
                        senseID: sense.id,
                        target: self, selector: #selector(showStatisticsForAccessibleRow(_:))),
            SenseAction(name: String(format: NSLocalizedString("Look up %@",
                                                               comment: "Button label; a word"),
                                     sense.terms(in: pair.secondary).first?.text ?? ""),
                        senseID: sense.id,
                        target: self, selector: #selector(lookUpAccessibleRow(_:))),
        ]

        return cell
    }

    /// The iOS 12 path: the same press, opening the same screen.
    @objc private func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began, !tableView.isEditing else { return }
        let touchPoint = gestureRecognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: touchPoint),
              indexPath.row < rows.count else { return }
        showStatistics(for: rows[indexPath.row])
    }

    // MARK: - Per-term statistics (TD-50)

    /// Everything the log knows about one meaning, which the ring can only summarise.
    ///
    /// Built from the snapshot the table is already drawing rather than from a fresh fetch:
    /// the screen is a reading of the log at the moment it was opened, and reading it twice
    /// would let the row and its detail disagree.
    /// - Parameter offersLookUp: `false` for a context-menu preview, which is not
    ///   interactive — the row would be pure extra height, and height is the clipping problem
    ///   on that path. The menu offers the action beside the preview instead.
    private func makeStatistics(for sense: Sense,
                                offersLookUp: Bool) -> SenseStatisticsViewController {
        SenseStatisticsViewController(
            sense: sense,
            progress: progress?[sense.id] ?? .unseen,
            languages: languages,
            offersLookUp: offersLookUp)
    }

    private func showStatistics(for sense: Sense) {
        navigationController?.pushViewController(
            makeStatistics(for: sense, offersLookUp: true), animated: true)
    }

    /// An accessibility action that remembers *which meaning* it belongs to.
    ///
    /// Not an index path: cells are reused and rows are re-sorted by search, so a captured
    /// position is stale the moment the table reloads while an identity is not. UIKit gives
    /// the handler nothing but the action itself, so the action has to carry it.
    private final class SenseAction: UIAccessibilityCustomAction {
        let senseID: UUID

        init(name: String, senseID: UUID, target: Any?, selector: Selector) {
            self.senseID = senseID
            super.init(name: name, target: target, selector: selector)
        }
    }

    private func sense(of action: UIAccessibilityCustomAction) -> Sense? {
        guard let action = action as? SenseAction else { return nil }
        return rows.first { $0.id == action.senseID }
    }

    @objc private func showStatisticsForAccessibleRow(_ action: UIAccessibilityCustomAction) -> Bool {
        guard let sense = sense(of: action) else { return false }
        showStatistics(for: sense)
        return true
    }

    @objc private func lookUpAccessibleRow(_ action: UIAccessibilityCustomAction) -> Bool {
        guard let word = sense(of: action)?.terms(in: languages.secondary).first?.text
        else { return false }
        lookUp(term: word, sender: self)
        return true
    }

    /// The platform answer for "show me more about this item" (iOS 13+), and the reason the
    /// gesture is a long press rather than a swipe: trailing swipe is taken by rename and
    /// delete, and a swipe acts on a row rather than inspecting it.
    @available(iOS 13, *)
    override func tableView(_ tableView: UITableView,
                            contextMenuConfigurationForRowAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
        guard !tableView.isEditing else { return nil }
        return UIContextMenuConfiguration(
            identifier: nil,
            // The statistics *are* the preview. Choosing this gesture over a sheet was for
            // exactly this: it can show something, not only offer actions.
            previewProvider: { [weak self] in
                guard let self, indexPath.row < self.rows.count else { return nil }
                return self.makeStatistics(for: self.rows[indexPath.row], offersLookUp: false)
            },
            actionProvider: { [weak self] _ in
                guard let self, indexPath.row < self.rows.count,
                      let word = self.rows[indexPath.row]
                          .terms(in: self.languages.secondary).first?.text
                else { return nil }
                return UIMenu(title: "", children: [
                    UIAction(title: String(format: NSLocalizedString("Look up %@",
                                                                     comment: "Button label; a word"),
                                           word),
                             image: .systemImage("character.book.closed")) { [weak self] _ in
                        guard let self else { return }
                        lookUp(term: word, sender: self)
                    },
                ])
            })
    }

    /// Tapping the preview opens the real screen, which is what a preview promises.
    @available(iOS 13, *)
    override func tableView(_ tableView: UITableView,
                            willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                            animator: UIContextMenuInteractionCommitAnimating) {
        guard let preview = animator.previewViewController as? SenseStatisticsViewController,
              let sense = rows.first(where: { $0.id == preview.senseID }) else { return }
        // Not the preview instance: it was built without the lookup row, which the real
        // screen should have. Rebuilt rather than mutated, so the two paths differ in exactly
        // one argument.
        animator.addCompletion { [weak self] in
            self?.showStatistics(for: sense)
        }
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
