//
//  ExerciseTransitionTests.swift
//  Unit Testing Bundle
//
//  The TD-16 crash class: the advance cycle's delayed start can outlive the screen.
//  Proves the shared animator's refresh is skipped once the container leaves its window.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct ExerciseTransitionTests {

    private func makeWindowedContainer() -> (UIWindow, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        return (window, container)
    }

    @Test func refreshRunsWhileContainerStaysOnScreen() async throws {
        let (window, container) = makeWindowedContainer()
        defer { window.isHidden = true }

        var refreshed = false
        ExerciseTransition.advance(container, afterDelay: 0.02) { refreshed = true }

        try await Task.sleep(nanoseconds: 1_200_000_000)  // delay + 0.5 s fade + margin
        #expect(refreshed)
        #expect(container.alpha == 1)  // spring-in restored the container
    }

    @Test func refreshSkippedWhenScreenIsLeftDuringDelay() async throws {
        let (window, container) = makeWindowedContainer()
        defer { window.isHidden = true }

        var refreshed = false
        ExerciseTransition.advance(container, afterDelay: 0.3) { refreshed = true }
        container.removeFromSuperview()  // "leave the screen" during the delayed start

        try await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(!refreshed, "refresh must not run once the container left its window (TD-16 crash class)")
    }
}
