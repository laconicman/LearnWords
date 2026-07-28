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

    /// The word already chosen, shown above the field while choosing its translation.
    ///
    /// **Restored after being deleted (owner, 2026-07-28).** The old search screen carried
    /// a section holding the term being defined, and it was removed along with the bug that
    /// section had — its row was tappable, so tapping the word filed it as its own
    /// translation. The row should never have been tappable; the *section* was doing real
    /// work. Two steps of the same screen otherwise look identical, and there is nothing
    /// else on screen to say which one you are on. It will not fit in the navigation bar.
    struct Context {
        let caption: String
        let term: String
    }

    private let purpose: Purpose
    private let context: Context?
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

    init(_ purpose: Purpose,
         initialText: String = "",
         context: Context? = nil,
         onCommit: @escaping (String) -> Void) {
        self.purpose = purpose
        self.context = context
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
        // `.roundedRect` is about 30pt tall, which reads as an afterthought beside 56pt
        // buttons and 44pt rows. A scaled floor keeps it in the same family and grows with
        // Dynamic Type; `greaterThanOrEqual` so a larger intrinsic height still wins.
        field.heightAnchor.constraint(
            greaterThanOrEqualToConstant:
                UIFontMetrics.default.scaledValue(for: 44)).isActive = true

        dictationButton.setImage(.systemImage("mic.circle.fill"), for: .normal)
        dictationButton.tintColor = .lwAccent
        dictationButton.addTarget(self, action: #selector(dictationTapped), for: .touchUpInside)
        dictationButton.accessibilityLabel = NSLocalizedString("Dictate", comment: "Button label")
        dictationButton.isHidden = purpose.language == nil    // nothing to recognise a note in
        dictationButton.sizeToFit()
        field.rightView = dictationButton
        field.rightViewMode = .always

        let stack = UIStackView(arrangedSubviews: contextViews() + [field])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(stack)
        let trailing = stack.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor)
        // One of the pair yields rather than conflicts if the header is ever measured
        // before it has a width. Auto Layout would otherwise break one of them anyway —
        // this chooses which, and does it silently.
        trailing.priority = .required - 1
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            trailing,
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
        ])
        // A table header view is laid out by frame, so its height has to be measured once
        // the content is in place. **Not measured here**: at `viewDidLoad` the table has no
        // width yet, and `systemLayoutSizeFitting` against a zero-width view is what
        // produced the "Unable to simultaneously satisfy constraints" storm —
        // `'fittingSizeHTarget' UIView.width == 0` against 8pt margins on both sides
        // cannot hold. `viewDidLayoutSubviews` measures it once the width is real.
        tableView.tableHeaderView = header
    }

    /// The pinned term: a caption and the word, in a tinted slab so it reads as *context*
    /// rather than as another thing to fill in. Deliberately not a table row — nothing
    /// here is selectable, and a row invites a tap.
    private func contextViews() -> [UIView] {
        guard let context else { return [] }

        let caption = UILabel()
        caption.text = context.caption
        caption.font = .preferredFont(forTextStyle: .caption1)
        caption.adjustsFontForContentSizeCategory = true
        caption.textColor = .lwTextSecondary

        let term = UILabel()
        term.text = context.term
        term.font = .preferredFont(forTextStyle: .title2)
        term.adjustsFontForContentSizeCategory = true
        term.textColor = .lwTextPrimary
        term.numberOfLines = 0

        let inner = UIStackView(arrangedSubviews: [caption, term])
        inner.axis = .vertical
        inner.spacing = 2
        inner.translatesAutoresizingMaskIntoConstraints = false

        // A plain view behind the stack rather than the stack's own `backgroundColor`,
        // which `UIStackView` ignores below iOS 14 — at the 12.1 floor the slab would
        // simply not be there, and the whole point of it is being visible.
        let slab = UIView()
        slab.backgroundColor = UIColor.lwAccent.withAlphaComponent(0.12)
        slab.layer.cornerRadius = 10
        slab.addSubview(inner)
        let innerTrailing = inner.trailingAnchor.constraint(equalTo: slab.trailingAnchor, constant: -12)
        innerTrailing.priority = .required - 1
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: slab.leadingAnchor, constant: 12),
            innerTrailing,
            inner.topAnchor.constraint(equalTo: slab.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(equalTo: slab.bottomAnchor, constant: -10),
        ])
        slab.isAccessibilityElement = true
        slab.accessibilityLabel = "\(context.caption): \(context.term)"
        return [slab]
    }

    /// Table header views size by frame, not by constraints.
    ///
    /// Does nothing until there is a width to fit into. Measuring at zero width asks Auto
    /// Layout to satisfy two 8pt margins inside nothing, which it reports at length and
    /// then recovers from by breaking one of *our* constraints.
    private func sizeHeaderToFit() {
        guard let header = tableView.tableHeaderView, tableView.bounds.width > 0 else { return }
        header.frame.size.width = tableView.bounds.width
        let height = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        guard header.frame.height != height else { return }
        header.frame.size.height = height
        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderToFit()
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
        // Only dismiss if the callback did not navigate onwards. The add-word flow pushes a
        // second step from here; popping unconditionally would tear that step straight back
        // off the stack.
        if navigationController?.topViewController === self {
            navigationController?.popViewController(animated: true)
        }
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
            onTranscription: { [weak self] heard in
                guard let self else { return }
                // Replaces rather than appends: each callback carries the whole
                // transcription so far, not the newest fragment.
                self.field.text = heard.text
                self.refreshCandidates()
                if heard.isFinal { self.isDictating = false }
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
