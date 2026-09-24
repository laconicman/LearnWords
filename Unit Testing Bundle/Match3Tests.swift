//
//  Match3Tests.swift
//  Unit Testing Bundle
//
//  `match3` is the judge behind dictation submit and every spoken answer. It now
//  lemmatises tokens before intersecting, so an inflected form of the right word
//  ("mice" for "mouse") counts — the answer the learner knows the lexeme, not
//  necessarily the dictionary form. These pin that semantic change and that
//  genuinely different words still miss.
//

import Testing
@testable import LearnWords

struct Match3Tests {

    @Test
    func exactMatches() {
        #expect(match3(pattern: "mouse", answer: "mouse", language: "en"))
    }

    @Test
    func unrelatedWordsMiss() {
        #expect(!match3(pattern: "mouse", answer: "keyboard", language: "en"))
    }

    @Test
    func anIrregularPluralMatchesItsLemma() {
        #expect(match3(pattern: "mouse", answer: "mice", language: "en"))
        #expect(match3(pattern: "mice", answer: "mouse", language: "en"))
    }

    @Test
    func anIrregularVerbFormMatchesItsLemma() {
        #expect(match3(pattern: "go", answer: "went", language: "en"))
    }

    @Test
    func determinersAreStillIgnored() {
        #expect(match3(pattern: "the cat", answer: "cat", language: "en"))
    }

    @Test
    func russianInflectionMatchesItsLemma() {
        // genitive "кошки" of nominative "кошка"
        #expect(match3(pattern: "кошка", answer: "кошки", language: "ru"))
    }

    @Test
    func aDifferentLexemeStillMisses() {
        // "kitten" shares no lemma with "cat" — the judge must not rubber-stamp it.
        #expect(!match3(pattern: "cat", answer: "kitten", language: "en"))
    }
}
