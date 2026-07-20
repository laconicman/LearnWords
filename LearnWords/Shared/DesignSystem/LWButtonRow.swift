//
//  LWButtonRow.swift
//  LearnWords
//
//  A pair of exercise buttons that stands side by side normally and stacks vertically
//  at accessibility text sizes.
//
//  Two half-width buttons cannot hold a scaled-up title: at
//  `accessibility-extra-large` the Russian titles truncated to "В сло…" and "Зн…",
//  which is worse than useless on the button you press to answer. Giving each button
//  the full width at those sizes is the system's own answer — `UIAlertController`
//  stacks its actions the same way for the same reason.
//

import UIKit

final class LWButtonRow: UIStackView {

    override func awakeFromNib() {
        super.awakeFromNib()
        // The scenes disagreed: Test's utility row was `fillEqually` while Dictation's
        // and Phonetics' were plain `fill` with hand-drawn equal-*width* constraints.
        // Once a row stacks vertically those width constraints say nothing about height,
        // so "В словаре" came out visibly shorter than "Слушать" on Phonetics alone.
        // The row decides this now, not three separate storyboard scenes.
        distribution = .fillEqually
        applyAxis()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.preferredContentSizeCategory
                != previous?.preferredContentSizeCategory else { return }
        applyAxis()
    }

    private func applyAxis() {
        // `isAccessibilityCategory` is iOS 11+, so it clears the 12.1 floor.
        axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? .vertical
            : .horizontal
    }
}
