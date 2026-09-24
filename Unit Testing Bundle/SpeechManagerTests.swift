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
/// the previous one and `shared` is spoken to by other suites. The debounce reads `now`, so
/// a test moves the clock forward itself rather than sleeping the interval away.
@MainActor
@Suite(.serialized)
struct SpeechSilenceTests {

    private func word(_ text: String) -> NSAttributedString { NSAttributedString(string: text) }

    /// A manager whose debounce clock the test drives, plus playback events observed from
    /// the synthesiser's own delegate callbacks — `began`/`finished`, not the hand-off.
    private func rig() -> (speech: SpeechManager, moment: () -> Date,
                           advance: (TimeInterval) -> Void,
                           began: () -> [String], finished: () -> [String]) {
        let speech = SpeechManager()
        var moment = Date(timeIntervalSince1970: 0)
        var began: [String] = []
        var finished: [String] = []
        speech.now = { moment }
        speech.onUtteranceBegan = { began.append($0.speechString) }
        speech.onUtteranceFinished = { finished.append($0.speechString) }
        return (speech, { moment }, { moment += $0 }, { began }, { finished })
    }

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
    /// it off. `began` and `finished` are the synthesiser's own reports: the second word
    /// beginning only after the first *finished* (not cancelled) is the uninterrupted
    /// playback, not just the order calls arrived in.
    @Test func aQueuedWordWaitsForTheOneBeingSpoken() async throws {
        let (speech, _, advance, began, finished) = rig()

        speech.speak(word("polar bear"), language: "en-US")
        advance(1)   // past the debounce — the app's reveal-to-prompt gap is 1.35 s
        speech.speak(word("fox"), language: "en-US", immediately: false)

        var silent = false
        speech.whenSilent { silent = true }
        try await waitUntil { silent }

        #expect(began() == ["polar bear", "fox"],
                "the queued word was dropped, or never actually started")
        #expect(finished() == ["polar bear", "fox"],
                "a word was cancelled rather than played out — the queue interrupted it")
    }

    /// A screen that has gone has nothing left to say: its queued prompt never starts,
    /// while another caller's queued word still plays.
    ///
    /// What is proven here is the queue — the part SpeechManager owns. Whether the
    /// in-flight word is audibly cut is the synthesiser's: the simulator answers `didFinish`
    /// for it either way, so that half wants an ear on a device (TD-38).
    @Test func leavingCancelsOnlyThatScreensSpeech() async throws {
        let (speech, _, advance, began, finished) = rig()
        let screen = NSObject()

        speech.speak(word("the answer"), language: "en-US", owner: screen)
        advance(1)
        speech.speak(word("the next prompt"), language: "en-US", immediately: false,
                     owner: screen)
        advance(1)
        speech.speak(word("a word-list preview"), language: "en-US", immediately: false)

        speech.cancelSpeech(ownedBy: screen)

        var silent = false
        speech.whenSilent { silent = true }
        try await waitUntil { silent }

        #expect(!began().contains("the next prompt") && !finished().contains("the next prompt"),
                "a prompt queued by the departed screen still played")
        #expect(finished().contains("a word-list preview"),
                "another caller's speech was taken down with the screen's")
    }
}
