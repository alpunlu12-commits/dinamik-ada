//
//  FullscreenDetector.swift
//  DynamicIsland
//
//  Tells the island when a full-screen app owns the display it lives on, so it
//  can get out of the way of a film.
//
//  The panel is `.fullScreenAuxiliary`, which is what lets it float over
//  full-screen apps in the first place — exactly the behaviour you want for a
//  volume HUD and exactly the behaviour you don't want across the top of a
//  video. Hiding is therefore a policy decision made here, not a window flag.
//
//  How detection works, and why this way: a full-screen window is an ordinary
//  window at layer 0 whose bounds cover the *entire* display, menu-bar strip
//  included. `CGWindowListCopyWindowInfo` reports bounds, layer and owning PID
//  for on-screen windows **without any permission** — only window titles and
//  pixel contents are gated behind Screen Recording, and neither is read here.
//
//  Rather than polling hard, this listens to the two events that can change the
//  answer — a Space switch (a full-screen app is its own Space) and an app
//  activation — and keeps a slow safety poll for the cases that produce neither,
//  such as a video going full-screen inside an already-frontmost window.
//

import AppKit

final class FullscreenDetector {

    /// Called on the main queue when the answer changes.
    var onChange: ((Bool) -> Void)?

    /// Which display to watch. Set by the controller from the island's screen.
    var screen: NSScreen? {
        didSet { evaluate() }
    }

    private(set) var isFullscreen = false

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    /// Read once: `ProcessInfo.processInfo` is not free and this is compared
    /// against every window on screen.
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Slow on purpose: the Space-change and activation notifications catch
    /// almost everything, and this only exists for the transitions that post
    /// neither — a video going full screen inside an already-frontmost window.
    /// Two seconds of lag on that case is not worth a faster poll.
    private static let pollInterval: TimeInterval = 2.0

    /// A full-screen window is allowed to miss the display bounds by a hair —
    /// some apps inset themselves by a point on a notched Mac.
    private static let tolerance: CGFloat = 2.0

    // MARK: Lifecycle

    func start() {
        guard observers.isEmpty else { return }

        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.evaluate()
            }
            observers.append(observer)
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        evaluate()
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach { workspace.removeObserver($0) }
        observers.removeAll()

        timer?.invalidate()
        timer = nil

        setFullscreen(false)
    }

    deinit {
        stop()
    }

    // MARK: Detection

    private func evaluate() {
        setFullscreen(detect())
    }

    private func setFullscreen(_ value: Bool) {
        guard value != isFullscreen else { return }
        isFullscreen = value
        onChange?(value)
    }

    private func detect() -> Bool {
        guard let screen = screen ?? NSScreen.main else { return false }

        // CGWindowList works in a flipped global space whose origin is the
        // top-left of the *primary* display; NSScreen is bottom-left. Convert
        // the screen's frame once and compare in CG's terms.
        guard let primary = NSScreen.screens.first else { return false }
        let frame = screen.frame
        let target = CGRect(x: frame.minX,
                            y: primary.frame.maxY - frame.maxY,
                            width: frame.width,
                            height: frame.height)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray?
        else { return false }

        // Deliberately NSArray/NSDictionary rather than `as? [[String: Any]]`.
        // That cast deep-bridges *every* key and value of *every* on-screen
        // window into Swift natives on each pass — on a busy desktop that is
        // thousands of allocations a second for the four keys actually read
        // here. Going through the Objective-C types keeps the access lazy.
        for case let window as NSDictionary in windows {
            // Layer 0 is a normal application window. The menu bar, the Dock and
            // our own panel all live above it, and would otherwise match.
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }

            // Our own window can never be the thing we're hiding from.
            if let pid = window[kCGWindowOwnerPID as String] as? pid_t,
               pid == ownPID { continue }

            guard let boundsDict = window[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { continue }

            if abs(bounds.minX - target.minX) <= Self.tolerance,
               abs(bounds.minY - target.minY) <= Self.tolerance,
               abs(bounds.width - target.width) <= Self.tolerance,
               abs(bounds.height - target.height) <= Self.tolerance {
                return true
            }
        }
        return false
    }
}
