//
//  SpeechSynth.swift
//  LearnWords
//
//  Created by  Paul on 16.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import Foundation
import AVFoundation

final class LWSpeechSynth {
    
    static var standard = LWSpeechSynth()
    private lazy var sytheiser = AVSpeechSynthesizer() // Made it global, to avoid initialization for every vc creation
    
    private init() {
    }
    
    func speak(utteranceString: NSAttributedString, language: String) {
        let utterance = AVSpeechUtterance(attributedString: utteranceString)
        //var utterance =  AVSpeechUtterance(string: foreignWord.text ?? "")
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
//

        utterance.rate = Float(LWUserDefaults.standard.utteranceRatePreference)
        utterance.pitchMultiplier = Float(LWUserDefaults.standard.pitchMultiplierPreference)

        //we can set pre and post utterance delay
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        sytheiser.stopSpeaking(at: .immediate)
        sytheiser.speak(utterance)

    }
}
