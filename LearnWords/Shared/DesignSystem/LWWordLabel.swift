//
//  LWWordLabel.swift
//  LearnWords
//
//  The big word/answer display on the exercise screens.
//
//  Its job is to be the *elastic* part of the layout. The exercise screens pin their
//  buttons to a fixed height (LWButton.baseHeight) and give the remaining space to
//  these labels, so a verbose word shrinks its own text instead of pushing the
//  buttons around. Before this, the exercise stacks used `fillProportionally` and a
//  long translation resized and moved the buttons between questions.
//
//  Keeps whatever point size the scene sets — the flashcard is meant to be large —
//  and only ever scales *down* from it.
//

import UIKit

final class LWWordLabel: UILabel {

    /// Floor for autoshrink. Low enough that even a long compound translation fits,
    /// high enough that it never becomes unreadable.
    private static let minimumScale: CGFloat = 0.3

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = Self.minimumScale
        // Single line, deliberately. UILabel only applies `adjustsFontSizeToFitWidth`
        // when `numberOfLines == 1`; with two lines it wraps and then *clips* instead
        // of scaling, which is how "главный докладчик" rendered as "главный / докладчи"
        // at the default text size. One line always shrinks to fit, so nothing is ever
        // cut off — at 80pt with a 0.3 floor even a long compound phrase stays large.
        numberOfLines = 1
        lineBreakMode = .byClipping
        textAlignment = .center
        // Low hugging: absorb the slack the buttons no longer take, so a short word
        // still centres in a full screen.
        setContentHuggingPriority(.defaultLow - 1, for: .vertical)
        // High compression resistance: expanding is welcome, disappearing is not. With
        // this at `.defaultLow` the label was the first thing squeezed when the screen
        // ran out of room, and at extra-large text the word being studied compressed to
        // nothing — the one thing on the screen that must never be lost.
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
    }
}
