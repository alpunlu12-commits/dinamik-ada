//
//  PrivacyMonitor.swift
//  DynamicIsland
//
//  Reports whether anything on the system is using the camera or the microphone.
//
//  Both answers come from asking the hardware whether it is *running somewhere* —
//  CoreAudio for input devices, CoreMediaIO for cameras. Neither opens a stream,
//  so neither trips the camera or microphone permission prompts: the app never
//  gains access to what is being captured, only to the fact that something is
//  capturing.
//
//  This is deliberately additive. macOS draws its own privacy indicator in the
//  menu bar and that remains the authority; the island only mirrors it.
//

import AppKit
import CoreAudio
import CoreMediaIO

final class PrivacyMonitor {

    /// Called on the main queue when the camera or microphone state changes.
    var onChange: ((PrivacyState) -> Void)?

    private(set) var state: PrivacyState = .idle

    private var timer: Timer?

    /// Devices start and stop often enough that a listener per device would mean
    /// re-registering constantly; a cheap poll is simpler and steadier.
    private static let sampleInterval: TimeInterval = 1.0

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }

        sample()
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if state.isActive {
            state = .idle
            onChange?(state)
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Sampling

    private func sample() {
        let fresh = PrivacyState(cameraActive: isAnyCameraRunning(),
                                 microphoneActive: isAnyMicrophoneRunning())
        guard fresh != state else { return }
        state = fresh
        onChange?(fresh)
    }

    // MARK: Microphone (CoreAudio)

    private func isAnyMicrophoneRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0
        else { return false }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &devices) == noErr
        else { return false }

        for device in devices where hasInputStreams(device) {
            if isRunningSomewhere(device) { return true }
        }
        return false
    }

    private func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }

        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    // MARK: Camera (CoreMediaIO)

    private func isAnyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &address, 0, nil, &size) == noErr, size > 0
        else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                        &address, 0, nil, size, &used, &devices) == noErr
        else { return false }

        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        for device in devices {
            var isRunning: UInt32 = 0
            let valueSize = UInt32(MemoryLayout<UInt32>.size)
            var valueUsed: UInt32 = 0
            guard CMIOObjectGetPropertyData(device, &running, 0, nil, valueSize,
                                            &valueUsed, &isRunning) == noErr else { continue }
            if isRunning != 0 { return true }
        }
        return false
    }
}
