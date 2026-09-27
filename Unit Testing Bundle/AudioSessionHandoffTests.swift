//
//  AudioSessionHandoffTests.swift
//  Unit Testing Bundle
//
//  The TD-15 regression, asserted rather than remembered.
//
//  TD-15 was: speech silently dead after visiting Phonetics — no error, no crash, nothing
//  in the log. The cause was the audio session left in a state the synthesiser could not
//  render into, and the reason it took so long to find is that *silence is not an
//  exception*. Nothing throws; the buffers simply come back empty.
//
//  Extracting `DictationController` reintroduced it. The extraction's `stop()` deactivated
//  the session and left the category at `.playAndRecord` — which passes `SpeechManager`'s
//  guard untouched, so nothing would ever reactivate it. These cases pin the contract that
//  closes it for good.
//

import Testing
import AVFoundation
@testable import LearnWords

/// Nested under SpeechSuite so its shared-audio-session pokes cannot overlap the
/// speech suites' utterances — a `.serialized` trait on this suite alone would still
/// let it run in parallel with them.
extension SpeechSuite {
    @MainActor
    struct AudioSessionHandoffTests {

        private var session: AVAudioSession { .sharedInstance() }

        /// The whole contract in one line: after dictation, playback owns the session.
        @Test func releasingHandsTheSessionToPlayback() {
            DictationController.shared.releaseSessionToPlayback()
            #expect(session.category == .playback)
        }

        /// The specific shape of the bug: never `.playAndRecord` left behind, because that is
        /// the category `SpeechManager.ensureAudioSession` treats as "already fine" and
        /// declines to reactivate.
        @Test func recordingCategoryIsNeverLeftBehind() throws {
            // Put the session where a recording round would have left it.
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            #expect(session.category == .playAndRecord, "precondition")

            DictationController.shared.stop()

            #expect(session.category != .playAndRecord,
                    "leaving .playAndRecord is TD-15: the synthesiser's guard skips it and never reactivates")
            #expect(session.category == .playback)
        }

        /// `stop` is called from `viewWillDisappear` and from `willLeaveCurrentQuestion`
        /// whether or not anything was recording, so it must be safe when idle — and must
        /// still perform the handoff, since an early return was the original defect.
        @Test func stoppingWhenNothingIsRecordingStillHandsTheSessionBack() throws {
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            #expect(!DictationController.shared.isRecording, "precondition: nothing to stop")

            DictationController.shared.stop()

            #expect(session.category == .playback)
        }

        @Test func releasingTwiceIsHarmless() {
            DictationController.shared.releaseSessionToPlayback()
            DictationController.shared.releaseSessionToPlayback()
            #expect(session.category == .playback)
        }

        /// The other half of the contract, asserted from `SpeechManager`'s side: the
        /// synthesiser must actually start on the session dictation left behind. A
        /// category check alone is not the contract — a `.playback` session that was
        /// never activated passes it while rendering silence (the TD-15 shape again),
        /// so this waits for the synthesiser's own `didStart` report.
        @Test func speechManagerAcceptsTheStateDictationLeavesBehind() async throws {
            defer { SpeechManager.shared.stopSpeaking() }
            var began = false
            SpeechManager.shared.onUtteranceBegan = { _ in began = true }
            defer { SpeechManager.shared.onUtteranceBegan = nil }

            DictationController.shared.releaseSessionToPlayback()
            SpeechManager.shared.speak(NSAttributedString(string: "bear"), language: "en-US")

            try await waitUntil({ began }, budget: speechTimeout)
            #expect(began, "the synthesiser never started — the session was left inactive (TD-15)")
        }
    }
}
