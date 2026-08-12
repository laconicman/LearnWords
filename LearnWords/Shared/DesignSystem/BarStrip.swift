//
//  BarStrip.swift
//  LearnWords
//
//  A row of proportional bars — the summary's only chart (TD-51).
//
//  One view for both jobs it has, because they are the same picture read two ways: laid
//  **across**, three segments of one bar are a distribution (untouched / learning /
//  learned); laid **along**, fourteen bars of their own height are a forecast. Building two
//  views would have been two sets of rounding, two sets of empty states and two chances to
//  disagree about what a zero looks like.
//
//  Drawn with plain layers rather than a charting dependency: the whole thing is rectangles,
//  it has to run at the iOS 12 floor, and a chart library would be the largest thing in the
//  app by some margin.
//

import UIKit

final class BarStrip: UIView {

    /// One bar, or one segment of one.
    struct Segment {
        let value: Int
        let colour: UIColor
        /// Shown under the bar in `.alongside` layout, and read out by VoiceOver in both.
        let label: String?

        init(value: Int, colour: UIColor, label: String? = nil) {
            self.value = value
            self.colour = colour
            self.label = label
        }
    }

    enum Layout {
        /// Segments share one bar, sized by proportion — a distribution.
        case stacked
        /// Segments stand side by side, each as tall as its share of the largest — a
        /// forecast.
        case alongside
    }

    private let layout: Layout
    private var segments: [Segment] = []
    private var bars: [CALayer] = []

    init(layout: Layout) {
        self.layout = layout
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(layout:)") }

    func show(_ segments: [Segment]) {
        self.segments = segments
        accessibilityLabel = segments
            .compactMap { segment in
                segment.label.map { "\($0): \(segment.value)" }
            }
            .joined(separator: ", ")
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: layout == .stacked ? Self.stackedHeight : Self.alongsideHeight)
    }

    /// Thick enough to read as a measurement rather than a hairline, and to carry a corner
    /// radius that does not swallow a small segment.
    private static let stackedHeight: CGFloat = 14
    private static let alongsideHeight: CGFloat = 48
    private static let gap: CGFloat = 2

    override func layoutSubviews() {
        super.layoutSubviews()
        bars.forEach { $0.removeFromSuperlayer() }
        bars = []
        guard bounds.width > 0, !segments.isEmpty else { return }

        switch layout {
        case .stacked: layOutStacked()
        case .alongside: layOutAlongside()
        }
    }

    private func layOutStacked() {
        let total = segments.reduce(0) { $0 + $1.value }
        // Nothing to divide: one flat track, so an empty set reads as "nothing yet" rather
        // than as a missing view.
        guard total > 0 else {
            return addBar(CGRect(origin: .zero, size: bounds.size),
                          colour: .lwTextSecondary.withAlphaComponent(0.15))
        }

        var x: CGFloat = 0
        for (index, segment) in segments.enumerated() where segment.value > 0 {
            // The last visible segment takes the remainder, so rounding never leaves a gap
            // at the end of a bar that is meant to be full.
            let isLast = !segments[(index + 1)...].contains { $0.value > 0 }
            let width = isLast
                ? bounds.width - x
                : (bounds.width * CGFloat(segment.value) / CGFloat(total)).rounded()
            addBar(CGRect(x: x, y: 0, width: width, height: bounds.height), colour: segment.colour)
            x += width
        }
    }

    private func layOutAlongside() {
        let tallest = segments.map(\.value).max() ?? 0
        let slot = (bounds.width - Self.gap * CGFloat(segments.count - 1)) / CGFloat(segments.count)

        for (index, segment) in segments.enumerated() {
            let x = (slot + Self.gap) * CGFloat(index)
            // A day with nothing due still gets a mark: a gap in a forecast reads as missing
            // data, and "nothing on Thursday" is information worth showing.
            let share = tallest == 0 ? 0 : CGFloat(segment.value) / CGFloat(tallest)
            let height = max(2, bounds.height * share)
            addBar(CGRect(x: x, y: bounds.height - height, width: slot, height: height),
                   colour: segment.value == 0
                       ? .lwTextSecondary.withAlphaComponent(0.15)
                       : segment.colour)
        }
    }

    private func addBar(_ frame: CGRect, colour: UIColor) {
        let bar = CALayer()
        bar.frame = frame
        // Resolved the same way `ProgressRing` does — a `CGColor` is a fixed colour, and
        // `resolvedColor(with:)` does not exist at the 12.1 floor.
        if #available(iOS 13.0, *) {
            bar.backgroundColor = colour.resolvedColor(with: traitCollection).cgColor
        } else {
            bar.backgroundColor = colour.cgColor
        }
        bar.cornerRadius = min(2, frame.height / 2)
        layer.addSublayer(bar)
        bars.append(bar)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // `CALayer` holds a resolved colour, so dark mode has to be re-applied by hand.
        setNeedsLayout()
    }
}
