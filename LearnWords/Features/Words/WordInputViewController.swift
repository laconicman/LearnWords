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

    /// Where the word being typed already appears, if anywhere.
    ///
    /// A closure rather than a `Lexicon`, so this screen stays store-free — it is a view
    /// controller, and the moment it can query the store it starts deciding things the
    /// store or the flow should decide.
    private let existingUsages: ((String) -> [Lexicon.TermUsage])?

    /// Where the typed word already appears. An *input* to the snapshot below, refreshed on
    /// its own schedule — see `scheduleUsageLookup`.
    private var usages: [Lexicon.TermUsage] = []
    private var pendingUsageLookup: DispatchWorkItem?

    /// Everything the table shows, as one value rebuilt in one place.
    ///
    /// It was two arrays — `usages` and `candidates` — read separately by
    /// `numberOfRowsInSection` and `cellForRowAt`. UIKit calls those at different moments,
    /// and anything that refreshed between them left the counts describing one state and
    /// the cells asking about another: *Index out of range* for section 0, row 0, with the
    /// array empty. A bounds check would have hidden that; a single snapshot makes the two
    /// answers incapable of disagreeing.
    private var sections: [TableSection] = []

    private enum Row {
        case usage(Lexicon.TermUsage)
        case candidate(String)
    }

    private struct TableSection {
        let title: String
        let rows: [Row]
    }

    private let field = UITextField()
    private let dictationButton = UIButton(type: .system)

    /// What the microphone is doing, as opposed to what has been asked of it.
    ///
    /// Was a `Bool` set the instant the button was tapped, which made the button red about
    /// a second before anything was being recorded (TD-42). The wait is inherent — see
    /// `DictationController.Activity` — so the only honest fix is to show it.
    private var dictation: DictationController.Activity = .idle {
        didSet { updateDictationButton() }
    }

    /// One commit per *appearance*.
    ///
    /// `commit` does not dismiss when its callback navigates onwards — that is what lets
    /// one screen serve both a single edit and a two-step flow. The cost is that the screen
    /// survives its own commit for the length of the push animation, with the keyboard up
    /// and the Save button live, so Return or a second tap ran the whole thing again and
    /// added the word twice.
    ///
    /// **Cleared on every appearance, not set once for the screen's life** (TD-53). It was
    /// a one-way door while a committed screen was always taken off the stack; now that Back
    /// returns to the word step, a door that never reopens is a screen with a dead Save
    /// button and no way out but Back. Resetting here still closes the original hole, which
    /// only ever opened between a commit and the push that follows it.
    private var hasCommitted = false

    /// - Parameter title: overrides the title `purpose` would pick. The add-word flow uses
    ///   `.add` for both of its steps — a word, then its meaning — and "Add word" is only
    ///   right for the first. The purpose describes what is *stored*; the title describes
    ///   what is being *asked for*, and they are not the same question.
    init(_ purpose: Purpose,
         initialText: String = "",
         context: Context? = nil,
         title: String? = nil,
         existingUsages: ((String) -> [Lexicon.TermUsage])? = nil,
         onCommit: @escaping (String) -> Void) {
        self.purpose = purpose
        self.context = context
        self.existingUsages = existingUsages
        self.suggestions = purpose.language.map { WordSuggestions(language: $0) }
        self.onCommit = onCommit
        super.init(style: .grouped)
        field.text = initialText
        self.title = title ?? purpose.screenTitle
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Being shown is being asked again: a screen returned to by Back must be answerable,
        // and the guard below only exists to cover the gap between a commit and its push.
        hasCommitted = false
        navigationItem.rightBarButtonItem?.isEnabled = true
        // The microphone button is one tap away; do its slow setup while the push animates.
        if let language = purpose.language {
            DictationController.shared.prewarm(language: language)
        }
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
        dictation = .idle
        cancelUsageLookup()
    }

    // MARK: - The input row

    /// A text field with the dictation button as its left view. The field is in a table
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
            greaterThanOrEqualToConstant: Self.minimumTouchTarget).isActive = true

        dictationButton.addTarget(self, action: #selector(dictationTapped), for: .touchUpInside)
        // Image, tint and label all follow the state, so they are set in exactly one place.
        updateDictationButton()
        // **The glyph is sized, then the button is sized around it.** `sizeToFit` did the
        // reverse — it grew the button to whatever the symbol happened to be, which at the
        // default configuration is about 50pt: a solid accent disc heavier than the Save
        // button, and the loudest thing on a screen whose subject is the text beside it.
        // `.body` is the field's own text style: the glyph sits inline with the word being
        // typed, so it takes the size of that word rather than a size of its own. A text
        // style rather than a point size also keeps it tracking Dynamic Type.
        if #available(iOS 13, *) {
            dictationButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(textStyle: .body), forImageIn: .normal)
        }
        // The square is the touch target, and the padding is the difference between it and
        // the glyph — a derived gap rather than a chosen one, so it cannot drift out of step
        // with either the type scale or the target.
        dictationButton.frame = CGRect(x: 0, y: 0,
                                       width: Self.minimumTouchTarget,
                                       height: Self.minimumTouchTarget)
        // **The leading side, because the clear button owns the trailing one.** A `rightView`
        // and the clear button occupy the same place and the `rightView` wins silently, so
        // the field could not be emptied except by selecting and deleting (TD-41).
        // Omitted rather than hidden where there is no language: nothing could recognise a
        // note, and an installed-but-invisible view is a question the next reader has to
        // answer.
        if purpose.language != nil {
            field.leftView = dictationButton
            field.leftViewMode = .always
        }

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

    /// The smallest square a finger reliably hits, scaled with Dynamic Type.
    ///
    /// Named because three things now depend on it — the field's height floor, the
    /// dictation button and the hint's lookup button — and three literals that happen to
    /// agree are not the same as one rule. 44pt is Apple's, not a taste: see the HIG's
    /// [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) guidance.
    private static var minimumTouchTarget: CGFloat {
        UIFontMetrics.default.scaledValue(for: 44)
    }

    /// The slab's own padding, and the gap between its text and its button.
    ///
    /// One token rather than the four literals it replaced: they were never four decisions.
    private static let slabPadding = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

    /// The pinned term: a caption and the word, in a tinted slab so it reads as *context*
    /// rather than as another thing to fill in. Deliberately not a table row — nothing
    /// here is selectable, and a row invites a tap.
    ///
    /// **It carries a lookup button** (TD-44). The learner may well have typed the word
    /// without looking it up, and this screen is where they have to say what it *means* —
    /// which is exactly the moment the definition is worth having. The ⓘ is the same
    /// control the suggestion rows below use for the same job, so the affordance is
    /// learned once.
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
        // The system ⓘ, which is what `.detailButton` draws on the suggestion rows below.
        // Never stretched: the text takes the width, the button takes its own.
        // `.detailDisclosure` rather than an `info.circle` image: it is the one that still
        // draws something at the iOS 12 floor, where `UIImage.systemImage` returns `nil`.
        let lookUpButton = UIButton(type: .detailDisclosure)
        lookUpButton.tintColor = .lwAccent
        // Sized by the same rule as the microphone opposite it — left to itself the symbol
        // renders about 50pt, twice the ⓘ on the rows below, which reads as a different
        // control rather than the same one.
        if #available(iOS 13, *) {
            lookUpButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(textStyle: .body), forImageIn: .normal)
        }
        lookUpButton.translatesAutoresizingMaskIntoConstraints = false
        lookUpButton.setContentHuggingPriority(.required, for: .horizontal)
        lookUpButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        lookUpButton.addTarget(self, action: #selector(lookUpContext), for: .touchUpInside)
        lookUpButton.accessibilityLabel = String(
            format: NSLocalizedString("Look up %@", comment: "Button label; placeholder is a word"),
            context.term)

        let padding = Self.slabPadding
        let slab = UIView()
        slab.backgroundColor = UIColor.lwAccent.withAlphaComponent(0.12)
        slab.layer.cornerRadius = 10
        slab.addSubview(inner)
        slab.addSubview(lookUpButton)
        let innerTrailing = inner.trailingAnchor.constraint(
            equalTo: lookUpButton.leadingAnchor, constant: -padding.right)
        innerTrailing.priority = .required - 1
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: slab.leadingAnchor, constant: padding.left),
            innerTrailing,
            inner.topAnchor.constraint(equalTo: slab.topAnchor, constant: padding.top),
            inner.bottomAnchor.constraint(equalTo: slab.bottomAnchor, constant: -padding.bottom),
            lookUpButton.trailingAnchor.constraint(
                equalTo: slab.trailingAnchor, constant: -padding.right),
            lookUpButton.centerYAnchor.constraint(equalTo: slab.centerYAnchor),
            // The glyph is around 22pt; the rest is reachable area, exactly as for the
            // microphone. `greaterThanOrEqual` so a larger accessibility size still wins.
            lookUpButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Self.minimumTouchTarget),
            lookUpButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.minimumTouchTarget),
        ])

        // The caption and the term read as one phrase; the button is its own element. The
        // slab therefore cannot be a single accessibility element any more — that would
        // hide the button it now contains from VoiceOver entirely.
        inner.isAccessibilityElement = true
        inner.accessibilityLabel = "\(context.caption): \(context.term)"
        return [slab]
    }

    @objc private func lookUpContext() {
        guard let context else { return }
        lookUp(term: context.term, sender: self)
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
    /// Waits for the typing to stop before asking the store.
    ///
    /// Completions come from `UITextChecker` in memory and stay instant; this is the half
    /// that touches Core Data, and running it per keystroke made the field stutter on a
    /// real vocabulary (owner). It is also the half whose answer only means something once
    /// the word is finished — "bea" matching nothing says nothing about "bear".
    private func scheduleUsageLookup() {
        pendingUsageLookup?.cancel()
        guard existingUsages != nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.usages = self.existingUsages?(self.field.text ?? "") ?? []
            self.rebuildSections()
        }
        pendingUsageLookup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.usageLookupDelay, execute: work)
    }

    /// Long enough to sit out ordinary typing, short enough that a finished word answers
    /// before the learner reaches for Save.
    private static let usageLookupDelay: TimeInterval = 0.4

    private func refreshCandidates() {
        // The typed text changed, so anything found for the previous text is now about a
        // different word. Cleared immediately rather than left showing a stale match.
        usages = []
        rebuildSections()
        scheduleUsageLookup()
    }

    /// The one place the table's contents are built. Every data-source method reads the
    /// result and nothing else, which is what keeps the counts and the cells agreeing.
    private func rebuildSections() {
        let typed = field.text ?? ""
        var rebuilt: [TableSection] = []

        if !usages.isEmpty {
            rebuilt.append(TableSection(
                title: NSLocalizedString("Already in your words", comment: "Section header"),
                rows: usages.map(Row.usage)))
        }

        if let suggestions {
            let isBlank = typed.trimmingCharacters(in: .whitespaces).isEmpty
            let words = isBlank ? suggestions.recents : suggestions.completions(for: typed)
            if !words.isEmpty {
                rebuilt.append(TableSection(
                    title: isBlank
                        ? NSLocalizedString("Recent", comment: "Section header")
                        : NSLocalizedString("Suggestions", comment: "Section header"),
                    rows: words.map(Row.candidate)))
            }
        }

        // Empty sections are dropped rather than shown headerless, so the grouped style
        // does not reserve space for a list that is not there.
        sections = rebuilt
        tableView.reloadData()
    }

    /// Nothing pending may fire after the screen goes: it would touch the store for a word
    /// nobody is typing any more.
    private func cancelUsageLookup() {
        pendingUsageLookup?.cancel()
        pendingUsageLookup = nil
    }

    private func row(at indexPath: IndexPath) -> Row? {
        guard indexPath.section < sections.count,
              indexPath.row < sections[indexPath.section].rows.count else { return nil }
        return sections[indexPath.section].rows[indexPath.row]
    }

    // MARK: - Committing

    @objc private func commit() {
        let entered = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasCommitted, purpose.allowsEmpty || !entered.isEmpty else { return }
        hasCommitted = true
        // Nothing more can be typed into a screen that has already answered.
        field.resignFirstResponder()
        navigationItem.rightBarButtonItem?.isEnabled = false
        DictationController.shared.stop()
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
        guard dictation == .idle else {
            DictationController.shared.stop()
            dictation = .idle
            return
        }

        dictation = .starting
        DictationController.shared.start(
            language: language,
            onListening: { [weak self] in self?.dictation = .listening },
            onTranscription: { [weak self] heard in
                guard let self else { return }
                // Replaces rather than appends: each callback carries the whole
                // transcription so far, not the newest fragment.
                self.field.text = heard.text
                self.refreshCandidates()
                if heard.isFinal { self.dictation = .idle }
            },
            onFailure: { [weak self] failure in
                self?.dictation = .idle
                self?.present(failure)
            })
    }

    /// Red means *listening*, and only listening.
    ///
    /// Grey for `starting` rather than a spinner: `beginRecording` runs on the main queue,
    /// so an activity indicator would sit frozen through the very wait it is meant to
    /// describe. A colour that does not need to animate tells the truth either way.
    private func updateDictationButton() {
        switch dictation {
        case .idle:
            dictationButton.setImage(.systemImage("mic.circle.fill"), for: .normal)
            dictationButton.tintColor = .lwAccent
            dictationButton.accessibilityLabel =
                NSLocalizedString("Dictate", comment: "Button label")
        case .starting:
            dictationButton.setImage(.systemImage("mic.circle.fill"), for: .normal)
            dictationButton.tintColor = .lwTextSecondary
            dictationButton.accessibilityLabel =
                NSLocalizedString("Starting dictation", comment: "Button label")
        case .listening:
            dictationButton.setImage(.systemImage("mic.circle"), for: .normal)
            dictationButton.tintColor = .lwAnswerWrong
            dictationButton.accessibilityLabel =
                NSLocalizedString("Stop dictating", comment: "Button label")
        }
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

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < sections.count ? sections[section].rows.count : 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section < sections.count ? sections[section].title : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch row(at: indexPath) {
        case .usage(let usage):
            return usageCell(usage)
        case .candidate(let word):
            let cell = tableView.dequeueReusableCell(withIdentifier: "candidate", for: indexPath)
            cell.textLabel?.attributedText = highlighted(word)
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.selectionStyle = .default
            // The accessory looks the word up; selecting the row chooses it. Two different
            // actions, which is why one is a button and not a second tap target.
            cell.accessoryType = .detailButton
            return cell
        case nil:
            // Unreachable while the counts come from `sections`, and cheaper than a trap if
            // that ever stops being true.
            return UITableViewCell()
        }
    }

    /// The existing-words rows show information and nothing else.
    ///
    /// Not selectable, on the lesson from the search screen: a row that looked like a hint
    /// was tappable, and tapping it filed the word as its own translation. A hint that can
    /// be acted on by accident is worse than no hint.
    /// Tints the part already typed, so it is obvious what each candidate adds.
    private func highlighted(_ candidate: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: candidate)
        guard let typed = field.text, !typed.isEmpty,
              let range = candidate.nsRange(of: typed) else { return attributed }
        attributed.addAttribute(.foregroundColor, value: UIColor.lwAccent, range: range)
        return attributed
    }

    private func usageCell(_ usage: Lexicon.TermUsage) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none

        cell.textLabel?.text = usage.translations.joined(separator: ", ")
        cell.textLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.textLabel?.textColor = .lwTextSecondary
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0

        // Smaller again, and allowed to truncate: which set it is in is useful context, not
        // something worth wrapping the row for.
        cell.detailTextLabel?.text = usage.setNames.joined(separator: ", ")
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .caption2)
        cell.detailTextLabel?.textColor = .lwTextSecondary
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.lineBreakMode = .byTruncatingTail
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard case .candidate(let word) = row(at: indexPath) else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        field.text = word
        refreshCandidates()
        commit()
    }

    override func tableView(_ tableView: UITableView,
                            accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard case .candidate(let word) = row(at: indexPath) else { return }
        lookUp(term: word, sender: self)
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
