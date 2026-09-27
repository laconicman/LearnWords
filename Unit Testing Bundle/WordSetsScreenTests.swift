//
//  WordSetsScreenTests.swift
//  Unit Testing Bundle
//
//  Wiring checks for the sets screen — the parts a compile check cannot see.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct WordSetsScreenTests {

    // The picker must be built on the non-deprecated initializer with the view
    // controller as its delegate. Presenting it is a device concern: a test host
    // has no document-browser service and aborts where a real app would not.
    @Test func importButtonBuildsAConfiguredPicker() {
        let vc = WordSetsTableViewController(style: .plain)

        let picker = vc.makeImportPicker()

        #expect(picker.delegate === vc)
        #expect(!picker.allowsMultipleSelection)
    }
}
