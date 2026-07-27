//
//  DictationController.swift
//  LearnWords
//
//  Speech in, text out. One recognition session at a time, for whoever asks.
//
//  Extracted from `SpokenAnswerSurface`, which had the audio engine, the recogniser, the
//  session lifecycle, the permission dance and the error alerts inline — about 150 of its
//  250 lines. That was fine while Phonetics was the only thing listening. It stopped being
//  fine when word entry wanted the same capability: the alternative was a second copy of
//  the trickiest code in the app.
//
//  **Reports, never presents.** Permission and error handling arrive as
//  `DictationController.Failure` values rather than alerts raised from here, because the
//  two callers put them in different places — an exercise screen has its own alert channel,
//  an input screen wants an inline message. A controller that presents UI decides something
//  the view layer should.
//
//  **Authorization is re-read every time, never cached.** Apple's rule for notifications
//  applies verbatim to speech: people can change permission in Settings at any point, so a
//  status read at launch is a guess by the time it is used. `start` therefore checks, and
//  asks only when the answer is "not yet decided".
//

import Foundation
import Speech
import AVFoundation

final class DictationController {

    /// Why dictation could not start, or could not continue. Each case is something the
    /// caller has to say differently, which is why they are distinguished at all.
    enum Failure {
        /// Never asked, and the learner declined the system prompt.
        case notPermitted
        /// Refused earlier, and only the Settings app can undo it.
        case permissionRevoked
        /// No recogniser for this language on this device.
        case unavailable(language: String)
        /// Recognition started and then failed. `isOffline` because that is the common
        /// cause and it reads as a bug when reported as a generic error: most devices
        /// recognise on Apple's servers.
        case recognition(Error, isOffline: Bool)
    }

    static let shared = DictationController()

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Set while `stop` is tearing the session down.
    ///
    /// Cancelling a recognition task makes it call back **with an error** — often
    /// `kAFAssistantErrorDomain 1110`, "no speech detected". A caller that stops *because
    /// it got the answer it wanted* would then be told the recognition failed, which is
    /// how a correct answer came to raise "No speech" and interrupt the exercise. A
    /// deliberate stop is not a failure, and this is how the callback knows the difference.
    private var isStopping = false

    var isRecording: Bool { audioEngine.isRunning }

    // MARK: - Starting

    /// Begins recognising `language`, reporting partial transcriptions as they arrive.
    ///
    /// - Parameters:
    ///   - onTranscription: called repeatedly with the best transcription so far, and a
    ///     flag for whether recognition considers it final. Always on the main queue.
    ///   - onFailure: called once, and only when something went wrong. Stopping normally
    ///     is not a failure.
    func start(language: String,
               onTranscription: @escaping (String, Bool) -> Void,
               onFailure: @escaping (Failure) -> Void) {
        authorize { [weak self] failure in
            guard let self else { return }
            if let failure { return onFailure(failure) }

            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
            guard let recognizer, recognizer.isAvailable else {
                return onFailure(.unavailable(language: language))
            }
            self.recognizer = recognizer

            do {
                try self.beginRecording(onTranscription: onTranscription, onFailure: onFailure)
            } catch {
                onFailure(.recognition(error, isOffline: false))
            }
        }
    }

    /// Ends the session and hands audio back to playback. Safe to call when nothing is
    /// running, which is what lets a caller stop unconditionally on the way off screen.
    func stop() {
        isStopping = true
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        // `endAudio` first, so the recogniser finishes what it already has instead of
        // being aborted mid-utterance.
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        releaseSessionToPlayback()
    }

    /// Returns the audio session to `.playback`, **active**.
    ///
    /// **Not `setActive(false)`, which is TD-15 waiting to happen again.** `SpeechManager`
    /// runs the synthesiser on the app's shared session and only configures it when the
    /// category is neither `.playback` nor `.playAndRecord`:
    ///
    /// ```swift
    /// guard session.category != .playback && session.category != .playAndRecord else { return }
    /// ```
    ///
    /// Deactivating while leaving the category at `.playAndRecord` therefore passes that
    /// guard untouched — synthesis renders into a deactivated session and produces empty
    /// buffers. That is precisely the original TD-15 symptom: speech silent, no error.
    /// Restoring the category *and* reactivating is what the Phonetics screen always did,
    /// and it is now the only copy of that knowledge.
    ///
    /// Idempotent, so a caller may release unconditionally.
    func releaseSessionToPlayback() {
        try? audioSession.setCategory(.playback, mode: .default, options: [])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Permission

    /// Re-reads both permissions, asking only for those still undecided.
    ///
    /// Two are needed and they are separate grants: recognition sends audio to Apple, the
    /// microphone captures it. Refusing either makes dictation impossible, but only a
    /// *revoked* grant needs a trip to Settings — a first refusal can simply be asked
    /// again next time, so the two are reported as different failures.
    private func authorize(completion: @escaping (Failure?) -> Void) {
        func afterSpeech() {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                self.authorizeMicrophone(completion: completion)
            case .notDetermined:
                completion(.notPermitted)
            default:
                completion(.permissionRevoked)
            }
        }

        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
            return afterSpeech()
        }
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async(execute: afterSpeech)
        }
    }

    private func authorizeMicrophone(completion: @escaping (Failure?) -> Void) {
        PermissionManager.shared.requestMicrophonePermission { granted in
            completion(granted ? nil : .permissionRevoked)
        }
    }

    // MARK: - Recording

    private func beginRecording(onTranscription: @escaping (String, Bool) -> Void,
                                onFailure: @escaping (Failure) -> Void) throws {
        task?.cancel()
        task = nil
        isStopping = false

        try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        // `.notifyOthersOnDeactivation` may only be passed when deactivating.
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            var isFinal = false

            if let result {
                isFinal = result.isFinal
                onTranscription(result.bestTranscription.formattedString, isFinal)
            }

            guard error != nil || isFinal else { return }
            let wasStopping = self.isStopping
            self.stop()

            // Silence in every sense: a stop we asked for, and the codes the recogniser
            // uses for "nothing was said" (203, 1110) or "you cancelled me" (216, 301).
            // None is a fault worth putting an alert in front of someone.
            let code = (error as NSError?)?.code
            let routine = [203, 216, 301, 1110]
            guard let error, !wasStopping, !routine.contains(code ?? 0) else { return }
            onFailure(.recognition(error, isOffline: code == 4))
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024,
                             format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }
}

// MARK: - Explaining a failure

extension DictationController.Failure {

    var title: String {
        switch self {
        case .notPermitted, .permissionRevoked:
            return NSLocalizedString("Dictation needs permission", comment: "Alert title")
        case .unavailable:
            return NSLocalizedString("Dictation is unavailable", comment: "Alert title")
        case .recognition:
            return NSLocalizedString("Speech recognition error", comment: "Alert title")
        }
    }

    var message: String {
        switch self {
        case .notPermitted:
            return NSLocalizedString(
                "LearnWords needs speech recognition and the microphone to take dictation. You can still type the word.",
                comment: "Alert message when dictation permission was declined")
        case .permissionRevoked:
            return NSLocalizedString(
                "Speech recognition or the microphone is turned off for LearnWords. Turn it on in Settings, or type the word instead.",
                comment: "Alert message when dictation permission was revoked")
        case .unavailable(let language):
            return String(format: NSLocalizedString(
                "This device has no speech recognition for %@. You can still type the word.",
                comment: "Alert message; placeholder is a language name"),
                          LanguageCode.displayName(language))
        case .recognition(let error, let isOffline):
            guard isOffline else { return error.localizedDescription }
            return error.localizedDescription + "\n\n" + NSLocalizedString(
                "Most devices recognise speech on Apple's servers, so this usually means there is no internet connection.",
                comment: "Speech recognition error detail")
        }
    }

    /// Whether the way out of this is the Settings app. A first refusal is not — asking
    /// again next time is the honest path, and sending someone to Settings for a decision
    /// they have not been asked to reconsider is a dead end dressed up as help.
    var isResolvedInSettings: Bool {
        if case .permissionRevoked = self { return true }
        return false
    }
}
