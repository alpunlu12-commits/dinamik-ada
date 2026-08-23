//
//  BluetoothMonitor.swift
//  DynamicIsland
//
//  Battery levels for connected Bluetooth audio devices — AirPods report each
//  bud and the case separately, most other headsets report a single figure.
//
//  Two decisions worth explaining:
//
//  **Where the levels come from.** The usual trick is to read `BatteryPercent…`
//  out of the IO registry, and on this machine those keys simply do not exist
//  for any device — an implementation built on them looks like it works and
//  silently never fires. `system_profiler SPBluetoothDataType` is the same
//  source the system's own Bluetooth menu uses, it reports the levels reliably,
//  and being a subprocess it needs no Bluetooth permission of our own.
//
//  **What triggers a read.** system_profiler takes a second or two, so it is
//  never polled at any speed worth calling a poll. AirPods announce themselves
//  in a much cheaper way: connecting adds an audio output device, and CoreAudio
//  will tell us the device list changed. That notification is the trigger; the
//  slow refresh behind it only keeps the percentages from going stale.
//

import Foundation
import CoreAudio

final class BluetoothMonitor {

    /// Called on the main queue when the connected devices or their levels change.
    var onChange: (([BluetoothDevice]) -> Void)?

    /// Called on the main queue when a device arrives, which is the moment worth
    /// showing on the island.
    var onConnect: ((BluetoothDevice) -> Void)?

    private(set) var devices: [BluetoothDevice] = []

    private let queue = DispatchQueue(label: "com.abacusisland.dynamicisland.bluetooth")
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var refreshTimer: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var hasReadOnce = false

    /// Levels drift slowly and the read is expensive.
    private static let refreshInterval: TimeInterval = 300

    /// A device takes a moment to finish presenting itself after the audio
    /// device list changes; asking too early reports it without battery.
    private static let settleDelay: TimeInterval = 2.0

    private static var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // MARK: Lifecycle

    func start() {
        guard deviceListListener == nil else { return }

        var address = Self.deviceListAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRefresh(announce: true)
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, block) == noErr {
            deviceListListener = block
        }

        scheduleRefresh(announce: false)

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.scheduleRefresh(announce: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil

        if let deviceListListener {
            var address = Self.deviceListAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                   &address, DispatchQueue.main, deviceListListener)
        }
        deviceListListener = nil

        if !devices.isEmpty {
            devices = []
            onChange?(devices)
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: Reading

    /// Coalesce the burst of device-list notifications a connection produces
    /// into a single read, once the dust has settled.
    private func scheduleRefresh(announce: Bool) {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(announce: announce) }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (announce ? Self.settleDelay : 0),
                                      execute: work)
    }

    private func refresh(announce: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let fresh = Self.read()

            DispatchQueue.main.async {
                let previous = self.devices
                let firstRead = !self.hasReadOnce
                self.hasReadOnce = true

                guard fresh != previous else { return }
                self.devices = fresh
                self.onChange?(fresh)

                // Announce genuine arrivals only — not a level ticking down, and
                // not the devices that were already connected at launch.
                guard announce, !firstRead else { return }
                let previousNames = Set(previous.map(\.name))
                if let arrived = fresh.first(where: { !previousNames.contains($0.name) }) {
                    self.onConnect?(arrived)
                }
            }
        }
    }

    private static func read() -> [BluetoothDevice] {
        guard let data = runSystemProfiler(),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return [] }

        var found: [BluetoothDevice] = []
        collectConnected(root, into: &found)
        return found
    }

    private static func runSystemProfiler() -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return data.isEmpty ? nil : data
    }

    /// The report nests the connected list somewhere inside; walk to it rather
    /// than hard-coding a path that a future macOS could rename around us.
    private static func collectConnected(_ node: Any, into found: inout [BluetoothDevice]) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if key == "device_connected", let entries = value as? [[String: Any]] {
                    for entry in entries {
                        for (name, properties) in entry {
                            guard let properties = properties as? [String: Any],
                                  let device = device(named: name, from: properties)
                            else { continue }
                            found.append(device)
                        }
                    }
                } else {
                    collectConnected(value, into: &found)
                }
            }
        } else if let array = node as? [Any] {
            for value in array { collectConnected(value, into: &found) }
        }
    }

    private static func device(named name: String, from properties: [String: Any]) -> BluetoothDevice? {
        let device = BluetoothDevice(
            name: name,
            left: percentage(properties["device_batteryLevelLeft"]),
            right: percentage(properties["device_batteryLevelRight"]),
            case_: percentage(properties["device_batteryLevelCase"]),
            single: percentage(properties["device_batteryLevelMain"])
                ?? percentage(properties["device_batteryLevel"])
        )
        // A device that reports nothing is not worth a row on the island.
        return device.hasBattery ? device : nil
    }

    /// The report writes percentages as text, and puts the sign on whichever
    /// side the user's locale calls for — "99%" here, "%99" in Turkish.
    private static func percentage(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        let digits = text.filter(\.isNumber)
        guard let number = Int(digits), (1...100).contains(number) else { return nil }
        return number
    }
}
