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

    private var isRecording = false { didSet { updateRecordButton() } }

    /// Whether this question has already been answered by voice.
    ///
    /// Recognition reports **partial** results, so a matching utterance arrives several
    /// times in a row. Answering on each one called `record` again with no question in
    /// flight, and the screen popped — a correct answer ending the whole exercise.
    private var hasAnswered = false

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
        // Deliberately **not** asking for permission here. The button used to sit disabled
        // until two authorization callbacks came back, which meant a permission sheet
        // before the learner had done anything to ask for one — the request most likely to
        // be refused, and a refusal is close to permanent. It is asked on first tap now.
    }

    func prepareForQuestion() {
        hasAnswered = false
        // In automatic mode the next question starts listening on its own. A short delay so
        // the prompt has been spoken before the microphone opens, or the synthesiser's own
        // voice is the first thing recognised.
        if isAutomatic {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.isAutomatic, !self.hasAnswered, !self.isRecording else { return }
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
    /// screen moves on. Delegated, so this knowledge exists once.
    func willLeaveCurrentQuestion() {
        DictationController.shared.stop()
        isRecording = false
    }

    // MARK: - Recognition

    @objc private func recordButtonTapped() {
        guard !isRecording else {
            DictationController.shared.stop()
            isRecording = false
            return
        }

        isRecording = true
        DictationController.shared.start(
            language: screen?.languages.answerLanguage ?? "en",
            onTranscription: { [weak self] heard in
                self?.consider(heard)
            },
            onFailure: { [weak self] failure in
                self?.isRecording = false
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
    private func consider(_ heard: DictationController.Heard) {
        recognizedLabel.text = heard.text
        guard !hasAnswered, let screen, let question = screen.question else { return }
        guard question.answers.contains(where: {
            match3(pattern: $0.text, answer: heard.text,
                   language: screen.languages.answerLanguage, delimiters: ",; ")
        }) else { return }

        hasAnswered = true
        DictationController.shared.stop()
        isRecording = false

        // Clearly pronounced *and* an exact match reads as verbatim; anything the
        // recogniser was unsure of stays judged. The threshold is a first guess, recorded
        // in docs/ProgressModel.md so it can be revised against real logs rather than taste.
        let exact = question.answers.contains {
            $0.text.compare(heard.text, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
        let confident = (heard.confidence ?? 0) >= Self.confidentPronunciation
        screen.answer(exact && confident ? .correctVerbatim : .correctJudged,
                      response: heard.text)
    }

    /// Mean segment confidence at or above which a spoken answer counts as verbatim.
    /// Apple's own example calls 0.94 "very high" and 0.72 merely likely, so this sits
    /// between them.
    private static let confidentPronunciation: Float = 0.85

    /// The long-press menu that turns continuous listening on and off.
    private func installModeMenu() {
        guard #available(iOS 14.0, *) else { return installLegacyModeGesture() }
        recordButton.menu = UIMenu(title: NSLocalizedString("Recognition",
                                                            comment: "Menu title"),
                                   children: [autoAction(on: true), autoAction(on: false)])
    }

    @available(iOS 14.0, *)
    private func autoAction(on: Bool) -> UIAction {
        UIAction(title: on
                 ? NSLocalizedString("Listen automatically", comment: "Menu item")
                 : NSLocalizedString("Listen when I tap", comment: "Menu item"),
                 state: isAutomatic == on ? .on : .off) { [weak self] _ in
            self?.isAutomatic = on
            self?.installModeMenu()          // redraw the checkmark
        }
    }

    /// iOS 12–13 have no button menu; a long press toggles instead, and the button title
    /// is the only affordance either way.
    private func installLegacyModeGesture() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(toggleAutomatic))
        recordButton.addGestureRecognizer(press)
    }

    @objc private func toggleAutomatic(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        isAutomatic.toggle()
    }

    private func updateRecordButton() {
        recordButton.purpose = isRecording ? .negative : .prominent
        let title: String
        if isRecording {
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
