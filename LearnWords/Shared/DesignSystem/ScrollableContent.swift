//
//  ScrollableContent.swift
//  LearnWords
//
//  Makes a screen's content stack scroll when it outgrows the screen — and only then.
//
//  Every screen in this app lays out a fixed vertical stack pinned to the safe area.
//  That was fine while every control had a fixed height, but once buttons and labels
//  scale with Dynamic Type the content can exceed the screen, and a plain UIStackView
//  has no answer for that: it compresses its arranged views past their constraints
//  until they overlap. The exercise screens each failed differently — Phonetics
//  overlapped its five buttons, Test and Dictation pushed the answer pair under the
//  tab bar — precisely because the same layout is duplicated across three storyboard
//  scenes, so nothing forced them to fail the same way. This is the one place that
//  answer now lives; every screen calls it.
//
//  `content` keeps a minimum height of one screenful, so short content still fills the
//  view (the word label expands and the flashcard stays centred) and only genuinely
//  taller content scrolls.
//

import UIKit

enum ScrollableContent {

    struct Wrapped {
        let scrollView: UIScrollView
        /// The scroll view's bottom pin. Dictation hands this to `UnderKeyboardLayoutConstraint`
        /// so keyboard avoidance keeps working after the re-parent.
        let bottomConstraint: NSLayoutConstraint
    }

    /// Re-parents `content` into a vertically scrolling view pinned to its container's
    /// safe area. Any constraints the scene had on `content` are dropped with it and
    /// replaced here.
    ///
    /// - Parameter fillsScreen: whether short content should stretch to a full screen.
    ///   True for the exercise screens, where `LWWordLabel` absorbs the slack and keeps
    ///   the flashcard centred. False for list-like screens such as the exercise chooser,
    ///   which have nothing elastic — there, stretching only opens a gap above the first
    ///   row, so the content keeps its natural height and sits at the top.
    @discardableResult
    static func wrap(_ content: UIView,
                     insets: UIEdgeInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20),
                     fillsScreen: Bool = true) -> Wrapped? {
        guard let container = content.superview else { return nil }

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive
        container.addSubview(scrollView)

        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let safeArea = container.safeAreaLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide
        let frameGuide = scrollView.frameLayoutGuide
        let bottom = safeArea.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            bottom,

            content.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -insets.right),

            // Pins the scrolling axis to vertical only.
            content.widthAnchor.constraint(equalTo: frameGuide.widthAnchor,
                                           constant: -(insets.left + insets.right)),

        ])

        if fillsScreen {
            // At least one screenful, and *only* that. An earlier version also pinned the
            // height *equal* to one screen at `defaultHigh`, meaning to make short content
            // fill the view — but this `greaterThanOrEqual` already does that, and the
            // equality actively forced tall content back down to one screen. Arranged
            // subviews then compressed until they overlapped: it is why the word and its
            // translation vanished at extra-large text, and why the chooser drew its
            // direction button over the "include learned words" row.
            // Never constrain scrolling content to fit.
            content.heightAnchor.constraint(greaterThanOrEqualTo: frameGuide.heightAnchor,
                                            constant: -(insets.top + insets.bottom)).isActive = true
        }

        return Wrapped(scrollView: scrollView, bottomConstraint: bottom)
    }
}
