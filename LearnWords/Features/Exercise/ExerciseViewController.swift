//
//  ExerciseViewController.swift
//  LearnWords
//
//  The exercise screen — one of it, for all three exercises (TD-20).
//
//  Test, Dictation and Phonetics are the same screen: a progress bar, the word, a place
//  the answer appears, a pair of utility buttons and a pair of answer buttons. That screen
//  used to exist three times in code *and* three times in the storyboard, which is why one
//  layout change produced three different bugs. It is assembled here, in code, once.
//
//  What differs between the three is injected as an `ExerciseAnswerSurface`, not overridden
//  — so this type is `final`, there is nothing abstract to instantiate by mistake, and the
//  compiler (not a `fatalError`) enforces that every exercise supplies what it must.
//
//  The sitting itself is a `PracticeSession`: it owns the queue, measures latency and
//  appends every answer to the review log. This screen only shows what it is told and
//  reports what the learner did.
//

import UIKit

final class ExerciseViewController: UIViewController, ExerciseScreen {

    // MARK: - Construction

    private let surface: ExerciseAnswerSurface
    private let session: PracticeSession

    init(session: PracticeSession, answerSurface: ExerciseAnswerSurface, title: String) {
        self.session = session
        self.surface = answerSurface
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    /// Unavailable by design: a screen without a sitting and an answer surface is not a
    /// valid screen, which is why this is never storyboard-instantiated.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("use init(session:answerSurface:title:)")
    }

    /// Builds the screen for one exercise over one set. The only place that knows which
    /// surface goes with which exercise.
    static func make(_ exercise: Exercise,
                     in wordSet: WordSet,
                     lexicon: Lexicon,
                     scope: PracticeSession.Scope = .due) throws -> ExerciseViewController {
        let session = try PracticeSession.start(
            exercise,
            in: wordSet.id,
            languages: .forSet(wordSet),
            lexicon: lexicon,
            scope: scope)

        let surface: ExerciseAnswerSurface
        switch exercise {
        case .learning: surface = SelfAssessedAnswerSurface()
        case .dictation: surface = TypedAnswerSurface()
        case .phonetics: surface = SpokenAnswerSurface()
        }
        return ExerciseViewController(session: session, answerSurface: surface,
                                      title: exercise.title)
    }

    // MARK: - Views

    private(set) var progressView = UIProgressView(progressViewStyle: .default)
    private(set) var promptLabel = LWWordLabel()
    private(set) var noteLabel = UILabel()
    private(set) var lookUpButton = LWButton(type: .system)
    private(set) var listenButton = LWButton(type: .system)
    private(set) var forgotButton = LWButton(type: .system)
    private(set) var knowButton = LWButton(type: .system)

    /// The animated container. `ExerciseTransition` drives this, never a child.
    /// `let`, so it is the same object before and after the view loads.
    let contentStack = UIStackView()

    private let underKeyboardLayoutConstraint = UnderKeyboardLayoutConstraint()

    // MARK: - ExerciseScreen

    var question: PracticeSession.Question? { session.current }
    var languages: LanguagePair { session.languages }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "Background")
        buildLayout()
        surface.attach(to: self)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .fastForward, target: self, action: #selector(skipTapped))
        navigationItem.largeTitleDisplayMode = .never

        // The entry state ExerciseTransition.show springs out of.
        contentStack.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        contentStack.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if question == nil { askQuestion() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.hidesBarsOnTap = false
        // The sitting is over, or the learner walked away. Either way nothing on this
        // screen may keep running — `willLeaveCurrentQuestion` only fires *between*
        // questions, so it never runs for the last one.
        surface.detach()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        navigationController?.hidesBarsOnTap ?? true
    }

    // MARK: - Layout

    private func buildLayout() {
        progressView.progressTintColor = .lwAccent
        promptLabel.font = .systemFont(ofSize: 80)

        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .lwTextSecondary
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        noteLabel.adjustsFontForContentSizeCategory = true

        configure(lookUpButton, title: "Look Up", purpose: .utility, action: #selector(lookUpTapped))
        configure(listenButton, title: "Listen", purpose: .utility, action: #selector(listenTapped))
        configure(forgotButton, title: "Forgot", purpose: .negative, action: #selector(forgotTapped))
        configure(knowButton, title: "Know", purpose: .affirmative, action: #selector(knowTapped))

        var rows: [UIView] = [
            progressView,
            promptLabel,
            noteLabel,
            surface.answerView,
            row(lookUpButton, listenButton),
            row(forgotButton, knowButton),
        ]
        if let accessory = surface.accessoryButton {
            rows.append(accessory)
        }
        rows.forEach(contentStack.addArrangedSubview)

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        // Same overflow strategy as every other screen — one implementation.
        let wrapped = ScrollableContent.wrap(contentStack)
        // Harmless where nothing focuses; Dictation is the one that needs it.
        if let bottom = wrapped?.bottomConstraint {
            underKeyboardLayoutConstraint.setup(bottom, view: view, minMargin: 0)
        }
    }

    private func configure(_ button: LWButton, title: String,
                           purpose: LWButton.Purpose, action: Selector) {
        button.purpose = purpose
        button.setTitle(NSLocalizedString(title, comment: "Exercise button"), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func row(_ left: UIView, _ right: UIView) -> LWButtonRow {
        let row = LWButtonRow(arrangedSubviews: [left, right])
        row.spacing = 8
        row.distribution = .fillEqually
        return row
    }

    // MARK: - The sitting

    /// Puts the next question up, or leaves when the sitting is done.
    private func askQuestion() {
        guard let question = session.nextQuestion() else {
            navigationController?.popViewController(animated: true)
            return
        }

        promptLabel.attributedText = NSAttributedString(string: question.prompt)
        // Only shown when the word alone is ambiguous — an empty label would otherwise
        // hold a gap on every screen.
        noteLabel.text = question.note
        noteLabel.isHidden = question.note == nil

        if LWUserDefaults.standard.pronounceQuestionsPreference {
            // Queued, not interrupting: a correct answer's reveal is still being spoken
            // 0.1 s later when the next question arrives, and interrupting it read as the
            // pronunciation being cut off.
            SpeechManager.shared.speak(promptLabel.attributedText!,
                                       language: languages.promptLanguage, immediately: false)
        }
        surface.prepareForQuestion()
        ExerciseTransition.show(contentStack)
    }

    @objc private func skipTapped() {
        guard question != nil else { return }
        surface.willLeaveCurrentQuestion()
        try? session.skip()
        progressView.progress = session.progress
        askQuestion()
    }

    /// Records the answer, gives feedback, reveals what was wanted, and moves on.
    func answer(_ outcome: ReviewOutcome, response: String?) {
        surface.willLeaveCurrentQuestion()
        // `record` returns nil when there was no question in flight, and throws if the
        // meaning vanished under us (edited away on another device) — either way the
        // sitting cannot continue.
        guard let answered = ((try? session.record(outcome, response: response)) ?? nil) else {
            navigationController?.popViewController(animated: true)
            return
        }

        // Feedback on the child view; the container transition stays separate (TD-16).
        if outcome.isPositive {
            surface.answerView.kapow.shine()
        } else {
            surface.answerView.kapow.shake()
        }

        progressView.progress = session.progress
        reveal(answered, isPositive: outcome.isPositive)
    }

    func presentAlert(_ alert: UIAlertController) {
        present(alert, animated: true)
    }

    // MARK: - Revealing

    private func reveal(_ question: PracticeSession.Question, isPositive: Bool) {
        let text = question.expected

        UIView.transition(with: surface.answerView,
                          duration: isPositive ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
            self?.setAnswerButtons(enabled: false, dimming: isPositive)
            self?.surface.showAnswer(text, isPositive: isPositive)
        }) { [weak self] _ in
            self?.setAnswerButtons(enabled: true, dimming: isPositive)
            self?.advance(afterCorrect: isPositive)
        }

        if LWUserDefaults.standard.pronounceAnswersPreference {
            SpeechManager.shared.speak(NSAttributedString(string: text),
                                       language: languages.answerLanguage)
        }
    }

    private func setAnswerButtons(enabled: Bool, dimming isPositive: Bool) {
        knowButton.isEnabled = enabled
        forgotButton.isEnabled = enabled
        let opacity: Float = enabled ? 1 : 0.1
        if isPositive { knowButton.layer.opacity = opacity } else { forgotButton.layer.opacity = opacity }
    }

    /// A wrong answer lingers so the correct one can be read; a right one moves on briskly.
    private func advance(afterCorrect isPositive: Bool) {
        ExerciseTransition.advance(contentStack, afterDelay: isPositive ? 0.1 : 2.0) { [weak self] in
            self?.askQuestion()
        }
    }

    // MARK: - Actions

    @objc private func knowTapped() { answer(.selfAssessedKnown, response: nil) }

    @objc private func forgotTapped() {
        haptic(feedback: .warning)
        answer(.selfAssessedForgot, response: nil)
    }

    @objc private func lookUpTapped() {
        lookUp(term: promptLabel.text ?? "", sender: self)
    }

    @objc private func listenTapped() {
        surface.willLeaveCurrentQuestion()
        guard let text = promptLabel.attributedText else { return }
        SpeechManager.shared.speak(text, language: languages.promptLanguage)
    }
}
