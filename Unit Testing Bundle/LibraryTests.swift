//
//  LibraryTests.swift
//  Unit Testing Bundle
//
//  Launch preparation — the work `prepareForLaunch` does before the first
//  screen exists.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct LibraryTests {

    private func freshLibrary() -> Library {
        Library(persistence: LWPersistence(inMemory: true),
                defaults: UserDefaults(suiteName: "LibraryTests-\(UUID())")!)
    }

    /// TD-26's residual (issue #57): the collector had no production caller, so
    /// meanings stranded by paths other than last-set removal accumulated.
    /// `prepareForLaunch` now runs the sweep once per launch, inside the same
    /// post-import wait as seeding — a half-delivered store cannot prove
    /// orphanhood, and a wrong delete would mirror to CloudKit.
    @Test func prepareForLaunchCollectsStrandedMeanings() async throws {
        let library = freshLibrary()
        let lexicon = library.lexicon
        let set = try lexicon.addWordSet(named: "Animals")
        let sense = try lexicon.addSense(to: set.id,
                                         terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.deleteWordSet(set.id)   // strands the meaning, deletes nothing else

        #expect(try lexicon.sense(sense.id) != nil, "stranded, not deleted")

        library.prepareForLaunch()
        // The sweep rides the same post-import wait as seeding, so it has not run
        // yet — a synchronous sweep would already have taken the meaning.
        #expect(try lexicon.sense(sense.id) != nil, "the sweep waits for sync to settle")
        try await waitUntil { (try? lexicon.sense(sense.id)) == nil }

        #expect(try lexicon.sense(sense.id) == nil, "the launch sweep collected it")
    }
}
