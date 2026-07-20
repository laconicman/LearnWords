//
//  LWButton.swift
//  LearnWords
//
//  The app's button control. Replaces GradientButton, whose fixed 2017 chrome
//  (gradient fill, hairline border, 5pt corners) rendered identically on every iOS
//  version — which is why it now clashes with the system-drawn bars around it.
//
//  A button states its *purpose*; this control decides how that purpose looks on the
//  OS it is running on. There is exactly one availability check, below, because every
//  button in the app funnels through here.
//
//    iOS 15+   UIButton.Configuration — the system draws it, and keeps drawing it
//              correctly as the platform moves (capsules, Liquid Glass metrics).
//    iOS 12–14 A small corner radius. Capsules belong to a later epoch; aping them
//              on iOS 12 would look more wrong than the flat rectangle does.
//
//  ("Purpose" rather than "role" because UIButton.role is already taken by UIKit.)
//
//  See docs/TechDebt.md TD-11 for the same graceful-degradation tier used by the
//  tab icons, and docs/Design.md for the deployment-target rationale.
//

import UIKit

@IBDesignable
final class LWButton: UIButton {

    // MARK: - Purpose

    /// What the button *means*. Appearance follows from this, so a screen never
    /// hard-codes a colour and the three exercise screens cannot drift apart.
    enum Purpose: String {
        /// Supporting actions — Look Up, Listen. Quiet, never competes with an answer.
        case utility
        /// "Know" — the affirmative answer.
        case affirmative
        /// "Forgot" — the negative answer. Not `destructive`: nothing is destroyed.
        case negative
        /// The main action on a screen — the exercise chooser, Start recognition.
        /// Tinted rather than filled: the chooser stacks three of these, and the HIG
        /// asks for at most one or two *prominent* buttons per view. Flip this one
        /// case to `.filled()` if a screen ever earns a single dominant CTA.
        case prominent
    }

    var purpose: Purpose = .utility { didSet { applyAppearance() } }

    /// Storyboard hook — Swift enums aren't `@IBInspectable`, so the scene sets the
    /// raw value as a user-defined runtime attribute (`purposeName`).
    @IBInspectable var purposeName: String {
        get { purpose.rawValue }
        set { purpose = Purpose(rawValue: newValue) ?? .utility }
    }

    // MARK: - Theming seam
    //
    // Gradients and borders are off by default — they read as dated, and the system
    // styles above are the point of this class. The knobs stay because the iOS 12–14
    // renderer has to exist anyway, so honouring them costs nothing, and a future
    // theme feature needs somewhere to land. This is a seam, not a theme *system*:
    // no theme model, no registry, until themes are actually built (YAGNI).
    //
    // Setting `startColor` or `endColor` opts a button out of the system appearance
    // entirely, on every OS version.

    @IBInspectable var startColor: UIColor? { didSet { applyAppearance() } }
    @IBInspectable var endColor: UIColor? { didSet { applyAppearance() } }
    @IBInspectable var borderColor: UIColor? { didSet { applyAppearance() } }
    @IBInspectable var borderWidth: CGFloat = 0 { didSet { applyAppearance() } }

    /// Corner radius used by the legacy and themed renderers.
    @IBInspectable var legacyCornerRadius: CGFloat = 5 { didSet { applyAppearance() } }

    /// Unthemed height at the default content size category. Scales with Dynamic Type.
    /// Comfortably past the HIG's 44pt minimum hit region without the old 72–100pt slabs.
    static let baseHeight: CGFloat = 56

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// `greaterThanOrEqual`, not `equal`: the constant is the *floor*. With fixed titles
    /// nothing pushes past it, so buttons still hold their size and position between
    /// questions — but a title that wraps at accessibility sizes can grow instead of
    /// being clipped.
    private lazy var heightConstraint: NSLayoutConstraint =
        heightAnchor.constraint(greaterThanOrEqualToConstant: Self.baseHeight)

    private func commonInit() {
        heightConstraint.isActive = true
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.5
        titleLabel?.adjustsFontForContentSizeCategory = true
        titleLabel?.numberOfLines = 0
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // The storyboard's localized title is in place by now; applyAppearance()
        // carries it into the configuration.
        applyAppearance()
    }

    // MARK: - Title
    //
    // Once a configuration is set, UIKit ignores the legacy title APIs for display.
    // Phonetics drives its record button through setTitle(_:for:) ("Start recognition"
    // / "Stopping" / …), so absorb that here rather than rewriting those call sites —
    // feature code shouldn't have to know which renderer is active.

    override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title, for: state)
        applyAppearance()
    }

    override func setImage(_ image: UIImage?, for state: UIControl.State) {
        super.setImage(image, for: state)
        applyAppearance()
    }

    // MARK: - Dynamic Type

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.preferredContentSizeCategory
                != previous?.preferredContentSizeCategory else { return }
        applyAppearance()
    }

    // MARK: - Appearance

    /// True when a caller has explicitly asked for the old chrome.
    private var isThemed: Bool { startColor != nil || endColor != nil }

    /// `applyFlatChrome` calls `setImage`, which is overridden to re-apply — break the cycle.
    private var isApplyingAppearance = false

    private func applyAppearance() {
        guard !isApplyingAppearance else { return }
        isApplyingAppearance = true
        defer { isApplyingAppearance = false }

        heightConstraint.constant = UIFontMetrics.default.scaledValue(for: Self.baseHeight)

        guard !isThemed else {
            applyThemedChrome()
            return
        }
        // The single availability branch in the app's button styling.
        if #available(iOS 15.0, *) {
            applySystemConfiguration()
        } else {
            applyLegacyChrome()
        }
    }

    // MARK: iOS 15+

    @available(iOS 15.0, *)
    private func applySystemConfiguration() {
        var config: UIButton.Configuration = purpose == .utility ? .gray() : .tinted()

        config.cornerStyle = .capsule
        if purpose == .utility {
            // Let .gray() supply the system's light fill — overriding it with the
            // secondary *text* colour turns a quiet button into the loudest slab
            // on the screen.
            config.baseForegroundColor = .lwTextPrimary
        } else {
            config.baseBackgroundColor = purposeColor
            config.baseForegroundColor = purposeColor
        }
        config.title = title(for: .normal)
        // The scene's own icon wins — the exercise chooser sets folder/keyboard/mic.
        config.image = image(for: .normal) ?? purposeImage
        config.imagePadding = 6
        // Wrap rather than truncate: "Английский → Русский" at an accessibility size
        // becomes "Английский…" otherwise, and a truncated answer button is useless.
        config.titleLineBreakMode = .byWordWrapping
        config.titleTextAttributesTransformer = .init { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .headline)
            return attributes
        }

        // A configuration draws its own background; leave the layer alone or its
        // corners clip the capsule.
        clearLayerChrome()
        configuration = config
    }

    // MARK: iOS 12–14

    private func applyLegacyChrome() {
        applyFlatChrome(fill: purposeColor.withAlphaComponent(0.18),
                        title: purpose == .utility ? .lwTextPrimary : purposeColor)
    }

    /// The pre-2026 look, on request: gradient fill plus border.
    private func applyThemedChrome() {
        applyFlatChrome(fill: .clear, title: .lwTextPrimary)
        gradientLayer.colors = [startColor ?? .clear, endColor ?? .clear].map(\.cgColor)
    }

    private func applyFlatChrome(fill: UIColor, title: UIColor) {
        if #available(iOS 15.0, *) { configuration = nil }
        gradientLayer.colors = nil
        backgroundColor = fill
        setTitleColor(title, for: .normal)
        titleLabel?.font = .preferredFont(forTextStyle: .headline)
        layer.cornerRadius = legacyCornerRadius
        layer.borderWidth = borderWidth
        layer.borderColor = borderColor?.cgColor
        if let purposeImage {
            setImage(purposeImage, for: .normal)
            tintColor = title
        }
    }

    private func clearLayerChrome() {
        gradientLayer.colors = nil
        backgroundColor = nil
        layer.cornerRadius = 0
        layer.borderWidth = 0
    }

    // MARK: - Purpose vocabulary

    private var purposeColor: UIColor {
        switch purpose {
        case .utility:     return .lwTextSecondary
        case .affirmative: return .lwAnswerCorrect
        case .negative:    return .lwAnswerWrong
        case .prominent:   return .lwAccent
        }
    }

    /// Icons carry the affirmative/negative distinction for anyone who can't rely on
    /// the red/green pair. `nil` on iOS 12 (no SF Symbols) — text-only, the same
    /// degradation the tab icons take (TD-11).
    private var purposeImage: UIImage? {
        switch purpose {
        case .affirmative: return .systemImage("checkmark")
        case .negative:    return .systemImage("xmark")
        case .utility, .prominent: return nil
        }
    }

    // MARK: - Layer

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
}
