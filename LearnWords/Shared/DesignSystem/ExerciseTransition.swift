//
//  ExerciseTransition.swift
//  LearnWords
//
//  Shared animation vocabulary for the exercise screens (Test, Dictation, Phonetics) —
//  the TD-16 DRY extraction. One advance cycle replaces the six copy-pasted
//  UIViewPropertyAnimator blocks; KaPow effects give answer feedback.
//
//  Division of labor (see KaPow's Design doc, "Coexistence with UIKit's animation
//  system"): predetermined one-shot curves like these belong to UIViewPropertyAnimator
//  and animate the *container*; KaPow's live physics effects fire on *child* views.
//  Never point both at the same property of the same view.
//

import UIKit
import KaPow

enum ExerciseTransition {

    /// Springs the exercise container in from its hidden state (alpha 0, scale 0.8 — set
    /// in each screen's `viewDidLoad`). The screens call this at the end of `askQuestion`,
    /// so it is both the entry animation and the second half of the advance cycle.
    static func show(_ container: UIView) {
        let springIn = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.5) { [weak container] in
            container?.alpha = 1
            container?.transform = .identity
        }
        springIn.startAnimation()
    }

    /// The question-advance cycle: shrink-fade the exercise container out, then run
    /// `refresh` (swap in the next question's content — which ends in `show(_:)`).
    ///
    /// Lifetime-safe by construction — this was the TD-16 crash: the delayed start (up to
    /// 2 s) can outlive the screen. The container is held weakly and `refresh` is skipped
    /// unless the container is still in a window; callers still use `[weak self]` inside
    /// `refresh` and must not rely on it running.
    static func advance(_ container: UIView,
                        afterDelay delay: TimeInterval,
                        refresh: @escaping () -> Void) {
        let fadeOut = UIViewPropertyAnimator(duration: 0.5, curve: .easeInOut) { [weak container] in
            container?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            container?.alpha = 0
        }
        fadeOut.addCompletion { [weak container] _ in
            guard let container, container.window != nil else { return }
            refresh()
        }
        fadeOut.startAnimation(afterDelay: delay)
    }
}

enum ExerciseFeedback {

    /// Celebration when a word first reaches the known level.
    static func levelUp(on view: UIView) {
        guard !levelUpSprayImages.isEmpty else { return }
        view.kapow.spray(images: levelUpSprayImages)
    }

    private static let levelUpSprayImages: [UIImage] = {
        let config = UIImage.SymbolConfiguration(textStyle: .title2)
        return ["star.fill", "sparkles"].compactMap {
            UIImage(systemName: $0, withConfiguration: config)?
                .withTintColor(.orange, renderingMode: .alwaysOriginal)
        }
    }()
}
