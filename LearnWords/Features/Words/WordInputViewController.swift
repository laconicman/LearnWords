//
//  WordInputViewController.swift
//  LearnWords
//
//  Entering one word, in one language.
//
//  **This replaces a `UIAlertController` with a text field.** An alert was defensible while
//  a word was just a string to capture; it stopped being so once the same moment wanted
//  completions, a dictionary lookup and dictation. An alert can hold a text field and
//  nothing else — no list, no accessory controls, no room to say which language you are
//  typing in — so every one of those capabilities would have had to live somewhere the
//  learner could not reach from where they needed it (owner, 2026-07-27).
//
//  One screen, reused: the meaning editor pushes it to add or rename a word, and the
//  add-word flow uses it for both halves of a new pair. Reuse is the point — the previous
//  arrangement had a rich search screen for one entry path and a bare alert for the other,
//  and the two drifted apart exactly as you would expect.
//
//  **Dictation is a visible button, not only a keyboard key.** The keyboard's microphone is
//  easy to miss and disappears with a hardware keyboard; a control in the interface says
//  the capability exists. It earns its place most on the *native*-language side, where the
//  learner is writing their own words rather than practising a foreign spelling.
//

import UIKit

final class WordInputViewController: UITableViewController {

    /// What the screen is for, which decides its title and its confirm button.
    enum Purpose {
        case add(language: String)
        case rename(Term)
        case note

        var language: String? {
            switch self {
            case .add(let language): return language
            case .rename(let term): return term.language
            case .note: return nil
            }
        }
    }

    private let purpose: Purpose
    private let suggestions: WordSuggestions?
    private let onCommit: (String) -> Void

    private let field = UITextField()
    private let dictationButton = UIButton(type: .system)
    private var candidates: [String] = []
    private var showingRecents = true

    /// Set while dictation is running, so a partial transcription can replace the last one
    /// instead of appending to it.
    private var isDictating = false {
        didSet { updateDictationButton() }
    }

    init(_ purpose: Purpose, initialText: String = "", onCommit: @escaping (String) -> Void) {
        self.purpose = purpose
        self.suggestions = purpose.language.map { WordSuggestions(language: $0) }
        self.onCommit = onCommit
        super.init(style: .grouped)
        field.text = initialText
        title = purpose.screenTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(_:initialText:onCommit:)") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "candidate")
        tableView.keyboardDismissMode = .interactive

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Save", comment: "Bar button"),
            style: .done, target: self, action: #selector(commit))

        buildInputRow()
        refreshCandidates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Leaving with the microphone open would keep the audio session — and the recording
        // indicator — alive behind an unrelated screen.
        DictationController.shared.stop()
        isDictating = false
    }

    // MARK: - The input row

    /// A text field with the dictation button as its right view. The field is in a table
    /// header rather than a cell so it never scrolls away from the candidates it filters.
    private func buildInputRow() {
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = purpose.placeholder
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        dictationButton.setImage(.systemImage("mic.circle.fill"), for: .normal)
        dictationButton.tintColor = .lwAccent
        dictationButton.addTarget(self, action: #selector(dictationTapped), for: .touchUpInside)
        dictationButton.accessibilityLabel = NSLocalizedString("Dictate", comment: "Button label")
        dictationButton.isHidden = purpose.language == nil    // nothing to recognise a note in
        dictationButton.sizeToFit()
        field.rightView = dictationButton
        field.rightViewMode = .always

        let header = UIView()
        field.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            field.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            field.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
        ])
        header.frame.size.height = field.intrinsicContentSize.height + 24
        tableView.tableHeaderView = header
    }

    @objc private func textChanged() {
        refreshCandidates()
    }

    /// Completions once there is something to complete, recently used words before that.
    private func refreshCandidates() {
        guard let suggestions else { return candidates = [] }
        let typed = field.text ?? ""
        showingRecents = typed.trimmingCharacters(in: .whitespaces).isEmpty
        candidates = showingRecents ? suggestions.recents : suggestions.completions(for: typed)
        tableView.reloadData()
    }

    // MARK: - Committing

    @objc private func commit() {
        let entered = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard purpose.allowsEmpty || !entered.isEmpty else { return }
        suggestions?.remember(entered)
        onCommit(entered)
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Dictation

    @objc private func dictationTapped() {
        guard let language = purpose.language else { return }
        guard !isDictating else {
            DictationController.shared.stop()
            isDictating = false
            return
        }

        isDictating = true
        DictationController.shared.start(
            language: language,
            onTranscription: { [weak self] transcription, isFinal in
                guard let self else { return }
                // Replaces rather than appends: each callback carries the whole
                // transcription so far, not the newest fragment.
                self.field.text = transcription
                self.refreshCandidates()
                if isFinal { self.isDictating = false }
            },
            onFailure: { [weak self] failure in
                self?.isDictating = false
                self?.present(failure)
            })
    }

    private func updateDictationButton() {
        let symbol = isDictating ? "mic.circle" : "mic.circle.fill"
        dictationButton.setImage(.systemImage(symbol), for: .normal)
        dictationButton.tintColor = isDictating ? .lwAnswerWrong : .lwAccent
        dictationButton.accessibilityLabel = isDictating
            ? NSLocalizedString("Stop dictating", comment: "Button label")
            : NSLocalizedString("Dictate", comment: "Button label")
    }

    /// Says what went wrong, and offers Settings only when Settings is genuinely the way
    /// out. Typing still works in every case, which the messages say rather than implying
    /// the screen is broken.
    private func present(_ failure: DictationController.Failure) {
        let alert = UIAlertController(title: failure.title, message: failure.message,
                                      preferredStyle: .alert)
        if failure.isResolvedInSettings {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""),
                                          style: .default) { _ in gotoAppSettings() })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Candidates

    override func numberOfSections(in tableView: UITableView) -> Int { candidates.isEmpty ? 0 : 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        candidates.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        showingRecents
            ? NSLocalizedString("Recent", comment: "Section header")
            : NSLocalizedString("Suggestions", comment: "Section header")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "candidate", for: indexPath)
        cell.textLabel?.attributedText = highlighted(candidates[indexPath.row])
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        // The accessory looks the word up; selecting the row chooses it. Two different
        // actions, which is why one is a button and not a second tap target on the label.
        cell.accessoryType = .detailButton
        return cell
    }

    /// Tints the part already typed, so it is obvious what each candidate adds.
    private func highlighted(_ candidate: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: candidate)
        guard let typed = field.text, !typed.isEmpty,
              let range = candidate.nsRange(of: typed) else { return attributed }
        attributed.addAttribute(.foregroundColor, value: UIColor.lwAccent, range: range)
        return attributed
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        field.text = candidates[indexPath.row]
        refreshCandidates()
        commit()
    }

    override func tableView(_ tableView: UITableView,
                            accessoryButtonTappedForRowWith indexPath: IndexPath) {
        lookUp(term: candidates[indexPath.row], sender: self)
    }
}

// MARK: - Text field

extension WordInputViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commit()
        return true
    }
}

// MARK: - Wording

private extension WordInputViewController.Purpose {

    var screenTitle: String {
        switch self {
        case .add: return NSLocalizedString("Add word", comment: "Screen title")
        case .rename: return NSLocalizedString("Edit word", comment: "Screen title")
        case .note: return NSLocalizedString("Note", comment: "Screen title")
        }
    }

    var placeholder: String {
        switch self {
        case .add(let language):
            return LanguageCode.displayName(language)
        case .rename(let term):
            return LanguageCode.displayName(term.language)
        case .note:
            return NSLocalizedString("Shown when the word alone is ambiguous",
                                     comment: "Placeholder")
        }
    }

    /// Only a note may be cleared; a word with no letters is not a word.
    var allowsEmpty: Bool {
        if case .note = self { return true }
        return false
    }
}
