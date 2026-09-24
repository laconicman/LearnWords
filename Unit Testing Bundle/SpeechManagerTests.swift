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

/// Nothing may start while a word is still being spoken: not the microphone, which cuts it
/// off by switching the audio session, and not the next word, which used to interrupt it.
///
/// Each test makes its own `SpeechManager`, because `speak` drops a request within 0.8 s of
/// the previous one and `shared` is spoken to by other suites.
@MainActor
@Suite(.serialized)
struct SpeechSilenceTests {

    private func word(_ text: String) -> NSAttributedString { NSAttributedString(string: text) }

    @Test func whenSilentRunsAtOnceWhenNothingIsSpeaking() {
        let speech = SpeechManager()
        var ran = false
        speech.whenSilent { ran = true }
        #expect(ran)
    }

    @Test func whenSilentWaitsForTheWordBeingSpoken() async throws {
        let speech = SpeechManager()
        speech.speak(word("polar bear"), language: "en-US")
        var ran = false
        speech.whenSilent { ran = true }
        #expect(!ran, "the word has only just started; the microphone would cut it off")

        try await waitUntil { ran }
        #expect(ran, "silence never came: a waiting microphone would never open")
    }

    /// `speak` replaces the current word, and the synthesiser reports the old one's cancel
    /// afterwards. That late cancel must not count as the new word ending.
    @Test func aLateCancelForAReplacedWordIsIgnored() async {
        let speech = SpeechManager()
        speech.speak(word("polar bear"), language: "en-US")
        var ran = false
        speech.whenSilent { ran = true }

        speech.speechSynthesizer(AVSpeechSynthesizer(),
                                 didCancel: AVSpeechUtterance(string: "a word already replaced"))
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }

        #expect(!ran, "a stale cancel ended the wait while the current word was still playing")
    }

    /// The next question's prompt is queued behind the revealed answer rather than cutting
    /// it off.
    @Test func aQueuedWordWaitsForTheOneBeingSpoken() async throws {
        let speech = SpeechManager()
        let recorder = UtteranceRecorder()
        speech.onUtteranceStarted = recorder.record

        speech.speak(word("polar bear"), language: "en-US")
        // `speak` drops a request within 0.8 s of the last; the reveal-to-prompt gap in the
        // app is 1.35 s, so this is the real spacing rather than a margin being bet on.
        try await Task.sleep(for: .milliseconds(850))
        speech.speak(word("fox"), language: "en-US", immediately: false)

        var silent = false
        speech.whenSilent { silent = true }
        try await waitUntil { silent }

        #expect(recorder.spoken == ["polar bear", "fox"],
                "the queued word was dropped, or interrupted the first")
    }
}

@MainActor
private final class UtteranceRecorder {
    private(set) var spoken: [String] = []
    func record(_ utterance: AVSpeechUtterance) { spoken.append(utterance.speechString) }
}
