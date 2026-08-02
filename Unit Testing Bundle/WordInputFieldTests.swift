//
//  WordInputFieldTests.swift
//  Unit Testing Bundle
//
//  Regression for TD-41: the dictation button was installed as the field's `rightView`.
//  A `rightView` and the clear button occupy the same place and the `rightView` wins
//  silently, so the field could not be emptied except by selecting and deleting.
//
//  Checked as geometry rather than as an assignment: the defect was two controls claiming
//  one rect, and `clearButtonRect(forBounds:)` is where UIKit says that rect is.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct WordInputFieldTests {

    /// Lays the screen out without appearing it — `viewDidAppear` takes first responder and
    /// `viewWillAppear` prewarms the recogniser, neither of which this is about.
    private func laidOutHeader(_ purpose: WordInputViewController.Purpose,
                               context: WordInputViewController.Context? = nil) throws -> UIView {
        let vc = WordInputViewController(purpose, context: context) { _ in }
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        vc.view.layoutIfNeeded()
        // `sizeHeaderToFit` runs *in* the first pass and resizes the header from it, so the
        // subviews' own frames settle on the second.
        vc.view.layoutIfNeeded()
        return try #require(vc.tableView.tableHeaderView)
    }

    private func laidOutField(_ purpose: WordInputViewController.Purpose) throws -> UITextField {
        let field = try #require(firstView(UITextField.self, in: laidOutHeader(purpose)))
        #expect(field.bounds.width > 0, "precondition: the field was laid out")
        return field
    }

    @Test func dictationLeavesTheClearButtonItsPlace() throws {
        let field = try laidOutField(.add(language: "en"))

        #expect(field.leftView != nil, "precondition: dictation is offered")
        #expect(field.rightView == nil, "a rightView takes the clear button's place")

        let clear = field.clearButtonRect(forBounds: field.bounds)
        let dictation = field.leftViewRect(forBounds: field.bounds)
        #expect(!clear.isEmpty && !dictation.isEmpty, "precondition: both controls have a rect")
        #expect(!clear.intersects(dictation),
                "dictation must not sit where the clear button appears — TD-41")
    }

    /// Omitted rather than hidden, so nothing reserves an inset for a control that cannot act.
    @Test func aNoteOffersNoDictation() throws {
        #expect(try laidOutField(.note).leftView == nil)
    }

    /// TD-44: the word may have been typed without ever being looked up, and this screen is
    /// where the learner has to say what it means.
    @Test func theHintOffersDictionaryLookup() throws {
        let header = try laidOutHeader(
            .add(language: "ru"),
            context: .init(caption: "Word", term: "bear"))
        let lookUp = try #require(firstView(UIButton.self, in: header) {
            $0.buttonType == .detailDisclosure
        })
        #expect(lookUp.bounds.width >= 44 && lookUp.bounds.height >= 44,
                "the ⓘ glyph is about 22pt; the rest has to be reachable area")
        #expect(lookUp.actions(forTarget: lookUp.allTargets.first as Any,
                              forControlEvent: .touchUpInside)?.isEmpty == false,
                "the button has to actually do something")
    }

    /// Without a pinned term there is nothing to look up, so nothing offers to.
    @Test func aScreenWithNoHintHasNoLookupButton() throws {
        let header = try laidOutHeader(.add(language: "en"))
        #expect(firstView(UIButton.self, in: header) { $0.buttonType == .detailDisclosure } == nil)
    }
}

private func firstView<T: UIView>(_ type: T.Type, in view: UIView,
                                  where matches: (T) -> Bool = { _ in true }) -> T? {
    if let found = view as? T, matches(found) { return found }
    for subview in view.subviews {
        if let found = firstView(type, in: subview, where: matches) { return found }
    }
    return nil
}
