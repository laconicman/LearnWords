//
//  SenseEntryViewController.swift
//  LearnWords
//
//  Confirming what a typed comma proposed, before any of it reaches the store (TD-53).
//
//  **A section per meaning, a row per word.** `MeaningEditorViewController` is the mirror
//  of this screen — it gives a section to each *language* because it edits one stored
//  meaning. Here the whole question is how many meanings there are, so the meanings are the
//  sections and the languages are groups of rows inside them.
//
//  **Each filled row is followed by an empty one** (owner, 2026-08-09), for another synonym;
//  and the meanings are followed by an empty section, for another meaning. That is what
//  makes the comma *optional* rather than the only way to say "two meanings" — the split it
//  triggers is a shortcut for something the screen can do on its own.
//
//  **Rows push `WordInputViewController` rather than editing in place.** The owner asked for
//  "input rows", and an inline `UITextField` per row is the obvious reading — but it is the
//  reading this codebase has already rejected once: completions, dictionary lookup and
//  dictation live on that screen, and the alert-with-a-text-field they replaced is exactly
//  what an inline field would bring back. The empty row is the affordance; the screen behind
//  it is the one every other entry path uses.
//
//  Store-free, like the input screen: it takes a proposal and hands back a confirmed one.
//  Nothing here may be pointed at a stored `Sense` — splitting one would strand its
//  `ReviewEvent` log (docs/LexicalModelResearch.md § *Commas at entry*).
//

import UIKit

final class SenseEntryViewController: UITableViewController {

    /// The meanings as they stand, edited in place by every action on this screen.
    private var proposals: [SenseEntry]

    /// The languages a meaning needs to be practisable, in display order: the studied
    /// language first, then the learner's own.
    private let sectionLanguages: [String]

    private let onCommit: ([SenseEntry]) -> Void

    /// Where a typed word already appears, asked per language. A closure rather than a
    /// `Lexicon`, so this screen stays store-free for the same reason `WordInputViewController`
    /// does — the moment it can query the store it starts deciding things the flow decides.
    private let existingUsages: ((String, String) -> [Lexicon.TermUsage])?

    /// Everything the table shows, rebuilt in one place.
    ///
    /// The same single-snapshot rule `WordInputViewController` documents: UIKit asks for
    /// counts and cells at different moments, and two arrays consulted separately are how
    /// *Index out of range* gets in.
    private var rows: [[Row]] = []

    private enum Row {
        /// A word already in the proposal: which language, and which of that language's words.
        case word(language: String, index: Int)
        /// The empty row that follows them.
        case addWord(language: String)
        /// Folds this meaning into the one above, turning both into synonyms of one meaning.
        case merge
        /// The empty section at the end.
        case addMeaning
    }

    init(proposals: [SenseEntry],
         languages: LanguagePair,
         existingUsages: ((String, String) -> [Lexicon.TermUsage])? = nil,
         onCommit: @escaping ([SenseEntry]) -> Void) {
        self.proposals = proposals
        self.sectionLanguages = [languages.secondary, languages.primary]
        self.existingUsages = existingUsages
        self.onCommit = onCommit
        super.init(style: .grouped)
        title = NSLocalizedString("Confirm meanings", comment: "Screen title")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("use init(proposals:languages:existingUsages:onCommit:)")
    }

    private enum Cell {
        static let word = "word"
        static let action = "action"
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Cell.word)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Cell.action)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Save", comment: "Bar button"),
            style: .done, target: self, action: #selector(commit))
        rebuildRows()
    }

    /// The one place the table's contents are built.
    private func rebuildRows() {
        var built: [[Row]] = proposals.enumerated().map { index, entry in
            var section: [Row] = []
            for language in sectionLanguages {
                for wordIndex in entry.words(in: language).indices {
                    section.append(.word(language: language, index: wordIndex))
                }
                section.append(.addWord(language: language))
            }
            // Nothing above the first meaning to merge into.
            if index > 0 { section.append(.merge) }
            return section
        }
        built.append([.addMeaning])
        rows = built
        // Save is a promise that every meaning is storable, so it goes out while one is not.
        navigationItem.rightBarButtonItem?.isEnabled = isStorable
        tableView.reloadData()
    }

    /// A meaning needs a word on **both** practised languages, or it cannot be asked in
    /// either direction — `Sense.canPractise` is the same rule, one layer down.
    private func isComplete(_ entry: SenseEntry) -> Bool {
        sectionLanguages.allSatisfy { !entry.words(in: $0).isEmpty }
    }

    private var isStorable: Bool {
        !proposals.isEmpty && proposals.allSatisfy(isComplete)
    }

    private func row(at indexPath: IndexPath) -> Row? {
        guard indexPath.section < rows.count,
              indexPath.row < rows[indexPath.section].count else { return nil }
        return rows[indexPath.section][indexPath.row]
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < rows.count ? rows[section].count : 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < proposals.count else { return nil }
        return String(format: NSLocalizedString("Meaning %d", comment: "Section header; a number"),
                      section + 1)
    }

    /// Two things worth saying at the bottom of a section, and never both: what a meaning is
    /// still missing, or — under the last one — what Save will do.
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section < proposals.count else {
            return String(format: NSLocalizedString("%d meanings will be created",
                                                    comment: "Footer; a count"),
                          proposals.count)
        }
        guard let missing = sectionLanguages.first(where: { proposals[section].words(in: $0).isEmpty })
        else { return nil }
        return String(format: NSLocalizedString("Needs a word in %@.",
                                                comment: "Footer; a language name"),
                      LanguageCode.displayName(missing))
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch row(at: indexPath) {
        case .word(let language, let index):
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.word, for: indexPath)
            configure(cell, text: proposals[indexPath.section].words(in: language)[index],
                      colour: .lwTextPrimary)
            cell.accessoryType = .disclosureIndicator
            return cell

        case .addWord(let language):
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.action, for: indexPath)
            // Named by language: a section holds two of these, and "Add word" twice says
            // nothing about which side is being added to.
            configure(cell, text: String(format: NSLocalizedString("Add a word in %@",
                                                                   comment: "Row; a language name"),
                                         LanguageCode.displayName(language)),
                      colour: .lwAccent)
            cell.accessoryType = .none
            return cell

        case .merge:
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.action, for: indexPath)
            configure(cell, text: NSLocalizedString("Merge into the meaning above",
                                                    comment: "Row"),
                      colour: .lwAccent)
            cell.accessoryType = .none
            return cell

        case .addMeaning:
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.action, for: indexPath)
            configure(cell, text: NSLocalizedString("Add another meaning", comment: "Row"),
                      colour: .lwAccent)
            cell.accessoryType = .none
            return cell

        case nil:
            // Unreachable while the counts come from `rows`, and cheaper than a trap if that
            // ever stops being true.
            return UITableViewCell()
        }
    }

    private func configure(_ cell: UITableViewCell, text: String, colour: UIColor) {
        cell.textLabel?.text = text
        cell.textLabel?.textColor = colour
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch row(at: indexPath) {
        case .word(let language, let index):
            editWord(at: index, in: language, ofMeaning: indexPath.section)
        case .addWord(let language):
            addWord(in: language, toMeaning: indexPath.section)
        case .merge:
            proposals = SenseEntry.merging(proposals, at: indexPath.section)
            rebuildRows()
        case .addMeaning:
            addMeaning()
        case nil:
            break
        }
    }

    /// Only real words can be swiped away.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if case .word = row(at: indexPath) { return true }
        return false
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              case .word(let language, let index) = row(at: indexPath) else { return }
        remove(wordAt: index, in: language, ofMeaning: indexPath.section)
    }

    // MARK: - Editing the proposal

    /// Removing a meaning's last word removes the meaning: an entry with nothing in it is
    /// not a meaning being edited, it is one being taken back.
    private func remove(wordAt index: Int, in language: String, ofMeaning meaning: Int) {
        guard proposals.indices.contains(meaning) else { return }
        let word = proposals[meaning].words(in: language)[index]
        if let position = proposals[meaning].terms.firstIndex(where: {
            $0.text == word && LanguageCode.canonical($0.language) == LanguageCode.canonical(language)
        }) {
            proposals[meaning].terms.remove(at: position)
        }
        if proposals[meaning].isEmpty { proposals.remove(at: meaning) }
        rebuildRows()
    }

    private func editWord(at index: Int, in language: String, ofMeaning meaning: Int) {
        let existing = proposals[meaning].words(in: language)[index]
        push(language: language,
             initialText: existing,
             title: NSLocalizedString("Edit word", comment: "Screen title")) { [weak self] entered in
            guard let self, self.proposals.indices.contains(meaning) else { return }
            // A comma typed *here* adds synonyms to this meaning. It cannot split: the row
            // being edited belongs to a meaning the learner has already laid out, and the
            // sections above are where meanings are added or removed.
            let replacements = SenseEntry.words(in: entered)
            guard !replacements.isEmpty else { return }
            self.replace(existing, in: language, ofMeaning: meaning, with: replacements)
        }
    }

    private func replace(_ word: String, in language: String, ofMeaning meaning: Int,
                         with replacements: [String]) {
        guard let position = proposals[meaning].terms.firstIndex(where: {
            $0.text == word && LanguageCode.canonical($0.language) == LanguageCode.canonical(language)
        }) else { return }
        proposals[meaning].terms.replaceSubrange(
            position...position, with: replacements.map { Term.Draft($0, in: language) })
        rebuildRows()
    }

    private func addWord(in language: String, toMeaning meaning: Int) {
        push(language: language,
             initialText: "",
             title: NSLocalizedString("Add word", comment: "Screen title")) { [weak self] entered in
            guard let self, self.proposals.indices.contains(meaning) else { return }
            self.proposals[meaning].terms
                .append(contentsOf: SenseEntry.words(in: entered).map { Term.Draft($0, in: language) })
            self.rebuildRows()
        }
    }

    /// A new meaning starts with the studied language, the same side the add-word flow asks
    /// for first; its footer then says what it still needs.
    private func addMeaning() {
        guard let language = sectionLanguages.first else { return }
        push(language: language,
             initialText: "",
             title: NSLocalizedString("Add meaning", comment: "Screen title")) { [weak self] entered in
            guard let self else { return }
            let words = SenseEntry.words(in: entered)
            guard !words.isEmpty else { return }
            // Commas here mean what they mean everywhere else on the way in: separate
            // meanings, one per word.
            self.proposals.append(contentsOf: words.map {
                SenseEntry(terms: [Term.Draft($0, in: language)])
            })
            self.rebuildRows()
        }
    }

    private func push(language: String,
                      initialText: String,
                      title: String,
                      onCommit: @escaping (String) -> Void) {
        let screen = WordInputViewController(
            .add(language: language),
            initialText: initialText,
            title: title,
            existingUsages: existingUsages.map { lookUp in { typed in lookUp(typed, language) } },
            onCommit: onCommit)
        navigationController?.pushViewController(screen, animated: true)
    }

    // MARK: - Committing

    @objc private func commit() {
        guard isStorable else { return }
        navigationItem.rightBarButtonItem?.isEnabled = false
        onCommit(proposals)
        if navigationController?.topViewController === self {
            navigationController?.popViewController(animated: true)
        }
    }
}
