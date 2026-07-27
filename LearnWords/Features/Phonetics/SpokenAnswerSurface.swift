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

    var answerView: UIView { recognizedLabel }
    var accessoryButton: LWButton? { recordButton }

    func attach(to screen: ExerciseScreen) {
        self.screen = screen
        recognizedLabel.font = .systemFont(ofSize: 60)
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        updateRecordButton()
        // Deliberately **not** asking for permission here. The button used to sit disabled
        // until two authorization callbacks came back, which meant a permission sheet
        // before the learner had done anything to ask for one — the request most likely to
        // be refused, and a refusal is close to permanent. It is asked on first tap now.
    }

    func prepareForQuestion() {
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
            onTranscription: { [weak self] heard, _ in
                self?.consider(heard.lowercased())
            },
            onFailure: { [weak self] failure in
                self?.isRecording = false
                self?.present(failure)
            })
    }

    /// Accepts the utterance as soon as it matches **any** synonym — saying either of
    /// "лиса" and "лисица" is right, which is the whole point of a meaning holding both.
    private func consider(_ heard: String) {
        recognizedLabel.text = heard
        guard let screen, let question = screen.question else { return }
        guard question.answers.contains(where: {
            match3(pattern: $0.text, answer: heard,
                   language: screen.languages.answerLanguage, delimiters: ",; ")
        }) else { return }

        DictationController.shared.stop()
        isRecording = false
        // A matcher said it was close enough — judged, not verbatim.
        screen.answer(.correctJudged, response: heard)
    }

    private func updateRecordButton() {
        recordButton.purpose = isRecording ? .negative : .prominent
        recordButton.setTitle(isRecording
            ? NSLocalizedString("Stop recognition", comment: "Button title")
            : NSLocalizedString("Start recognition", comment: "Button title"), for: [])
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
