//
//  StringCanonicaliseTests.swift
//  Unit Testing Bundle
//
//  `String.canonicalise()` normalizes user-entered words before storage/lookup.
//

import Testing
@testable import LearnWords

struct StringCanonicaliseTests {

    @Test(arguments: [
        ("  Hello  ", "hello"),          // trims surrounding whitespace, lowercases
        ("WORLD", "world"),              // lowercases
        ("\tBear\n", "bear"),            // trims tabs/newlines
        ("already", "already"),          // no-op when already canonical
        ("  Multiple   Words  ", "multiple   words"), // inner spacing preserved
    ])
    func lowercasesAndTrimsWhitespace(input: String, expected: String) {
        #expect(input.canonicalise() == expected)
    }
}
