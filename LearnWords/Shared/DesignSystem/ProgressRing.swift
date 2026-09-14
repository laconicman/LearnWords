//
//  ProgressRing.swift
//  LearnWords
//
//  The progress indicator on a word row: two concentric arcs that say how well a meaning
//  is known and how much work went into it.
//
//  **Two arcs, because there are two stories** (`docs/ProgressModel.md` R3). The outer arc
//  is **mastery** — how durable the memory is. The inner arc is **effort** — everything the
//  learner has put in, which never goes down even when mastery does. A word you have
//  fought with for a month and still get wrong shows a full inner arc and a thin outer one,
//  and that is the honest picture. One arc could not tell those apart from a word you have
//  never touched.
//
//  **Colour carries retention.** The outer arc tints from the accent colour toward a warm
//  "due soon" tone as the chance of recalling it right now falls. So a fully-mastered word
//  that has not been seen in months reads as complete-but-fading, which is exactly what it
//  is.
//
//  Replaces `KDCircularProgress` — 556 vendored lines from 2015 (TD-17). Two `CAShapeLayer`
//  arcs need far less, animate with a spring so a level-up *settles* rather than jumps, and
//  scale with Dynamic Type as R6 requires.
//

import UIKit

final class ProgressRing: UIView {

    // MARK: - Values

    /// How well learned, 0…1 — the outer arc.
    var mastery: Float = 0
    /// Work invested, 0…1 — the inner arc.
    var effort: Float = 0
    /// Chance of recall right now, 0…1 — the outer arc's colour.
    var retention: Float = 1

    /// Sets all three at once, springing to the new values.
    ///
    /// Animation is opt-out because the common caller is a table cell: a cell being
    /// *configured* on dequeue must not animate (it would smear the previous row's value
    /// across the new one), while a cell being *updated* in place should.
    func setProgress(mastery: Float, effort: Float, retention: Float, animated: Bool) {
        self.mastery = mastery
        self.effort = effort
        self.retention = retention
        applyValues(animated: animated)
    }

    // MARK: - Layers

    private let masteryTrack = CAShapeLayer()
    private let masteryArc = CAShapeLayer()
    private let effortTrack = CAShapeLayer()
    private let effortArc = CAShapeLayer()

    private var arcs: [CAShapeLayer] { [masteryTrack, effortTrack, masteryArc, effortArc] }

    // MARK: - Metrics

    /// Stroke width as a fraction of the view's width, so the ring keeps its proportions
    /// at every Dynamic Type size instead of turning into a hairline when it grows.
    private let masteryStrokeRatio: CGFloat = 0.11
    private let effortStrokeRatio: CGFloat = 0.06
    private let gapRatio: CGFloat = 0.05

    /// R6: the indicator follows the type scale and never drives row height against the
    /// font. 44pt at the default content size.
    override var intrinsicContentSize: CGSize {
        let side = UIFontMetrics(forTextStyle: .body).scaledValue(for: 44)
        return CGSize(width: side, height: side)
    }

    // MARK: - Life cycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false      // the row speaks for it; see `accessibilityText`

        for arc in arcs {
            arc.fillColor = UIColor.clear.cgColor
            arc.lineCap = .round
            arc.strokeEnd = 0
            layer.addSublayer(arc)
        }
        masteryTrack.strokeEnd = 1
        effortTrack.strokeEnd = 1
        applyColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let side = min(bounds.width, bounds.height)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let masteryWidth = side * masteryStrokeRatio
        let effortWidth = side * effortStrokeRatio
        let masteryRadius = (side - masteryWidth) / 2
        let effortRadius = masteryRadius - masteryWidth / 2 - side * gapRatio - effortWidth / 2

        // Both arcs start at twelve o'clock and run clockwise — the direction a reader
        // expects a dial to fill.
        func path(radius: CGFloat) -> CGPath {
            UIBezierPath(arcCenter: centre,
                         radius: max(radius, 0.5),
                         startAngle: -.pi / 2,
                         endAngle: 3 * .pi / 2,
                         clockwise: true).cgPath
        }

        for arc in [masteryTrack, masteryArc] {
            arc.path = path(radius: masteryRadius)
            arc.lineWidth = masteryWidth
        }
        for arc in [effortTrack, effortArc] {
            arc.path = path(radius: max(effortRadius, masteryWidth))
            arc.lineWidth = effortWidth
        }
        for arc in arcs { arc.frame = bounds }

        applyValues(animated: false)
    }

    // MARK: - Applying

    private func applyValues(animated: Bool) {
        set(masteryArc, to: mastery, animated: animated)
        set(effortArc, to: effort, animated: animated)
        applyColors()
    }

    private func set(_ arc: CAShapeLayer, to value: Float, animated: Bool) {
        let clamped = CGFloat(min(max(value, 0), 1))
        guard animated else {
            // No implicit animation either — a dequeued cell must appear at its value,
            // not travel to it from the previous row's.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.strokeEnd = clamped
            CATransaction.commit()
            return
        }
        guard abs(arc.strokeEnd - clamped) > 0.0005 else { return }

        // A spring, so a level-up settles instead of snapping — the same physical feel as
        // the KaPow moments elsewhere (TD-16).
        let spring = CASpringAnimation(keyPath: "strokeEnd")
        spring.fromValue = arc.presentation()?.strokeEnd ?? arc.strokeEnd
        spring.toValue = clamped
        spring.damping = 14
        spring.stiffness = 130
        spring.mass = 0.7
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        spring.timingFunction = CAMediaTimingFunction(name: .easeOut)
        arc.strokeEnd = clamped
        arc.add(spring, forKey: "strokeEnd")
    }

    // MARK: - Colour

    /// Resolved against the current traits, because a `CALayer` holds a `CGColor` and a
    /// `CGColor` cannot follow light/dark on its own — it has to be re-resolved whenever
    /// the traits change, which is what `traitCollectionDidChange` below is for.
    private func resolved(_ color: UIColor) -> CGColor {
        color.resolvedColor(with: traitCollection).cgColor
    }

    private func applyColors() {
        masteryTrack.strokeColor = resolved(.lwTrack)
        effortTrack.strokeColor = resolved(.lwTrack)
        // Effort is context for mastery, not a rival to it, so it stays quiet.
        effortArc.strokeColor = resolved(.lwTextSecondary.withAlphaComponent(0.45))
        masteryArc.strokeColor = resolved(masteryColor)
    }

    /// Accent when the word is fresh in mind, warming toward the "wrong" tone as the
    /// chance of recall falls. Not red — an overdue word is not a mistake.
    private var masteryColor: UIColor {
        let risk = CGFloat(1 - min(max(retention, 0), 1))
        return UIColor.lwAccent.blended(with: .lwAnswerWrong, amount: risk * 0.6)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
            applyColors()
        }
        if traitCollection.preferredContentSizeCategory != previous?.preferredContentSizeCategory {
            invalidateIntrinsicContentSize()
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    // MARK: - Accessibility

    /// What the ring is worth saying out loud. The cell owns the phrasing; this is the
    /// part only the ring knows.
    var accessibilityText: String {
        let percent = Int((mastery * 100).rounded())
        return String(format: NSLocalizedString("%d%% learned", comment: "progress ring"),
                      percent)
    }
}

// MARK: - Blending

private extension UIColor {
    /// Linear blend in sRGB. Enough for a two-stop tint, and it keeps the ring's colour
    /// logic readable at the call site.
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        let t = min(max(amount, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}
