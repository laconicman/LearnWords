//
//  MaxKnownLevel.swift
//  Unit Testing Bundle
//
//  Parent suite for every test that depends on `WordAndStat.maxKnownLevel`, which reads
//  the global `LWUserDefaults.maxKnownLevelPreference`.
//
//  `.serialized` orders tests *within* a suite, not across suites. `WordAndStatTests` was
//  safe alone, but the moment `ExerciseSessionTests` also began pinning that preference the
//  two suites raced and a level-up assertion failed intermittently — passing in isolation,
//  failing in the full run. Nesting both under one serialized parent serializes the whole
//  family, so the shared global has a single writer at a time.
//
//  The real fix is for `maxKnownLevel` to be injected rather than read from a global; that
//  belongs with the TD-13 persistence work, not here.
//

import Testing
import Foundation
@testable import LearnWords

@Suite(.serialized)
enum MaxKnownLevel {

    /// Runs `body` with `maxKnownLevelPreference` pinned to `level`, then restores it.
    static func pinned(_ level: Int, _ body: () -> Void) {
        let defaults = LWUserDefaults.standard
        let original = defaults.maxKnownLevelPreference
        defaults.maxKnownLevelPreference = level
        defer { defaults.maxKnownLevelPreference = original }
        body()
    }
}
