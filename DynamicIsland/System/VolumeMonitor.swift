//
//  VolumeMonitor.swift
//  DynamicIsland
//
//  Reports output-volume and mute changes via CoreAudio property listeners —
//  public API, no permissions, and event-driven rather than polled.
//
//  Two wrinkles worth knowing about:
//    • Not every device publishes a "main" volume element. Aggregate and some
//      USB devices only expose per-channel volume, so channel 1 is used as a
//      fallback for both reading and listening.
//    • The default output device can change under us (headphones plugged in,
//      AirPlay picked), so the system object is watched too and the listeners
//      are moved to the new device.
//

import CoreAudio
import Foundation

final class VolumeMonitor {

    /// Called on the main queue with the new level (0…1) and mute state.
    var onChange: ((Double, Bool) -> Void)?

    /// When true, a level that lands off the 5% grid is nudged onto it.
    var snapsToFivePercent = true

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemListener: (AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)?

    private var lastLevel: Double?
    private var lastMuted: Bool?

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // MARK: Lifecycle

    func start() {
        guard systemListener == nil else { return }

        var address = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
        if AudioObjectAddPropertyListenerBlock(Self.system, &address, DispatchQueue.main, block) == noErr {
            systemListener = (address, block)
        }

        attachToDefaultDevice()
    }

    func stop() {
        detachFromDevice()

        if let listener = systemListener {
            var address = listener.0
            AudioObjectRemovePropertyListenerBlock(Self.system, &address, DispatchQueue.main, listener.1)
            systemListener = nil
        }

        lastLevel = nil
        lastMuted = nil
    }

    deinit {
        stop()
    }

    // MARK: Device wiring

    private func attachToDefaultDevice() {
        detachFromDevice()

        device = defaultOutputDevice()
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }

        // Element main covers most devices; 1 and 2 catch the per-channel ones.
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            addListener(selector: kAudioDevicePropertyVolumeScalar, element: element)
        }
        addListener(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)

        // Prime the cache so switching devices doesn't flash the island.
        lastLevel = readVolume()
        lastMuted = readMute()
    }

    private func detachFromDevice() {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
        deviceListeners.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func addListener(selector: AudioObjectPropertySelector,
                             element: AudioObjectPropertyElement) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emit()
        }
        if AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
            deviceListeners.append((address, block))
        }
    }

    // MARK: Writing

    /// Set the output level. Devices that expose a main volume element take it
    /// there; the rest are driven per channel.
    func setLevel(_ level: Double, snapping: Bool? = nil) {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        let snap = snapping ?? snapsToFivePercent
        var value = Float32(snap ? level.snappedToFivePercent : level.clampedToUnit)

        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }

            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }

            AudioObjectSetPropertyData(device, &address, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &value)

            // The main element covers every channel; stop before double-setting.
            if element == kAudioObjectPropertyElementMain { break }
        }

        // Dragging the slider up is an unambiguous "I want to hear this".
        if level > 0, readMute() { setMuted(false) }
    }

    /// Whether the default output is muted right now.
    var isMuted: Bool {
        device == AudioObjectID(kAudioObjectUnknown) ? false : readMute()
    }

    /// Flip mute. Needed by the media-key monitor, which swallows the mute key
    /// and therefore has to do the system's job for it.
    func toggleMute() {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        setMuted(!readMute())
        emit()
    }

    /// Move the level by one step, the way the hardware keys do.
    ///
    /// Returns false when there is no device to drive, so a swallowed key can be
    /// handed back to the system instead of vanishing.
    @discardableResult
    func step(up: Bool, precise: Bool) -> Bool {
        guard device != AudioObjectID(kAudioObjectUnknown),
              let current = readVolume() else { return false }

        // macOS moves in sixteenths; the 5% grid setting is the whole reason
        // this app has a snap preference, so honour it here too — except under
        // the fine-adjustment modifier, where snapping back to the grid would
        // swallow the very step the user asked for.
        var step = snapsToFivePercent ? 0.05 : 1.0 / 16.0
        if precise { step /= 4 }

        // Stepping up from a muted device should be audible, which is what the
        // system does too.
        if up, readMute() { setMuted(false) }

        let target = (current + (up ? step : -step)).clampedToUnit
        setLevel(target, snapping: precise ? false : nil)
        emit()
        return true
    }

    private func setMuted(_ muted: Bool) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return }

        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return }

        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// The level right now, for seeding the UI at launch: the listeners only
    /// fire on a *change*, so without this the island shows no volume at all
    /// until the user happens to press a volume key.
    func currentLevel() -> Double? {
        device == AudioObjectID(kAudioObjectUnknown) ? nil : readVolume()
    }

    // MARK: Reading

    private func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultOutputAddress
        AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &id)
        return id
    }

    private func readVolume() -> Double? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }

            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return Double(min(max(value, 0), 1))
            }
        }
        return nil
    }

    private func readMute() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func emit() {
        guard let level = readVolume() else { return }
        let muted = readMute()

        // Several listeners fire for one keypress; only surface real changes.
        let levelChanged = abs((lastLevel ?? -1) - level) > 0.0005
        let muteChanged = muted != lastMuted
        guard levelChanged || muteChanged else { return }

        let previous = lastLevel
        lastLevel = level
        lastMuted = muted
        onChange?(level, muted)

        // Nudge onto the grid only for a real step. An app fading its audio
        // moves in tiny increments, and snapping those would fight it.
        guard snapsToFivePercent, !level.isOnFivePercentGrid,
              abs((previous ?? level) - level) >= .discreteStepThreshold else { return }
        setLevel(level.snappedToFivePercent)
    }
}
