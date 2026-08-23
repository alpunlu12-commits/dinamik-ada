//
//  IslandTimer.swift
//  DynamicIsland
//
//  The countdown behind the island's timer.
//
//  Remaining time is derived from a deadline rather than decremented on each
//  tick: a repeating timer drifts, and it stops firing at its normal rate while
//  the machine is asleep or the run loop is busy. Reading the clock instead
//  means the countdown is correct whenever anyone looks at it, however coarse
//  the ticks turn out to be.
//

import Foundation

final class IslandTimer {

    /// Called on the main queue whenever the displayed value should change, and
    /// with nil when the countdown is cleared.
    var onChange: ((CountdownState?) -> Void)?

    /// Called on the main queue the moment the countdown reaches zero.
    var onFinished: ((TimeInterval) -> Void)?

    private(set) var state: CountdownState? {
        didSet { if state != oldValue { onChange?(state) } }
    }

    private var deadline: Date?
    private var ticker: Timer?

    /// Fast enough that the seconds never look like they stutter.
    private static let tickInterval: TimeInterval = 0.2

    // MARK: Commands

    func start(minutes: Int) {
        let duration = TimeInterval(minutes * 60)
        deadline = Date().addingTimeInterval(duration)
        state = CountdownState(duration: duration, remaining: duration, isRunning: true)
        startTicking()
    }

    /// Pause a running countdown, or resume a paused one.
    func toggle() {
        guard var current = state else { return }

        if current.isRunning {
            current.remaining = remainingFromDeadline() ?? current.remaining
            current.isRunning = false
            deadline = nil
            stopTicking()
        } else {
            deadline = Date().addingTimeInterval(current.remaining)
            current.isRunning = true
            startTicking()
        }
        state = current
    }

    func restart() {
        guard let current = state else { return }
        start(minutes: Int((current.duration / 60).rounded()))
    }

    func cancel() {
        stopTicking()
        deadline = nil
        state = nil
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        let ticker = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard var current = state, current.isRunning,
              let remaining = remainingFromDeadline() else { return }

        if remaining <= 0 {
            stopTicking()
            deadline = nil
            current.remaining = 0
            current.isRunning = false
            state = current
            onFinished?(current.duration)
            return
        }

        current.remaining = remaining
        state = current
    }

    private func remainingFromDeadline() -> TimeInterval? {
        deadline.map { max(0, $0.timeIntervalSinceNow) }
    }
}
