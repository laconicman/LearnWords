//
//  SpeechManager.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/26/25.
//  Copyright © 2025 Paul. All rights reserved.
//


import AVFoundation

final class SpeechManager: NSObject {
    static let shared = SpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceQueue = [(utterance: AVSpeechUtterance, owner: ObjectIdentifier?)]()

    /// The utterance handed to the synthesiser and not yet finished or cancelled.
    ///
    /// **Our own record, not `synthesizer.isSpeaking`.** Asking the synthesiser meant a
    /// queued utterance never played — nothing called `processQueue` again once the first one
    /// ended — so every caller had to interrupt, and the next question's prompt cut the
    /// revealed answer off mid-word. Knowing which utterance is ours also lets a cancel
    /// that arrives late, for one already replaced, be told apart from the end of the
    /// current one.
    private var current: AVSpeechUtterance?
    private var currentOwner: ObjectIdentifier?
    private var isProcessing: Bool { current != nil }

    /// Waiting for silence; see `whenSilent`.
    private var whenSilentActions: [() -> Void] = []

    /// Test hooks fed from the delegate: the synthesiser *began* the utterance or *finished*
    /// it — real playback events, not just the hand-off. Nothing in the app sets them.
    var onUtteranceBegan: ((AVSpeechUtterance) -> Void)?
    var onUtteranceFinished: ((AVSpeechUtterance) -> Void)?

    /// This is used for trolling (or debouncing) tts requests.
    /// `now` is the clock it reads — tests move it instead of paying the interval in
    /// wall-clock time.
    private var latestTTSRequestDate: Date?
    var now: () -> Date = Date.init
    
    /// Internal rather than private so tests can have an instance of their own: `speak`
    /// drops a request within 0.8 s of the previous one, and on `shared` that interval
    /// depends on whatever another suite spoke last. The app uses `shared`.
    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }
    
    /// - Returns: whether the utterance was accepted. A call inside the debounce
    ///   window is dropped silently, so callers whose action depends on speech
    ///   actually playing (Listen marks the answer aided) check this.
    @discardableResult
    func speak(_ utteranceString: NSAttributedString, language: String, immediately: Bool = true, rate: Float = Float(LWUserDefaults.standard.utteranceRatePreference), pitchMultiplier: Float = Float(LWUserDefaults.standard.pitchMultiplierPreference), owner: AnyObject? = nil) -> Bool {

        // Guard against too frequent calls to `synthesizer`.
        // Any frequent calls to `synthesizer` including stopping it cause it stop generating speech but no errors are emited.
        let currentDate = now()
        guard currentDate.timeIntervalSince(latestTTSRequestDate ?? .distantPast) > 0.8 else { return false }
        latestTTSRequestDate = currentDate

        ensureAudioSession()
        
        let utterance = AVSpeechUtterance(attributedString: utteranceString)
        //We can get voices that are present in system and then use set them either with identifiers or by using default for language
        //let voices = AVSpeechSynthesisVoice.speechVoices()
        //utterance.voice = AVSpeechSynthesisVoice(identifier: voice[0])
        // TODO: set from settings
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        //we can check (get only)
        //let  lang = utterance.voice?.language
        // Another way to get BCP-47 the code for the user’s current locale (as in Settings) This is a class func
        //let currentLang = AVSpeechSynthesisVoice.currentLanguageCode()
        // FIXME: UserDefaults.standard.float(forKey: "utteranceRatePreference")
//        utterance.rate = Float(LWUserDefaults.standard.utteranceRatePreference)
//        print(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceMaximumSpeechRate)
        
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier

        //we can set pre and post utterance delay
        utterance.preUtteranceDelay = 0.01
        utterance.postUtteranceDelay = 0.1
        
        if immediately {
            interrupt()
        }
        
        // Add to queue
        utteranceQueue.append((utterance, owner.map(ObjectIdentifier.init)))
        
        // Start processing if not already
        if !isProcessing {
            processQueue()
        }
        return true
    }
    
    /// Readies the synthesiser so the first utterance is not the one that pays for it.
    ///
    /// `AVSpeechSynthesizer` loads its voice on first use, which is why the word list
    /// touches `SpeechManager.shared` in `viewDidAppear` — a habit that worked by accident
    /// and said nothing about why. This names it, and does the other half: configuring the
    /// audio session up front, so the first `speak` is not also the first activation.
    func prewarm(language: String) {
        ensureAudioSession()
        _ = AVSpeechSynthesisVoice(language: language)
    }

    /// Runs `action` once nothing is being spoken or waiting to be: at once when the
    /// synthesiser is silent, otherwise when the last queued utterance finishes or is stopped.
    ///
    /// **Why anything waits.** Opening the microphone switches the shared audio session to
    /// `.playAndRecord`, and a word still being spoken is cut off by it. Phonetics used to
    /// open it on a fixed 1.2 s timer after the prompt started, which is shorter than a
    /// two-word prompt at a slow speech rate.
    ///
    /// Always called back on the main queue.
    func whenSilent(_ action: @escaping () -> Void) {
        guard isProcessing else { return action() }
        whenSilentActions.append(action)
    }

    func stopSpeaking() {
        interrupt()
        becameSilent()
    }

    /// Drops everything `owner` still has queued, and stops its utterance if it is the one
    /// playing. Other callers' speech is untouched: a screen that has gone has nothing left
    /// to say, but a queued prompt must not take a word-list preview down with it.
    func cancelSpeech(ownedBy owner: AnyObject) {
        let ownerID = ObjectIdentifier(owner)
        utteranceQueue.removeAll { $0.owner == ownerID }
        guard currentOwner == ownerID else { return }
        // Nil before stopping: if the utterance had already ended, no cancel arrives to
        // advance the queue — and a late one is ignored by the identity check.
        current = nil
        currentOwner = nil
        synthesizer.stopSpeaking(at: .immediate)
        processQueue()
    }

    /// Stops what is playing and drops what is queued, without announcing silence — the
    /// caller is about to speak again, and a microphone waiting on `whenSilent` must not
    /// open in the gap.
    private func interrupt() {
        utteranceQueue.removeAll()
        current = nil
        currentOwner = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func becameSilent() {
        let actions = whenSilentActions
        whenSilentActions.removeAll()
        actions.forEach { $0() }
    }

    /// The synthesizer runs on the app's shared audio session (`usesApplicationAudioSession`),
    /// so the app must configure/activate it or synthesis renders empty buffers
    /// ("mDataByteSize (0)") — historically only the Phonetics screen did this, so speech was
    /// silent until that screen was visited. Leaves `.playAndRecord` alone so the Phonetics
    /// mic flow isn't clobbered.
    private func ensureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback && session.category != .playAndRecord else { return }
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func processQueue() {
        guard !utteranceQueue.isEmpty else { return becameSilent() }
        let next = utteranceQueue.removeFirst()
        current = next.utterance
        currentOwner = next.owner
        synthesizer.speak(next.utterance)
    }

    /// The end of an utterance, finished or cancelled. One that was already replaced by a
    /// newer `speak` is ignored: its cancel arrives after the new one has started.
    fileprivate func utteranceEnded(_ utterance: AVSpeechUtterance) {
        guard utterance === current else { return }
        current = nil
        currentOwner = nil
        processQueue()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    // Apple does not say which queue these arrive on, and everything they touch is
    // main-confined — so they hop there.

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onUtteranceBegan?(utterance) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.onUtteranceFinished?(utterance)
            self.utteranceEnded(utterance)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.utteranceEnded(utterance) }
    }
}
