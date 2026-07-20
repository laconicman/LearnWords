//
//  ExerciseViewController.swift
//  LearnWords
//
//  The exercise screen — built once, specialised three ways (TD-20 step 2).
//
//  Test, Dictation and Phonetics are the same screen: a progress bar, the word, a place
//  the answer appears, a pair of utility buttons and a pair of answer buttons. That
//  screen used to exist three times in code *and* three times in the storyboard, which is
//  why one layout change produced three different bugs — overlapping buttons here, buttons
//  under the tab bar there, clipped text somewhere else, and three different leftover
//  height caps. The layout is now assembled here, in code, so there is one of it.
//
//  Subclasses supply only what genuinely differs: which exercise they are, what the
//  answer surface is, and how it is filled and cleared. Everything else — lifecycle,
//  transitions, feedback, scoring, progress, the round-end save — lives here and runs
//  identically for all three.
//

import UIKit

class ExerciseViewController: UIViewController {

    // MARK: - Subclass contract

    /// Which exercise this is. Scored per-exercise by `WordAndStat`.
    var exercise: ExerciseSession.Exercise {
        fatalError("\(type(of: self)) must override `exercise`")
    }

    /// The surface the answer appears on. Receives the KaPow shine/shake feedback, so it
    /// must be a child view — the container is animated separately (TD-16).
    func makeAnswerView() -> UIView {
        fatalError("\(type(of: self)) must override `makeAnswerView()`")
    }

    /// Reveal `text` as the answer to the current word.
    func showAnswer(_ text: String, isPositive: Bool) {}

    /// Return the answer surface to its waiting state for a new question.
    func prepareAnswerForQuestion() {}

    /// A control shown below the answer buttons — Phonetics' record button. `nil` if the
    /// screen has none.
    var accessoryButton: LWButton? { nil }

    /// Called before the screen moves off the current word, by answer or by skip.
    /// Phonetics hands the audio session back to playback here.
    func willLeaveCurrentWord() {}

    // MARK: - Shared views

    private(set) var progressView = UIProgressView(progressViewStyle: .default)
    private(set) var promptLabel = LWWordLabel()
    private(set) var answerView = UIView()
    private(set) var lookUpButton = LWButton(type: .system)
    private(set) var listenButton = LWButton(type: .system)
    private(set) var forgotButton = LWButton(type: .system)
    private(set) var knowButton = LWButton(type: .system)

    /// The animated container. `ExerciseTransition` drives this, never a child.
    private(set) var contentStack = UIStackView()

    // MARK: - Round

    private(set) var session = ExerciseSession(exercise: .learning, words: [])

    /// The languages this round runs in, resolved once per question so a mid-round
    /// settings change cannot split a single word's prompt from its answer.
    private(set) var languages = LanguagePair.current

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "Background")
        buildLayout()

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
        answerView = makeAnswerView()

        progressView.progressTintColor = .lwAccent
        promptLabel.font = .systemFont(ofSize: 80)

        configure(lookUpButton, title: "Look Up", purpose: .utility, action: #selector(lookUpTapped))
        configure(listenButton, title: "Listen", purpose: .utility, action: #selector(listenTapped))
        configure(forgotButton, title: "Forgot", purpose: .negative, action: #selector(forgotTapped))
        configure(knowButton, title: "Know", purpose: .affirmative, action: #selector(knowTapped))

        var rows: [UIView] = [
            progressView,
            promptLabel,
            answerView,
            row(lookUpButton, listenButton),
            row(forgotButton, knowButton),
        ]
        if let accessory = accessoryButton {
            rows.append(accessory)
        }

        contentStack = UIStackView(arrangedSubviews: rows)
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        // Same overflow strategy as every other screen — one implementation.
        scrollBottomConstraint = ScrollableContent.wrap(contentStack)?.bottomConstraint
    }

    /// The scroll view's bottom pin. Dictation drives keyboard avoidance from it.
    private(set) var scrollBottomConstraint: NSLayoutConstraint?

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

    func startRound() {
        session = .start(exercise)
    }

    @objc func nextTapped() {
        guard !session.isFinished else { return }
        willLeaveCurrentWord()
        session.skip()
        progressView.progress = session.progress
        askQuestion()
    }

    /// Presents the next word, or ends the round.
    func askQuestion() {
        guard let word = session.currentWord else {
            session.commit()
            navigationController?.popToRootViewController(animated: true)
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
        prepareAnswerForQuestion()
        ExerciseTransition.show(contentStack)
    }

    /// Scores `outcome` against the current word and reveals the answer.
    func answer(_ outcome: ReviewOutcome) {
        willLeaveCurrentWord()
        guard let result = session.answer(outcome) else { // this never happens for now
            navigationController?.popToRootViewController(animated: true)
            return
        }

        // Feedback on the child view; the container transition stays separate (TD-16).
        if result.isPositive {
            answerView.kapow.shine()
            if result.reachedKnownLevel {
                ExerciseFeedback.levelUp(on: view)
            }
        } else {
            answerView.kapow.shake()
        }

        progressView.progress = session.progress
        reveal(result)
    }

    private func reveal(_ result: ExerciseSession.Answer) {
        let text = languages.answer(for: result.word)
        let isPositive = result.isPositive

        UIView.transition(with: answerView,
                          duration: isPositive ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
            self?.setAnswerButtons(enabled: false, dimming: isPositive)
            self?.showAnswer(text, isPositive: isPositive)
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

    @objc func listenTapped() {
        guard let text = promptLabel.attributedText else { return }
        SpeechManager.shared.speak(text, language: languages.promptLanguage)
    }
}
