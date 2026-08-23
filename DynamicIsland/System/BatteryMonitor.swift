//
//  BatteryMonitor.swift
//  DynamicIsland
//
//  Watches the power source through IOKit — public API, no permissions, and
//  push-based: IOKit hands us a run-loop source that fires whenever anything
//  about the power source changes.
//
//  The island only *flashes* for a handful of moments worth interrupting for:
//  plugging in, unplugging, reaching full, and crossing a low-battery threshold.
//  Plain percentage drift is kept in `snapshot` for the control center to read
//  without bothering anyone.
//
//  Each low-battery threshold announces itself once per discharge. Without that
//  bookkeeping the island would re-announce 20% every time IOKit posts a fresh
//  reading — the level hovers around a threshold for minutes — which is exactly
//  the behaviour that makes people turn a feature off. Plugging in resets the
//  set, so the next discharge warns again.
//

import Foundation
import IOKit.ps

final class BatteryMonitor {

    /// Latest reading, refreshed on every IOKit notification.
    private(set) var snapshot: PowerSnapshot?

    /// Called on the main queue for a power moment worth showing.
    var onPowerEvent: ((PowerSnapshot, PowerEvent) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    /// Thresholds already announced during this discharge.
    private var announcedThresholds: Set<Int> = []

    /// Descending, so the lowest crossed threshold is the one that speaks.
    private static let lowBatteryThresholds = [20, 10, 5]

    // MARK: Lifecycle

    func start() {
        guard runLoopSource == nil else { return }

        snapshot = read()

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        announcedThresholds.removeAll()
    }

    deinit {
        stop()
    }

    // MARK: Reading

    private func refresh() {
        guard let fresh = read() else { return }
        let previous = snapshot
        snapshot = fresh
        guard let previous else { return }

        if previous.isPluggedIn != fresh.isPluggedIn {
            // A fresh discharge gets its warnings back.
            if !fresh.isPluggedIn { announcedThresholds.removeAll() }
            onPowerEvent?(fresh, fresh.isPluggedIn ? .pluggedIn : .unplugged)
            return
        }

        // "Charged" is the moment charging stops with the pack full — not
        // merely reading 100%, which happens for a while before it finishes.
        if fresh.isPluggedIn, fresh.percentage >= 100,
           previous.isCharging, !fresh.isCharging {
            onPowerEvent?(fresh, .fullyCharged)
            return
        }

        guard !fresh.isPluggedIn else { return }

        // The most urgent threshold the level has reached, not the first one it
        // happened to cross: a drop from 25% straight to 3% should say 5%, not
        // walk back up through 20% and 10% on later readings. Everything above
        // the one that fires is marked spoken-for, so it can't warn later.
        guard let crossed = Self.lowBatteryThresholds
            .filter({ fresh.percentage <= $0 })
            .min(),
            !announcedThresholds.contains(crossed)
        else { return }

        for threshold in Self.lowBatteryThresholds where threshold >= crossed {
            announcedThresholds.insert(threshold)
        }
        onPowerEvent?(fresh, .lowBattery(threshold: crossed))
    }

    private func read() -> PowerSnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as NSArray?
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source as CFTypeRef)?
                    .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // IOKit reports -1 while it is still working the estimate out.
            var minutesRemaining: Int?
            if isCharging, let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                minutesRemaining = minutes
            } else if !isPluggedIn, let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                minutesRemaining = minutes
            }

            return PowerSnapshot(
                percentage: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesRemaining: minutesRemaining
            )
        }
        return nil
    }
}
