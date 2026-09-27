//
//  SpokenAnswerSurface.swift
//  LearnWords
//
//  The Phonetics exercise: say the translation.
//
//  **Recognition lives in `DictationController` now (TD-31).** This file used to own the
//  audio engine, the recogniser, the session lifecycle and the permission dance. Extracting
//  them for word entry left two copies of the same lifecycle, and the second copy was the
//  one with the history of getting it wrong — TD-15 was exactly this: speech silently dead
//  after a recognition round, no error anywhere. One owner, or it happens again.
//
//  A recognised utterance is `.correctJudged`: `match3` decides whether the transcription
//  was close enough, so it is matcher evidence, not verbatim.
//
//  Was `WordPhoneticsViewController`, a subclass of an abstract screen.
//

import UIKit

final class SpokenAnswerSurface: NSObject, ExerciseAnswerSurface {

    private let recognizedLabel = LWWordLabel()
    private let recordButton = LWButton(type: .system)
    private weak var screen: ExerciseScreen?

    /// What the microphone is doing, not what has been asked of it — the same distinction
    /// word entry needed (TD-42). "Stop recognition" appeared about a second before there
    /// was anything to stop.
    /// Internal so tests can place and observe the mic state the button reflects.
    var dictation: DictationController.Activity = .idle {
        didSet { updateRecordButton() }
    }

    /// Whether this question has already been answered by voice.
    ///
    /// Recognition reports **partial** results, so a matching utterance arrives several
    /// times in a row. Answering on each one called `record` again with no question in
    /// flight, and the screen popped — a correct answer ending the whole exercise.
    private var hasAnswered = false

    /// Set once the screen is gone. Auto mode schedules its listening a second into each
    /// question, so without this the timer could open the microphone *after* the exercise
    /// had been dismissed — leaving the recording indicator lit over an unrelated screen.
    private var isDetached = false

    /// Bumped whenever the question changes. A `whenSilent` wait queued for one question
    /// can outlive it — the answer reveal is speech too — and would otherwise fire inside
    /// the *next* question, whose `hasAnswered` was just reset. Read internally so tests
    /// can hand `consider` the generation a session was opened in.
    private(set) var questionGeneration = 0

    /// Final results already judged on this question. The **first** attempt must match
    /// the recogniser's best reading; its ranked alternatives count only on retries —
    /// the first try tests whether the learner can hit the canonical pronunciation, a
    /// retry is forgiving because the point of it is recovery (owner call, 2026-09-27).
    /// Only `isFinal` results count: a partial is still mid-utterance, not an attempt.
    /// A cancelled task can still deliver one late final; `consider` drops results
    /// whose session opened before the current `questionGeneration`, so a straggler
    /// can neither credit nor spend the strict attempt of the next question.
    private var completedAttempts = 0

    /// Keeps listening across questions instead of waiting for a tap each time.
    ///
    /// Offered as a long-press menu on the record button rather than a second control: the
    /// exercise screen has one accessory slot, and the choice belongs to the button it
    /// changes the behaviour of.
    private var isAutomatic: Bool {
        get { LWUserDefaults.standard.continuousRecognition }
        set { LWUserDefaults.standard.continuousRecognition = newValue; updateRecordButton() }
    }

    var answerView: UIView { recognizedLabel }
    var accessoryButton: LWButton? { recordButton }

    func attach(to screen: ExerciseScreen) {
        self.screen = screen
        recognizedLabel.font = .systemFont(ofSize: 60)
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        installModeMenu()
        updateRecordButton()
        DictationController.shared.prewarm(language: screen.languages.answerLanguage)
        // Deliberately **not** asking for permission here. The button used to sit disabled
        // until two authorization callbacks came back, which meant a permission sheet
        // before the learner had done anything to ask for one — the request most likely to
        // be refused, and a refusal is close to permanent. It is asked on first tap now.
    }

    func prepareForQuestion() {
        hasAnswered = false
        completedAttempts = 0
        // In automatic mode the next question starts listening on its own — once the prompt
        // has actually finished. A fixed delay bet on the prompt being short: opening the
        // microphone switches the session to `.playAndRecord` and cut a long word off
        // mid-syllable, and `whenSilent` knows the real end rather than guessing at 1.2 s.
        if isAutomatic {
            questionGeneration += 1
            let generation = questionGeneration
            SpeechManager.shared.whenSilent { [weak self] in
                guard let self, self.questionGeneration == generation,
                      !self.isDetached, self.isAutomatic,
                      !self.hasAnswered, self.dictation == .idle else { return }
                self.recordButtonTapped()
            }
        }
        recognizedLabel.attributedText = NSAttributedString(
            string: NSLocalizedString("pronounce the translation", comment: "label prompt"),
            attributes: [.foregroundColor: UIColor.lwAnswerPending])
    }

    func showAnswer(_ text: String, isPositive: Bool) {
        let colour = isPositive ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong
        recognizedLabel.attributedText = NSAttributedString(
            string: text, attributes: [.foregroundColor: colour])
        recognizedLabel.textColor = colour
    }

    /// Recording holds `.playAndRecord`; give playback back before anything speaks or the
    /// screen moves on. Delegated, so this knowledge exists once. Interrupting a question
    /// (Listen, an answer, a skip) also kills the pending auto-listen: without it the timer
    /// can open the microphone while the synthesiser is speaking the answer, and grade the
    /// app's own voice as the learner's.
    func willLeaveCurrentQuestion() {
        questionGeneration += 1
        DictationController.shared.stop()
        dictation = .idle
    }

    func detach() {
        isDetached = true
        questionGeneration += 1
        DictationController.shared.stop()
        dictation = .idle
    }

    // MARK: - Recognition

    @objc private func recordButtonTapped() {
        guard dictation == .idle else {
            DictationController.shared.stop()
            dictation = .idle
            return
        }

        dictation = .starting
        let generation = questionGeneration
        DictationController.shared.start(
            language: screen?.languages.answerLanguage ?? "en",
            onListening: { [weak self] in self?.dictation = .listening },
            onTranscription: { [weak self] heard in
                self?.consider(heard, session: generation)
            },
            onFailure: { [weak self] failure in
                self?.dictation = .idle
                self?.present(failure)
            })
    }

    /// Accepts the utterance as soon as it matches **any** synonym — saying either of
    /// "лиса" and "лисица" is right, which is the whole point of a meaning holding both.
    /// Accepts the utterance as soon as it matches **any** synonym — saying either of
    /// "лиса" and "лисица" is right, which is the whole point of a meaning holding both.
    ///
    /// The grade uses the recogniser's confidence when it has one. `confidence` is `0`
    /// until the result is final, so a match on a *partial* is deliberately taken at the
    /// weaker grade rather than waited on: making the learner hold still for the final
    /// result to earn a better mark would be a worse exercise than a slightly cautious one.
    /// Internal rather than private so tests can drive the attempt gate without a
    /// microphone (the `matchedReading` tests cover matching; this path covers *when*
    /// alternatives are consulted).
    ///
    /// `session` is the `questionGeneration` the delivering session was opened in: a
    /// cancelled recognition task can still deliver one last result, and it belongs to
    /// the question that was on screen when it started — a straggler must not grade,
    /// repaint, or spend the strict attempt of the question that came after.
    func consider(_ heard: DictationController.Heard, session generation: Int) {
        guard generation == questionGeneration else { return }
        recognizedLabel.text = heard.text
        guard !hasAnswered, let screen, let question = screen.question else { return }
        defer { if heard.isFinal { completedAttempts += 1 } }
        guard let credited = Self.matchedReading(in: heard,
                                                 answers: question.answers.map(\.text),
                                                 language: screen.languages.answerLanguage,
                                                 allowAlternatives: completedAttempts > 0)
        else {
            // A final already ended the controller's session (its callback stops on
            // `isFinal`): leaving `.listening` here showed "Stop recognition" over a
            // dead recording, and the retry took two taps — one to clear the stale
            // state, one to actually start. Partials keep the session alive; only a
            // final hands the button back.
            if heard.isFinal { dictation = .idle }
            return
        }

        hasAnswered = true
        DictationController.shared.stop()
        dictation = .idle

        // Clearly pronounced *and* an exact match on the *best* guess reads as verbatim;
        // an alternative reading stays judged — the recogniser preferred another.
        // The threshold is a first guess, recorded in docs/ProgressModel.md so it can be
        // revised against real logs rather than taste.
        let exact = question.answers.contains {
            $0.text.compare(credited.text, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
        let confident = (heard.confidence ?? 0) >= Self.confidentPronunciation
        // `response` is the log's record of what was said, so it keeps the recogniser's
        // best reading even when an alternative is what matched — recording the
        // alternative would write an apparently-exact answer and erase the disagreement
        // the log exists to preserve (raised by review, PR #33).
        screen.answer(exact && confident && credited.isBest ? .correctVerbatim : .correctJudged,
                      response: heard.text)
    }

    /// The first reading of the utterance that answers the question: the recogniser's best
    /// guess wins, and only then are the alternatives tried, in its confidence order.
    /// `isBest` records which it was — an answer the recogniser ranked second is matched
    /// evidence but never verbatim. `allowAlternatives` is false on a question's first
    /// attempt: that one is graded on the best reading alone.
    static func matchedReading(in heard: DictationController.Heard,
                               answers: [String], language: String,
                               allowAlternatives: Bool)
        -> (text: String, isBest: Bool)? {
        func hits(_ reading: String) -> Bool {
            answers.contains {
                match3(pattern: $0, answer: reading, language: language, delimiters: ",; ")
            }
        }
        if hits(heard.text) { return (heard.text, true) }
        guard allowAlternatives else { return nil }
        for candidate in heard.alternatives where hits(candidate) {
            return (candidate, false)
        }
        return nil
    }

    /// Mean segment confidence at or above which a spoken answer counts as verbatim.
    /// Apple's own example calls 0.94 "very high" and 0.72 merely likely, so this sits
    /// between them.
    private static let confidentPronunciation: Float = 0.85

    /// The long-press menu that turns continuous listening on and off.
    private func installModeMenu() {
        recordButton.menu = UIMenu(title: NSLocalizedString("Recognition",
                                                            comment: "Menu title"),
                                   children: [autoAction(on: true), autoAction(on: false)])
    }

    private func autoAction(on: Bool) -> UIAction {
        UIAction(title: on
                 ? NSLocalizedString("Listen automatically", comment: "Menu item")
                 : NSLocalizedString("Listen when I tap", comment: "Menu item"),
                 state: isAutomatic == on ? .on : .off) { [weak self] _ in
            self?.isAutomatic = on
            self?.installModeMenu()          // redraw the checkmark
        }
    }

    private func updateRecordButton() {
        // `.utility` is the grey one: while starting, the button is neither the main action
        // nor a running recording, and saying so costs no new colour vocabulary.
        switch dictation {
        case .idle:      recordButton.purpose = .prominent
        case .starting:  recordButton.purpose = .utility
        case .listening: recordButton.purpose = .negative
        }
        // A chevron says "there is more here" — without it the long-press menu is a secret,
        // and auto mode looked like the button had silently changed its mind (owner).
        recordButton.setImage(.systemImage("chevron.down.circle"), for: .normal)
        let title: String
        if dictation == .starting {
            title = NSLocalizedString("Starting…", comment: "Button title while the microphone opens")
        } else if dictation == .listening {
            title = NSLocalizedString("Stop recognition", comment: "Button title")
        } else if isAutomatic {
            title = NSLocalizedString("Listening automatically", comment: "Button title")
        } else {
            title = NSLocalizedString("Start recognition", comment: "Button title")
        }
        recordButton.setTitle(title, for: [])
    }

    /// Every failure leaves the exercise usable — "Forgot" and "Know" still work — so the
    /// wording never suggests the screen is broken, and Settings is offered only when
    /// Settings is genuinely the way out.
    private func present(_ failure: DictationController.Failure) {
        let alert = UIAlertController(title: failure.title, message: failure.message,
                                      preferredStyle: .alert)
        if failure.isResolvedInSettings {
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Allow in settings", comment: ""),
                style: .default) { _ in gotoAppSettings() })
        }
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Got it", comment: "Button title"), style: .default))
        screen?.presentAlert(alert)
    }
}
