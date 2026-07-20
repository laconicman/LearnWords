//
//  WordPhoneticsViewController.swift
//  LearnWords
//
//  Created by  Paul on 24.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//
//  The spoken-production exercise.
//
//  Structure lives in `ExerciseViewController` (TD-20). What is genuinely this screen:
//  speech recognition, the record button, and ownership of the audio session — which is
//  why it is the one screen that overrides `willLeaveCurrentWord()` and `listenTapped()`,
//  to hand the session back to playback before speaking or moving on.
//
//  A recognised utterance is `.correctJudged`: `match3` decides whether the transcription
//  was close enough, so it is matcher evidence, not verbatim.
//

import UIKit
import Speech

final class WordPhoneticsViewController: ExerciseViewController, SFSpeechRecognizerDelegate {

    private let recognizedLabel = LWWordLabel()
    private let recordButton = LWButton(type: .system)

    private lazy var speechRecognizer = SFSpeechRecognizer(
        locale: Locale(identifier: languages.answerLanguage))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()

    override var exercise: ExerciseSession.Exercise { .phonetics }

    override func makeAnswerView() -> UIView {
        recognizedLabel.font = .systemFont(ofSize: 60)
        return recognizedLabel
    }

    override var accessoryButton: LWButton? {
        recordButton.purpose = .prominent
        recordButton.setTitle(NSLocalizedString("Start recognition", comment: "Button title"), for: [])
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        return recordButton
    }

    // MARK: - Answer surface

    override func prepareAnswerForQuestion() {
        recognizedLabel.attributedText = NSAttributedString(
            string: NSLocalizedString("pronounce the translation", comment: "label prompt"),
            attributes: [.foregroundColor: UIColor.lwAnswerPending])
    }

    override func showAnswer(_ text: String, isPositive: Bool) {
        let colour = isPositive ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong
        recognizedLabel.attributedText = NSAttributedString(
            string: text, attributes: [.foregroundColor: colour])
        recognizedLabel.textColor = colour
    }

    // MARK: - Audio session ownership

    /// Recording holds `.playAndRecord`; anything that speaks or advances needs playback
    /// back first. This is the hook the base class calls before leaving a word.
    override func willLeaveCurrentWord() {
        if audioEngine.isRunning {
            recordButtonTapped()
        }
        try? audioSession.setCategory(.playback, mode: .default, policy: .default, options: [])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    override func listenTapped() {
        willLeaveCurrentWord()
        super.listenTapped()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Stays disabled until authorization comes back.
        recordButton.isEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestMicrophoneAccess()
        speechRecognizer?.delegate = self
        requestRecognitionAccess()
    }

    private func requestMicrophoneAccess() {
        audioSession.requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, !allowed else { return }
                self.recordButton.isEnabled = false
                self.recordButton.setTitle(
                    NSLocalizedString("Microphone access denied.", comment: "Button title"),
                    for: .disabled)
                self.presentPermissionAlert(
                    title: NSLocalizedString("Allow microphone usage", comment: "Alert title"),
                    message: NSLocalizedString("for phonetic exercises", comment: "Alert message"),
                    offeringSettings: true)
            }
        }
    }

    private func requestRecognitionAccess() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            OperationQueue.main.addOperation {
                guard let self else { return }
                switch status {
                case .authorized:
                    self.recordButton.isEnabled = true

                case .denied, .restricted:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle(
                        NSLocalizedString("Recognition not allowed", comment: "Button title"),
                        for: .disabled)
                    self.presentPermissionAlert(
                        title: NSLocalizedString("Allow speech recognition", comment: "Alert title"),
                        message: NSLocalizedString("for phonetic exercises", comment: "Alert message"),
                        offeringSettings: true)

                case .notDetermined:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle(
                        NSLocalizedString("Recognition permission needed", comment: "Button title"),
                        for: .disabled)
                    self.presentPermissionAlert(
                        title: NSLocalizedString("Allow speech recognition", comment: "for phonetic exercises"),
                        message: nil, offeringSettings: false)

                default:
                    self.recordButton.isEnabled = false
                }
            }
        }
    }

    private func presentPermissionAlert(title: String, message: String?, offeringSettings: Bool) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if offeringSettings {
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Allow in settings", comment: ""),
                style: .default) { _ in gotoAppSettings() })
        }
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Got it", comment: "Button title"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - Recognition

    @objc private func recordButtonTapped() {
        guard !audioEngine.isRunning else {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recordButton.isEnabled = false
            recordButton.setTitle(NSLocalizedString("Stopping", comment: "Button title"), for: .disabled)
            recordButton.purpose = .prominent
            return
        }
        do {
            try startRecording()
            recordButton.setTitle(NSLocalizedString("Stop recognition", comment: "Button title"), for: [])
            recordButton.purpose = .negative
        } catch {
            recordButton.setTitle(NSLocalizedString("Recognition Not Available", comment: "Button title"), for: [])
            recordButton.purpose = .prominent
        }
    }

    private func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        // `.notifyOthersOnDeactivation` may only be passed when deactivating.
        try audioSession.setActive(true)
        let inputNode = audioEngine.inputNode

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }
        recognitionRequest = request

        // TODO: Check if recognition is avaliable
        // guard speechRecognizer.isAvailable else { showAlert(); return }
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            var isFinal = false

            if let result {
                let heard = result.bestTranscription.formattedString.lowercased()
                self.recognizedLabel.text = heard
                isFinal = result.isFinal

                if let word = self.session.currentWord,
                   match3(pattern: self.languages.answer(for: word),
                          answer: heard,
                          language: self.languages.answerLanguage,
                          delimiters: ",; ") /* && isFinal */ {
                    self.recordButtonTapped() // stop the audio
                    // A matcher said it was close enough — judged, not verbatim.
                    self.answer(.correctJudged)
                }
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
                self.recordButton.setTitle(
                    NSLocalizedString("Start recognition", comment: "Button title"), for: [])
                self.recordButton.purpose = .prominent

                // 203 is "no speech detected" — routine, not worth an alert.
                if let error, (error as NSError).code != 203 {
                    self.presentRecognitionError(error)
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func presentRecognitionError(_ error: Error) {
        let offline = NSLocalizedString(
            "\n Probably there is no internet connection. \n Recognition happens on Apple servers for most of devices. ",
            comment: "Speech recognition error detail")
        let detail = (error as NSError).code == 4
            ? error.localizedDescription + offline
            : error.localizedDescription + "\n" + (error as NSError).userInfo.debugDescription

        let alert = UIAlertController(
            title: NSLocalizedString("Speech recognition error", comment: ""),
            message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        recordButton.isEnabled = available
        recordButton.setTitle(
            available ? NSLocalizedString("Start recognition", comment: "Button title")
                      : NSLocalizedString("Recognition Not Available", comment: "Button title"),
            for: available ? [] : .disabled)
        recordButton.purpose = .prominent
    }
}
