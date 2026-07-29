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

    /// The engine had no usable input format — checked rather than discovered, because
    /// discovering it means an uncatchable `NSException` from `installTap`.
    enum DictationError: Error { case noAudioInput }

    /// One reading of what was heard.
    ///
    /// `confidence` is the recogniser's own certainty, 0…1 — and it is **0 until
    /// `isFinal`**, which is a constraint rather than a detail: anything that wants to
    /// judge *how well* a word was pronounced has to wait for the final result, not accept
    /// the first partial that matches.
    /// ([`SFTranscriptionSegment.confidence`](https://developer.apple.com/documentation/speech/sftranscriptionsegment/confidence))
    struct Heard {
        let text: String
        let isFinal: Bool
        /// Mean segment confidence. `nil` while partial.
        let confidence: Float?
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

    /// The recogniser for `language`, built once per locale.
    ///
    /// **The only place one is constructed.** `start` used to build a fresh
    /// `SFSpeechRecognizer` on every call, which quietly made `prewarm` pointless — it
    /// cached an instance that the very next line threw away. Warming something up and then
    /// discarding it is worse than not warming it: the cost is paid twice and the code
    /// claims a benefit it does not deliver.
    private func recognizer(for language: String) -> SFSpeechRecognizer? {
        if let existing = recognizer, existing.locale.identifier == language { return existing }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        return recognizer
    }

    // MARK: - Warming up

    /// Does the slow parts of `start` ahead of the tap.
    ///
    /// The first dictation of a session takes about a second and a half before the
    /// recording indicator appears, and almost none of that is recognition: it is building
    /// an `SFSpeechRecognizer` for the locale, activating the audio session, and letting
    /// `AVAudioEngine` allocate its render resources. All three can happen while the screen
    /// is appearing, when nobody is waiting.
    ///
    /// **Silent when it cannot help.** It never requests permission — a screen appearing is
    /// not a request for the microphone, and prompting there is the surest way to be
    /// refused. Unauthorised, or already recording, it does nothing at all.
    func prewarm(language: String) {
        guard !isRecording,
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              PermissionManager.shared.isMicrophoneAuthorized else { return }

        _ = self.recognizer(for: language)

        // **The engine is deliberately left alone.** An earlier version called
        // `audioEngine.prepare()` here, reasoning that allocating the graph early was free
        // and that not activating the audio session was the careful choice. It was the
        // opposite: `prepare` pulls the input node, and with the session still in
        // `.playback` there is no capture hardware to describe, so the engine caches an
        // input format of **0 Hz**. That format survives into `beginRecording`, and
        // `installTap` with it fails `IsFormatSampleRateAndChannelCountValid` — an
        // Objective-C exception, which Swift cannot catch, so the app dies.
        //
        // Building the recogniser is the part worth doing early anyway. The engine cannot
        // be warmed without first claiming the microphone, and claiming it for a recording
        // that may never happen is exactly what a warm-up must not do.
    }

    // MARK: - Starting

    /// Begins recognising `language`, reporting partial transcriptions as they arrive.
    ///
    /// - Parameters:
    ///   - onTranscription: called repeatedly with the best transcription so far, and a
    ///     flag for whether recognition considers it final. Always on the main queue.
    ///   - onFailure: called once, and only when something went wrong. Stopping normally
    ///     is not a failure.
    func start(language: String,
               onTranscription: @escaping (Heard) -> Void,
               onFailure: @escaping (Failure) -> Void) {
        authorize { [weak self] failure in
            guard let self else { return }
            if let failure { return onFailure(failure) }

            guard let recognizer = self.recognizer(for: language), recognizer.isAvailable else {
                return onFailure(.unavailable(language: language))
            }

            do {
                try self.beginRecording(onTranscription: onTranscription, onFailure: onFailure)
            } catch DictationError.noAudioInput {
                onFailure(.unavailable(language: language))
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

    private func beginRecording(onTranscription: @escaping (Heard) -> Void,
                                onFailure: @escaping (Failure) -> Void) throws {
        task?.cancel()
        task = nil
        isStopping = false

        try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        // `.notifyOthersOnDeactivation` may only be passed when deactivating.
        try audioSession.setActive(true)

        // Read **after** the session is active and recording-capable: before that the
        // input node reports 0 Hz, and a tap installed with that format throws an
        // Objective-C exception that no Swift `do/catch` can contain.
        let inputNode = audioEngine.inputNode
        var format = inputNode.outputFormat(forBus: 0)
        if format.sampleRate == 0 {
            // The engine is holding a configuration from before the session could describe
            // the input. `reset` drops it so the node is re-queried against the session
            // that is active *now* — recovery rather than a refusal, since by this point
            // the learner has already tapped the microphone.
            audioEngine.reset()
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            // Nothing to record from — no microphone, or the session was not granted the
            // route. Reported, never risked: this is the one place where continuing means
            // an uncatchable crash rather than a handled failure.
            releaseSessionToPlayback()
            throw DictationError.noAudioInput
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            var isFinal = false

            if let result {
                isFinal = result.isFinal
                let segments = result.bestTranscription.segments
                // Averaged across segments: a two-word answer where one word was clear and
                // the other mumbled should not read as confident.
                let confidence: Float? = isFinal && !segments.isEmpty
                    ? segments.map(\.confidence).reduce(0, +) / Float(segments.count)
                    : nil
                onTranscription(Heard(text: result.bestTranscription.formattedString,
                                      isFinal: isFinal,
                                      confidence: confidence))
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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
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
