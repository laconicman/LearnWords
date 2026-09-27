//
//  WaitUntil.swift
//  Unit Testing Bundle
//
//  Waiting on real UIKit animations. A completion can land long after the animation's
//  duration — a 0.52 s fade had not finished after a fixed 1.6 s sleep during a full parallel
//  run (TD-61) — so tests poll for the outcome instead of betting on a margin.
//

/// How long an animation's outcome is given to show up. Generous on purpose: a passing wait
/// returns as soon as its condition holds, so only a failure pays all of it.
let animationTimeout: Duration = .seconds(5)

/// Waits on real `AVSpeechSynthesizer` playback get a wider berth: utterances land in the
/// simulator's single speechsynthesisd queue, and its latency is the machine's, not the
/// test's — two short words that take ~2.3 s idle have been seen to need over 5 s under
/// load, while a pass still returns as soon as the delegate reports.
let speechTimeout: Duration = .seconds(20)

/// Polls `condition` every 20 ms until it holds or `budget` passes. It only waits —
/// assert afterwards, so a failure still reports which part of the condition was false.
@MainActor
func waitUntil(_ condition: () -> Bool, budget: Duration = animationTimeout) async throws {
    let deadline = ContinuousClock.now + budget
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}
