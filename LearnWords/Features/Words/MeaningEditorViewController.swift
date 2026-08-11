//
//  MeaningEditorViewController.swift
//  LearnWords
//
//  Editing one meaning: the words that express it, in each language, plus its note.
//
//  **This is the screen the lexical redesign was for.** Until it existed a meaning could
//  hold synonyms — the seed shows "fox / лиса, лисица" — but nothing in the app could
//  produce one: `Lexicon.addTerm` and `removeTerm` were called from no screen, and the
//  editor was two text fields in an alert that silently ignored every word after the
//  first. The data model supported synonyms; the user could not reach them.
//
//  A section per language rather than a fixed left/right pair, because a meaning is a
//  *language tuple* and a set may cover more than two (docs/Design.md). Adding a word in a
//  language the set does not yet list widens the set, which is `Lexicon.addTerm`'s job.
//
//  Built in code, like the other screens that were rewritten (`ExerciseViewController`,
//  `SettingsViewController`) — the storyboard holds only what has not been rebuilt yet.
//

import UIKit

final class MeaningEditorViewController: UITableViewController {

    private let lexicon: Lexicon
    private let languages: LanguagePair

    /// Re-read after every edit: a term's text can be shared, so editing one word here can
    /// change what another row of this screen displays.
    private var sense: Sense

    /// Called after any change, so the list behind this screen can refresh.
    private var onChange: (() -> Void)?

    /// The languages that get a section, in display order: the two being practised first,
    /// then anything else the meaning happens to cover.
    private var sectionLanguages: [String] = []

    init(sense: Sense, languages: LanguagePair, lexicon: Lexicon, onChange: (() -> Void)? = nil) {
        self.sense = sense
        self.languages = languages
        self.lexicon = lexicon
        self.onChange = onChange
        super.init(style: .grouped)
        title = NSLocalizedString("Edit meaning", comment: "Meaning editor screen title")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("use init(sense:languages:lexicon:onChange:)")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Cell.word)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Cell.action)
        rebuildSections()
    }

    private enum Cell {
        static let word = "word"
        static let action = "action"
    }

    /// A section per language the meaning covers, plus the practised pair even when one
    /// side is still empty — otherwise there would be nowhere to add the missing half.
    private func rebuildSections() {
        var codes = [languages.secondary, languages.primary].map(LanguageCode.canonical)
        for code in sense.languages.sorted() where !codes.contains(LanguageCode.canonical(code)) {
            codes.append(code)
        }
        sectionLanguages = codes
        tableView.reloadData()
    }

    private func words(in section: Int) -> [Term] {
        sense.terms(in: sectionLanguages[section])
    }

    /// Re-reads the meaning from the store and refreshes both this screen and the list
    /// that pushed it.
    private func reload() {
        if let fresh = try? lexicon.sense(sense.id) { sense = fresh }
        onChange?()
        rebuildSections()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sectionLanguages.count + 1        // + the note
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < sectionLanguages.count else {
            return NSLocalizedString("Note", comment: "Meaning editor section header")
        }
        return LanguageCode.displayName(sectionLanguages[section])
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == sectionLanguages.count else { return nil }
        return NSLocalizedString("Shown during practice when the word alone is ambiguous.",
                                 comment: "Meaning editor note footer")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < sectionLanguages.count ? words(in: section).count + 1 : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // The note.
        guard indexPath.section < sectionLanguages.count else {
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.word, for: indexPath)
            cell.textLabel?.text = sense.note ?? NSLocalizedString("Add a note", comment: "Meaning editor row")
            cell.textLabel?.textColor = sense.note == nil ? .lwAccent : .lwTextPrimary
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        let terms = words(in: indexPath.section)
        // The trailing "Add word" row.
        guard indexPath.row < terms.count else {
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.action, for: indexPath)
            cell.textLabel?.text = NSLocalizedString("Add word", comment: "Meaning editor row")
            cell.textLabel?.textColor = .lwAccent
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.accessoryType = .none
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: Cell.word, for: indexPath)
        cell.textLabel?.text = terms[indexPath.row].text
        cell.textLabel?.textColor = .lwTextPrimary
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.section < sectionLanguages.count else { return editNote() }

        let language = sectionLanguages[indexPath.section]
        let terms = words(in: indexPath.section)
        if indexPath.row < terms.count {
            editWord(terms[indexPath.row])
        } else {
            addWord(in: language)
        }
    }

    /// Only real words can be swiped away — not the "Add word" row, and not the note.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section < sectionLanguages.count
            && indexPath.row < words(in: indexPath.section).count
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let term = words(in: indexPath.section)[indexPath.row]
        do {
            // Unlinks the word from this meaning; the word itself survives for whatever
            // else uses it.
            sense = try lexicon.removeTerm(term.id, from: sense.id)
            onChange?()
            rebuildSections()
        } catch LexiconError.lastTerm {
            tableView.reloadRows(at: [indexPath], with: .automatic)
            presentNotice(
                title: NSLocalizedString("This is the only word", comment: "Alert title"),
                message: NSLocalizedString(
                    "A meaning needs at least one word. Delete the meaning itself if you no longer want it.",
                    comment: "Alert message"))
        } catch {
            debugLog("Could not remove \(term.text): \(error)")
        }
    }

    // MARK: - Editing

    /// Every edit here pushes `WordInputViewController` rather than raising an alert.
    ///
    /// The alert it replaces could hold a text field and nothing else, so the completions,
    /// the dictionary lookup and the dictation button — all of which belong exactly here,
    /// where a learner is reaching for a word they half-remember — had nowhere to go. It is
    /// the same screen the add-word flow uses, so the two entry paths cannot drift.
    private func addWord(in language: String) {
        push(.add(language: language),
             existingUsages: { [weak self] typed in
                 ((try? self?.lexicon.usages(ofTerm: typed, in: language)) ?? [])
                     .filter { $0.senseID != self?.sense.id }
             }) { [weak self] entered in
            guard let self else { return }
            do {
                // **A comma here means synonyms, not new meanings** (TD-53). Everywhere on
                // the way *in* a comma proposes separate meanings, but this meaning already
                // exists and owns its `ReviewEvent` log — splitting it would leave the
                // history on one half and none on the other. Adding words to the meaning
                // being edited is the only reading that cannot lose anything.
                for word in SenseEntry.words(in: entered) {
                    // Links an existing word when the spelling already exists, rather than
                    // making a twin — the point of an atomic term (TD-18).
                    self.sense = try self.lexicon.addTerm(Term.Draft(word, in: language),
                                                          to: self.sense.id)
                }
                self.reload()
            } catch {
                debugLog("Could not add \(entered): \(error)")
            }
        }
    }

    private func editWord(_ term: Term) {
        push(.rename(term), initialText: term.text,
             existingUsages: { [weak self] typed in
                 // The word being renamed is not a clash with itself.
                 ((try? self?.lexicon.usages(ofTerm: typed, in: term.language)) ?? [])
                     .filter { $0.senseID != self?.sense.id }
             }) { [weak self] entered in
            self?.rename(term, to: entered)
        }
    }

    /// Renames, unless the new spelling already exists — in which case the learner decides
    /// whether the two words are the same word.
    ///
    /// `updateTerm` edits the row in place, so renaming "bruin" to "bear" where "bear"
    /// already exists would leave **two rows spelled the same** — exactly what
    /// `findOrCreateTerm` prevents everywhere else. Merging is the only sensible resolution
    /// here: unlike the add flow there is no second meaning to create, just one meaning
    /// being edited and a question of which word it should use.
    private func rename(_ term: Term, to entered: String) {
        let clash = ((try? lexicon.usages(ofTerm: entered, in: term.language)) ?? [])
            .filter { $0.senseID != sense.id }

        guard let existing = clash.first else {
            // Every meaning and set using this word sees the change — an atomic term.
            try? lexicon.updateTerm(term.id, text: entered)
            return reload()
        }

        DuplicateWordPrompt.ask(on: self, word: entered, existing: existing,
                                offering: [.useExisting]) { [weak self] _ in
            guard let self else { return }
            do {
                self.sense = try self.lexicon.replaceTerm(
                    term.id, with: Term.Draft(entered, in: term.language), inSense: self.sense.id)
                self.reload()
            } catch {
                debugLog("Could not merge \(entered): \(error)")
            }
        }
    }

    private func editNote() {
        push(.note, initialText: sense.note ?? "") { [weak self] entered in
            guard let self else { return }
            try? self.lexicon.updateSense(self.sense.id, note: entered)
            self.reload()
        }
    }

    private func push(_ purpose: WordInputViewController.Purpose,
                      initialText: String = "",
                      existingUsages: ((String) -> [Lexicon.TermUsage])? = nil,
                      onCommit: @escaping (String) -> Void) {
        let screen = WordInputViewController(purpose, initialText: initialText,
                                             existingUsages: existingUsages, onCommit: onCommit)
        navigationController?.pushViewController(screen, animated: true)
    }

    private func presentNotice(title: String, message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(ac, animated: true)
    }
}
