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

import UIKit

final class ExerciseViewController: UIViewController, ExerciseScreen {

    // MARK: - Construction

    private let kind: ExerciseSession.Exercise
    private let surface: ExerciseAnswerSurface

    init(exercise: ExerciseSession.Exercise, answerSurface: ExerciseAnswerSurface, title: String) {
        self.kind = exercise
        self.surface = answerSurface
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    /// Unavailable by design: a screen without an answer surface is not a valid screen,
    /// which is why this is never storyboard-instantiated.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("use init(exercise:answerSurface:title:)")
    }

    /// The three exercises the app offers. The only place that knows which surface goes
    /// with which exercise.
    static func make(_ exercise: ExerciseSession.Exercise) -> ExerciseViewController {
        switch exercise {
        case .learning:
            return ExerciseViewController(
                exercise: .learning, answerSurface: SelfAssessedAnswerSurface(),
                title: NSLocalizedString("Learning", comment: "Exercise screen title"))
        case .dictation:
            return ExerciseViewController(
                exercise: .dictation, answerSurface: TypedAnswerSurface(),
                title: NSLocalizedString("Dictation", comment: "Exercise screen title"))
        case .phonetics:
            return ExerciseViewController(
                exercise: .phonetics, answerSurface: SpokenAnswerSurface(),
                title: NSLocalizedString("Phonetic", comment: "Exercise screen title"))
        }
    }

    // MARK: - Views

    private(set) var progressView = UIProgressView(progressViewStyle: .default)
    private(set) var promptLabel = LWWordLabel()
    private(set) var lookUpButton = LWButton(type: .system)
    private(set) var listenButton = LWButton(type: .system)
    private(set) var forgotButton = LWButton(type: .system)
    private(set) var knowButton = LWButton(type: .system)

    /// The animated container. `ExerciseTransition` drives this, never a child.
    /// `let`, so it is the same object before and after the view loads — reassigning it
    /// in `buildLayout()` meant anything holding a reference early got a different stack.
    let contentStack = UIStackView()

    private let underKeyboardLayoutConstraint = UnderKeyboardLayoutConstraint()

    // MARK: - Round

    private(set) var session = ExerciseSession(exercise: .learning, words: [])

    /// Resolved once per question, so a mid-round settings change cannot split a word's
    /// prompt from its answer.
    private(set) var languages = LanguagePair.current

    var currentWord: WordAndStat? { session.currentWord }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "Background")
        buildLayout()
        surface.attach(to: self)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        if #available(iOS 11.0, *) {
            navigationItem.largeTitleDisplayMode = .never
        }

        startRound()

        // The entry state ExerciseTransition.show springs out of.
        contentStack.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        contentStack.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if session.isFinished {
            startRound()
        }
        askQuestion()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.hidesBarsOnTap = false
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        navigationController?.hidesBarsOnTap ?? true
    }

    // MARK: - Layout

    private func buildLayout() {
        progressView.progressTintColor = .lwAccent
        promptLabel.font = .systemFont(ofSize: 80)

        configure(lookUpButton, title: "Look Up", purpose: .utility, action: #selector(lookUpTapped))
        configure(listenButton, title: "Listen", purpose: .utility, action: #selector(listenTapped))
        configure(forgotButton, title: "Forgot", purpose: .negative, action: #selector(forgotTapped))
        configure(knowButton, title: "Know", purpose: .affirmative, action: #selector(knowTapped))

        var rows: [UIView] = [
            progressView,
            promptLabel,
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

    // MARK: - The round

    private func startRound() {
        session = .start(kind)
    }

    @objc private func nextTapped() {
        guard !session.isFinished else { return }
        surface.willLeaveCurrentWord()
        session.skip()
        progressView.progress = session.progress
        askQuestion()
    }

    /// Presents the next word, or ends the round.
    private func askQuestion() {
        guard let word = session.currentWord else {
            session.commit()
            navigationController?.popViewController(animated: true)
            return
        }
        if session.skipsCurrentWord(includingLearned: LWUserDefaults.standard.includeLearnedWords) {
            nextTapped()
            return
        }

        languages = .current
        promptLabel.attributedText = NSAttributedString(string: languages.prompt(for: word))
        if LWUserDefaults.standard.pronounceQuestionsPreference {
            SpeechManager.shared.speak(promptLabel.attributedText!, language: languages.promptLanguage)
        }
        surface.prepareForQuestion()
        ExerciseTransition.show(contentStack)
    }

    // MARK: - ExerciseScreen

    func answer(_ outcome: ReviewOutcome) {
        surface.willLeaveCurrentWord()
        guard let result = session.answer(outcome) else { // this never happens for now
            navigationController?.popViewController(animated: true)
            return
        }

        // Feedback on the child view; the container transition stays separate (TD-16).
        if result.isPositive {
            surface.answerView.kapow.shine()
            if result.reachedKnownLevel {
                ExerciseFeedback.levelUp(on: view)
            }
        } else {
            surface.answerView.kapow.shake()
        }

        progressView.progress = session.progress
        reveal(result)
    }

    func presentAlert(_ alert: UIAlertController) {
        present(alert, animated: true)
    }

    // MARK: - Revealing

    private func reveal(_ result: ExerciseSession.Answer) {
        let text = languages.answer(for: result.word)
        let isPositive = result.isPositive

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

    @objc private func knowTapped() { answer(.selfAssessedKnown) }

    @objc private func forgotTapped() {
        haptic(feedback: .warning)
        answer(.selfAssessedForgot)
    }

    @objc private func lookUpTapped() {
        lookUp(term: promptLabel.text ?? "", sender: self)
    }

    @objc private func listenTapped() {
        surface.willLeaveCurrentWord()
        guard let text = promptLabel.attributedText else { return }
        SpeechManager.shared.speak(text, language: languages.promptLanguage)
    }
}
