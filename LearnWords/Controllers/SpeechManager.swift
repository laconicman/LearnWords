//
//  SpeechManager.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/26/25.
//  Copyright © 2025 Paul. All rights reserved.
//


import AVFoundation

final class SpeechManager /*: NSObject */ {
    static let shared = SpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceQueue = [AVSpeechUtterance]()
    private var isProcessing: Bool { // Maybe call it `isSpeaking`.
        synthesizer.isSpeaking || synthesizer.isPaused
    }
    /// This is used for trolling (or debouncing) tts requests.
    private var latestTTSRequestDate: Date?
    
    private /* override */ init() {
        // super.init()
        if #available(iOS 13.0, *) {
            synthesizer.usesApplicationAudioSession = true
        }
        // synthesizer.delegate = self
    }
    
    func speak(_ utteranceString: NSAttributedString, language: String, immediately: Bool = true, rate: Float = Float(LWUserDefaults.standard.utteranceRatePreference), pitchMultiplier: Float = Float(LWUserDefaults.standard.pitchMultiplierPreference)) {
        
        // Guard against too frequent calls to `synthesizer`.
        // Any frequent calls to `synthesizer` including stopping it cause it stop generating speech but no errors are emited.
        let currentDate = Date()
        guard currentDate.timeIntervalSince(latestTTSRequestDate ?? .distantPast) > 0.8 else { return }
        latestTTSRequestDate = currentDate
        
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
            stopSpeaking()
        }
        
        // Add to queue
        utteranceQueue.append(utterance)
        
        // Start processing if not already
        if !isProcessing {
            processQueue()
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        utteranceQueue.removeAll()
    }
    
    private func processQueue() {
        guard !utteranceQueue.isEmpty else { return }
        let utterance = utteranceQueue.removeFirst()
        synthesizer.speak(utterance)
    }
}

//// MARK: - AVSpeechSynthesizerDelegate
//extension SpeechManager: AVSpeechSynthesizerDelegate {
//    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
//        // Wait a small delay before processing next item for stability
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
//            self?.processQueue()
//        }
//    }
//    
//    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
//            self?.processQueue()
//        }
//    }
//}
