# Animation system — research & decision guide (TD-16)

Research (2026-07-19) to guide the animation-system redesign session. Context: a crash in
`WordTestViewController` (delayed `UIViewPropertyAnimator` + `[unowned self]` outliving the
screen) exposed that the exercise animations are copy-pasted and fragile; the owner wants a
modern, DRY system with delightful effects in the spirit of
[Pow](https://github.com/movingparts-io/Pow).

## Current state (after the hotfix)

- All three exercise screens (Test, Dictation, Phonetics) carry **the same two animations,
  copy-pasted**: spring-in (`dampingRatio: 0.5`, alpha/transform reset) and shrink-fade-out
  (`scale 0.8`, `easeInOut`) with an `askQuestion()` completion and a delayed start
  (0.1 s / 2 s). Six blocks total; all used `[unowned self]` — the Test screen crashed when
  the 2 s delay outlived the screen; now `[weak self]` everywhere (hotfixed, build green).
- Other animation code: `KDCircularProgress` (vendored control), `UnderKeyboardDistrib`
  (keyboard avoidance). No other delight/feedback effects exist.

## Pow — the facts

- **iOS 15+, MIT** (so porting/vendoring with attribution is fine), pure SwiftUI, SPM.
- **Change effects** (fire on a value change): Spray, Haptic, Jump, Ping, Rise, Shake,
  Shine, Spin, Sound. **Transitions** (insert/remove): Anvil, Blinds, Blur, Boing, Clock,
  Flicker, Film Exposure, Flip, Glare, Iris, Move, Pop, Poof, Rotate3D, Snapshot, Skid,
  Swoosh, Vanish, Wipe.
- **Implementation is physics, not keyframes**: e.g. Shake is a `ViewModifier` driven by
  `TimelineView` at 60 fps through a `SecondOrderDynamics` integrator (frequency 3,
  damping 0.85) chasing a decaying sinusoid — that's what makes it feel alive. A shared
  `Infrastructure/` layer (~20 files) holds the simulation math (`SecondOrderDynamics`,
  `Spring`, `Simulative`), a `ParticleLayer`, 3D transform helpers, and SwiftUI
  type-erasure plumbing (`AnyChangeEffect` etc.).

## OS-coverage math (Legacy floor 12.1)

`@available(iOS 15, *)`-gated effects reach **every supported device except the iOS 12 tier**
(iPhone 5s/6-era): iPhone 6s and newer all run iOS 15. So "Pow-gated delight + plain
animation fallback below 15" degrades gracefully for exactly the audience that already gets
text-only tabs (TD-11). SwiftUI hosting itself is iOS 13+.

## The UIKit-analog landscape (research result: thin)

No maintained Pow-equivalent exists for UIKit. Facebook's Pop is archived, Spring/Stellar/
anim are dead, Hero is transitions-only and in maintenance mode, Lottie is for
designer-authored vector animations (different tool). What's alive is narrow:
single-purpose confetti libs on `CAEmitterLayer`
([SwiftConfettiView](https://github.com/ugurethemaydin/SwiftConfettiView),
SPConfetti). The ecosystem answer for UIKit delight is: **compose it yourself** from
`CAKeyframeAnimation`/`CASpringAnimation`, `CAEmitterLayer` (particles),
`CAGradientLayer` masks (shine), `UIViewPropertyAnimator`.

## Options

**A. Use Pow directly via SwiftUI hosting (no port).**
Overlay a passthrough `UIHostingController` view above a UIKit view for *particle/overlay*
effects (Spray, Poof), or wrap whole SwiftUI islands (`swiftui-uikit-interop`).
✅ Zero porting, MIT, battle-tested feel. ❌ **Change effects can't move UIKit-rendered
content** (a hosted Shake shakes the SwiftUI overlay, not the UIKit label under it) — only
overlay effects work; iOS 15 gate; adds SwiftUI hosting complexity to every call site.

**B. UIKit analogs / hand-rolled kit.**
Small in-house `Shared/DesignSystem/Effects/`: classic CA shake, spring pops, emitter
spray, gradient shine. ✅ Works to the 12.1 floor, no dependencies, full control.
❌ Hand-tuned curves never feel as alive as Pow's physics; each effect is bespoke work.

**C. Port Pow to UIKit (owner-favored; separate session).**
Faithful port = `CADisplayLink`-driven `SecondOrderDynamics` (the math files are pure Swift
— **portable verbatim**), applying transforms to `CALayer` instead of SwiftUI modifiers;
particles = `CAEmitterLayer` (or port Pow's `ParticleLayer`). The SwiftUI type-erasure
plumbing is irrelevant to UIKit — skip it. ✅ Pow-quality feel, works to floor (CADisplayLink
is iOS 3+), MIT allows it. ❌ Real work per effect (~50–150 lines + a small shared
simulation core); a *full* 28-effect port is a library-sized project.

## Recommendation

**C-lite, staged — port only what the app needs, on a DRY base:**

1. **DRY first (no new tech):** extract the duplicated spring-in/fade-out pair into one
   shared `ExerciseTransitionAnimator` (Controller/DesignSystem layer) used by all three
   exercise screens, with lifetime-safe completion semantics. This discharges the crash
   class regardless of the delight decision.
2. **Port the shared simulation core** (`SecondOrderDynamics` + a `CADisplayLink` driver;
   one small file each) and **3–4 effects with clear product homes**: Shake (wrong answer),
   Shine or Jump (correct answer), Spray (word reaches known level). Live in
   `Shared/DesignSystem/Effects/`, MIT attribution in the header.
3. **Reassess after use.** If more effects are wanted later, add them one at a time; if the
   modern rewrite (TD-13 world) arrives first, it uses Pow directly — the ported effects'
   *product mapping* (which effect on which event) transfers as-is.

Option A remains a valid shortcut for purely-overlay celebration moments (Spray) if step 2
stalls — it's compatible with the same product mapping.

## Constraints & notes for the port session

- Floor 12.1: `UIViewPropertyAnimator` (iOS 10+), `CAEmitterLayer`, `CADisplayLink` all fine;
  `UIView.animate(springDuration:)` and CustomAnimationTiming APIs of iOS 17 are out.
- Respect `UIAccessibility.isReduceMotionEnabled` — Pow does; the port must too.
- Haptics on effect fire (`UINotificationFeedbackGenerator`) are cheap and add most of the
  perceived delight; they're iOS 10+.
- Keep effects **fire-and-forget on layers**, never capturing the VC (the TD-16 crash class).

## Port-precheck addendum (2026-07-19, second pass)

Verified before starting the port that no one has done it already:

- **Repo moved**: Pow is now maintained at [EmergeTools/Pow](https://github.com/EmergeTools/Pow)
  (Moving Parts partnered with Emerge Tools to open-source it; MIT, active as of 2026-04,
  ~4.3k stars). Links above to `movingparts-io/Pow` redirect there.
- **No UIKit port exists.** GitHub code search for `SecondOrderDynamics` finds only Pow
  itself, plain forks, and one unrelated render engine; repo search for a UIKit
  port/adaptation is empty. The maintainer closed
  ["Use in UIKit" (#58)](https://github.com/EmergeTools/Pow/issues/58) pointing to
  `UIHostingController`/`UIHostingConfiguration` — i.e. the official answer is Option A,
  and no UIKit API is planned.
- **New input for Option C**: [jtrivedi/Wave](https://github.com/jtrivedi/Wave) (MIT,
  iOS 13+, active 2026-03) is a maintained `CADisplayLink` spring-physics engine for
  UIKit/Core Animation. It could serve as the port's simulation core instead of porting
  `SecondOrderDynamics` — but it ships no effect presets (no Shake/Shine/Spray), and its
  iOS 13 floor is above ours. Porting Pow's own math verbatim (~1 small file) stays the
  default: zero dependencies, identical feel, works to 12.1. b3ll/Motion is the same idea
  but dormant (last push 2024).
- **Port started**: the `KaPow` SPM package at
  `/Users/paul/Documents/Code/Animations/KaPow` (iOS 12 floor; core +
  Shake ported, tests green) with the `KaPowShowcase` sibling app comparing each
  effect side-by-side against original Pow. Direction docs live in the package's
  DocC catalog — that is now the authoritative home for port decisions.
- **Port complete for the TD-16 mapping** (Shake, Jump, Shine, Spray — all
  verified side-by-side, 2026-07-19). Adoption is handed off to
  `TASK-TD16-adoption.md` in this folder — **executed 2026-07-19** (see its status
  header); only the manual feel-pass remains.

## Sources

- [Pow repo](https://github.com/movingparts-io/Pow) — README (effects, iOS 15+, MIT);
  `Sources/Pow/Effects/ShakeEffect.swift` (TimelineView + SecondOrderDynamics, ~60 lines
  core); `Sources/Pow/Infrastructure/` (simulation + particle + type-erasure files).
- [SwiftConfettiView](https://github.com/ugurethemaydin/SwiftConfettiView), SPConfetti —
  the surviving UIKit particle libs.
- `swiftui-uikit-interop` skill — hosting/overlay mechanics and their limits.
