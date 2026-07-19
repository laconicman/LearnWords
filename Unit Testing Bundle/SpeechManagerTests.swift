//
//  SpeechManagerTests.swift
//  Unit Testing Bundle
//
//  Regression test for the "silent until Phonetics" bug: SpeechManager uses the app's
//  shared audio session, so speak() must configure/activate it itself.
//

import Testing
import AVFoundation
@testable import LearnWords

struct SpeechManagerTests {

    @Test func speakConfiguresPlaybackAudioSession() {
        #expect(AVAudioSession.sharedInstance().category != .playAndRecord,
                "precondition: no mic flow active in the test host")

        SpeechManager.shared.speak(NSAttributedString(string: "bear"), language: "en-US")

        let category = AVAudioSession.sharedInstance().category
        #expect(category == .playback,
                "speak() must set up the shared session — it was silent until Phonetics did it")
    }
}
