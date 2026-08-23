//
//  MediaKeyMonitor.swift
//  DynamicIsland
//
//  Intercepts the hardware volume and brightness keys so the island can replace
//  the system HUD instead of appearing next to it.
//
//  Why an event tap is the only way: macOS draws the volume/brightness HUD from
//  `OSDUIHelper`, a system agent with no public switch and no supported way to
//  ask it to stay quiet. The HUD is a *consequence* of the key event reaching
//  the window server, so the only way to stop it is to take the event first and
//  not pass it on. `CGEvent.tapCreate` at `.cghidEventTap` / `.headInsertEventTap`
//  sits ahead of that delivery; returning nil from the callback swallows the
//  key, the system HUD never fires, and we apply the level change ourselves.
//
//  The cost is real and stated plainly rather than hidden: an event tap needs
//  **Accessibility** permission, so this module is off by default, exactly like
//  notification mirroring. Without permission `start()` fails loudly (via
//  `onTrustChange`) rather than leaving a switch that lies.
//
//  Safety rule that shapes the whole design: a swallowed key that we then fail
//  to act on means the user has *no* volume control. So the callback only
//  returns nil when the handler says it actually handled the key — anything we
//  don't understand, or can't apply, is passed straight through to the system.
//  Keyboard-backlight keys are deliberately in that "pass through" set: we have
//  no way to drive the backlight, so intercepting them would break them.
//

import AppKit

/// A hardware key we are willing to take over.
enum MediaKey: Equatable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
}

final class MediaKeyMonitor {

    /// Called on the main queue for each intercepted key. Return true when the
    /// key was applied — only then is it withheld from the system.
    ///
    /// The `precise` flag mirrors macOS's own Shift+Option modifier, which moves
    /// in quarter steps.
    var onKey: ((MediaKey, _ precise: Bool) -> Bool)?

    /// Called on the main queue when Accessibility trust changes.
    var onTrustChange: ((Bool) -> Void)?

    /// Whether the process is currently allowed to install an event tap.
    var isTrusted: Bool { AXIsProcessTrusted() }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustTimer: Timer?
    private var lastTrusted: Bool?

    /// Key codes whose key-*down* we swallowed, so the matching key-*up* can be
    /// swallowed too. Withholding a release for a press the system did see
    /// leaves it holding a key down forever; passing on a release for a press it
    /// never saw makes it show the HUD we just suppressed. Only a matched pair
    /// is correct, so the pairing is tracked rather than assumed.
    private var swallowedKeyDowns: Set<Int32> = []

    /// NX key types, from IOKit's `ev_keymap.h`. Not exposed to Swift, and
    /// stable since forever — the HID usage table these come from is frozen.
    private enum NXKey {
        static let soundUp: Int32 = 0
        static let soundDown: Int32 = 1
        static let brightnessUp: Int32 = 2
        static let brightnessDown: Int32 = 3
        static let mute: Int32 = 7
    }

    /// `NSEvent.subtype` for the aux-control buttons that carry media keys.
    private static let auxControlSubtype: Int16 = 8

    /// Accessibility can be granted while we run, and there is no notification
    /// for it, so the state is polled at a rate that costs nothing.
    private static let trustPollInterval: TimeInterval = 2.0

    // MARK: Lifecycle

    func start() {
        publishTrust()
        startTrustPolling()

        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: context
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        trustTimer?.invalidate()
        trustTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        lastTrusted = nil
        swallowedKeyDowns.removeAll()
    }

    deinit {
        stop()
    }

    /// Raise the system's Accessibility prompt. Same call the notification
    /// mirror uses — macOS shows one prompt for the process, not per feature.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long or when the user
        // toggles permission. Re-arming is the documented recovery.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let passThrough = Unmanaged.passUnretained(event)

        // `CGEventType` has no case for system-defined events — it only models
        // the mouse/keyboard set — so the raw value is the only way to name it.
        guard type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlSubtype
        else { return passThrough }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let keyIsDown = ((data & 0xFF00) >> 8) == 0x0A

        guard let key = Self.mediaKey(for: keyCode) else { return passThrough }

        // A release belongs to whoever took the press.
        guard keyIsDown else {
            return swallowedKeyDowns.remove(keyCode) != nil ? nil : passThrough
        }

        // macOS's own fine-adjustment modifier.
        let precise = nsEvent.modifierFlags.contains(.shift)
            && nsEvent.modifierFlags.contains(.option)

        // The tap callback runs on the main run loop, so the handler can touch
        // the model directly — but it must be quick, or the tap gets disabled.
        guard onKey?(key, precise) ?? false else {
            swallowedKeyDowns.remove(keyCode)
            return passThrough
        }
        swallowedKeyDowns.insert(keyCode)
        return nil
    }

    private static func mediaKey(for code: Int32) -> MediaKey? {
        switch code {
        case NXKey.soundUp:         return .volumeUp
        case NXKey.soundDown:       return .volumeDown
        case NXKey.mute:            return .mute
        case NXKey.brightnessUp:    return .brightnessUp
        case NXKey.brightnessDown:  return .brightnessDown
        default:                    return nil
        }
    }

    // MARK: Trust

    private func startTrustPolling() {
        guard trustTimer == nil else { return }

        let timer = Timer(timeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.publishTrust()
            // Permission granted while we were running: install the tap now,
            // so the user doesn't have to toggle the switch to see it work.
            if AXIsProcessTrusted(), self.eventTap == nil { self.start() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    private func publishTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != lastTrusted else { return }
        lastTrusted = trusted
        onTrustChange?(trusted)
    }
}
