//
//  BrightnessMonitor.swift
//  DynamicIsland
//
//  Reports built-in display brightness changes.
//
//  ⚠️ This is the one module that leaves public API. macOS exposes no supported
//  way to read the built-in display's brightness level: the IOKit route
//  (`IODisplayGetFloatParameter`) returns nothing on Apple Silicon, and there is
//  no AppKit equivalent. DisplayServices is the private framework the system's
//  own brightness HUD uses.
//
//  Consequences, and why this is still the right call here:
//    • It is loaded with dlopen/dlsym rather than linked, so a missing or
//      renamed symbol on a future macOS degrades to `isAvailable == false` and
//      the module simply goes quiet — it cannot crash the app.
//    • It rules out the Mac App Store, which this app already rules out by
//      shipping unsandboxed (see README → İzinler ve yetkiler).
//
//  There is also no change notification to subscribe to, so this polls. The
//  read is a cheap C call; at 4 Hz it does not register in Activity Monitor.
//

import AppKit

final class BrightnessMonitor {

    /// Called on the main queue with the new level (0…1) and whether the change
    /// looks user-initiated — only those deserve to take the island over.
    var onChange: ((Double, Bool) -> Void)?

    /// When true, a level that lands off the 5% grid is nudged onto it.
    var snapsToFivePercent = true

    /// False when the private symbol could not be resolved. The module is then
    /// simply inactive; nothing else in the app needs to care.
    var isAvailable: Bool { getBrightness != nil }

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var getBrightness: GetBrightness?
    private var setBrightness: SetBrightness?
    private var notifyBrightnessChanged: SetBrightness?
    private var timer: Timer?
    private var last: Double?

    private static let sampleInterval: TimeInterval = 0.25

    /// Ambient-light adjustment moves brightness continuously, a fraction of a
    /// percent at a time; a brightness key moves it a notch (1/16 ≈ 6%) at once.
    /// Anything below this is drift, and drift must never open the island —
    /// macOS doesn't show its own HUD for auto-brightness either.
    private static let userStepThreshold: Double = 0.015

    /// Below this the hardware is just reporting noise.
    private static let noiseFloor: Double = 0.001

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                        RTLD_LAZY)
        if let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        }
        if let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightness = unsafeBitCast(symbol, to: SetBrightness.self)
        }
        // Tells the system the level moved, so it persists the value and its own
        // UI agrees with ours. Optional: absence just means a less tidy result.
        if let handle, let symbol = dlsym(handle, "DisplayServicesBrightnessChanged") {
            notifyBrightnessChanged = unsafeBitCast(symbol, to: SetBrightness.self)
        }
    }

    deinit {
        stop()
    }

    // MARK: Lifecycle

    func start() {
        guard isAvailable, timer == nil else { return }

        last = read()

        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = nil
    }

    /// Current level, or nil when unavailable. Used by the control center.
    func currentLevel() -> Double? {
        read()
    }

    /// True when brightness can be driven, not just read.
    var isAdjustable: Bool { setBrightness != nil }

    /// Move the level by one step, the way the hardware keys do.
    ///
    /// Returns false when brightness can't be driven, so a swallowed key can be
    /// handed back to the system rather than doing nothing at all.
    @discardableResult
    func step(up: Bool, precise: Bool) -> Bool {
        guard isAdjustable, let current = read() else { return false }

        // The fine-adjustment modifier bypasses the 5% grid, or snapping would
        // undo the quarter-step the user just asked for.
        var step = snapsToFivePercent ? 0.05 : 1.0 / 16.0
        if precise { step /= 4 }

        let snap = snapsToFivePercent && !precise
        let target = (current + (up ? step : -step)).clampedToUnit
        setLevel(target, snapping: snap)
        // setLevel owns `last`, so the poll won't replay this as a fresh change;
        // the island is told about it directly instead.
        onChange?(snap ? target.snappedToFivePercent : target, true)
        return true
    }

    /// Set the built-in display's brightness.
    func setLevel(_ level: Double, snapping: Bool? = nil) {
        guard let setBrightness, let display = builtInDisplay() else { return }
        let snap = snapping ?? snapsToFivePercent
        let clamped = snap ? level.snappedToFivePercent : level.clampedToUnit
        _ = setBrightness(display, Float(clamped))
        _ = notifyBrightnessChanged?(display, Float(clamped))
        // Own the new value so the next poll doesn't read it back as a jump and
        // fire a HUD for a change the user just made by hand.
        last = clamped
    }

    // MARK: Reading

    private func sample() {
        guard let level = read() else { return }
        guard let previous = last else { last = level; return }

        let delta = abs(previous - level)
        guard delta > Self.noiseFloor else { return }

        last = level
        // Drift still updates the reading the control center shows; it just
        // doesn't interrupt anyone.
        let userInitiated = delta >= Self.userStepThreshold
        onChange?(level, userInitiated)

        // Only a deliberate step gets pulled onto the 5% grid; ambient drift is
        // left alone, or the display would twitch all day.
        guard snapsToFivePercent, userInitiated, !level.isOnFivePercentGrid,
              delta >= .discreteStepThreshold else { return }
        setLevel(level.snappedToFivePercent)
    }

    private func read() -> Double? {
        guard let getBrightness, let display = builtInDisplay() else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return Double(min(max(value, 0), 1))
    }

    private func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }

        return displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? displays.first
    }
}
