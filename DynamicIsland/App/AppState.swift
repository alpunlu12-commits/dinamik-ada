//
//  AppState.swift
//  DynamicIsland
//
//  Persisted, observable user settings. Values are stored in UserDefaults and
//  republished to SwiftUI via @Published so both the Settings window and the
//  live island react instantly.
//
//  Module switches only cover modules that actually exist — a toggle for a
//  feature that isn't wired up yet is worse than no toggle. Later phases add
//  theirs alongside.
//
//  "Launch at login" is the exception to the UserDefaults rule: the system
//  owns that state through SMAppService, so it is read back from there rather
//  than mirrored, and a failed registration falls back to the real value.
//

import SwiftUI
import Combine
import ServiceManagement

/// Physical footprint of the island. Phase 1 keeps this coarse (small/medium);
/// later phases may add "large".
enum IslandSize: String, CaseIterable, Identifiable {
    case small
    case medium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:  return Strings.small
        case .medium: return Strings.medium
        }
    }
}

/// Spring speed for the expand/collapse animations.
enum AnimationSpeed: String, CaseIterable, Identifiable {
    case slow
    case normal
    case fast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slow:   return Strings.slow
        case .normal: return Strings.normal
        case .fast:   return Strings.fast
        }
    }
}

final class AppState: ObservableObject {

    // MARK: Appearance

    /// Interface language. Kept in step with the static every string reads.
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            Localization.language = language
        }
    }

    /// Which display the island lives on.
    @Published var preferredDisplay: DisplayPreference {
        didSet { defaults.set(preferredDisplay.storageValue, forKey: Keys.preferredDisplay) }
    }

    /// Overall island footprint.
    @Published var islandSize: IslandSize {
        didSet { defaults.set(islandSize.rawValue, forKey: Keys.islandSize) }
    }

    /// Spring animation speed.
    @Published var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: Keys.animationSpeed) }
    }

    /// Seconds to wait before auto-collapsing the expanded / control-center
    /// state once the pointer has left the island.
    @Published var autoCollapseDelay: Double {
        didSet { defaults.set(autoCollapseDelay, forKey: Keys.autoCollapseDelay) }
    }

    // MARK: Modules

    @Published var musicEnabled: Bool {
        didSet { defaults.set(musicEnabled, forKey: Keys.musicEnabled) }
    }

    @Published var volumeEnabled: Bool {
        didSet { defaults.set(volumeEnabled, forKey: Keys.volumeEnabled) }
    }

    @Published var brightnessEnabled: Bool {
        didSet { defaults.set(brightnessEnabled, forKey: Keys.brightnessEnabled) }
    }

    @Published var batteryEnabled: Bool {
        didSet { defaults.set(batteryEnabled, forKey: Keys.batteryEnabled) }
    }

    @Published var timerEnabled: Bool {
        didSet { defaults.set(timerEnabled, forKey: Keys.timerEnabled) }
    }

    @Published var bluetoothEnabled: Bool {
        didSet { defaults.set(bluetoothEnabled, forKey: Keys.bluetoothEnabled) }
    }

    @Published var privacyEnabled: Bool {
        didSet { defaults.set(privacyEnabled, forKey: Keys.privacyEnabled) }
    }

    /// Mirroring banners needs Accessibility, so it is off until asked for.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    /// Calendar is off until asked for: it is the only module that needs the
    /// user's permission to say anything at all.
    @Published var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Keys.calendarEnabled) }
    }

    /// Live activity for the Downloads folder.
    @Published var downloadsEnabled: Bool {
        didSet { defaults.set(downloadsEnabled, forKey: Keys.downloadsEnabled) }
    }

    /// The drop zone and the file shelf.
    @Published var shelfEnabled: Bool {
        didSet { defaults.set(shelfEnabled, forKey: Keys.shelfEnabled) }
    }

    /// Take the hardware volume/brightness keys over so the island replaces the
    /// system HUD instead of appearing beside it. Needs Accessibility, so it is
    /// off until asked for — same rule as notification mirroring.
    @Published var mediaKeysEnabled: Bool {
        didSet { defaults.set(mediaKeysEnabled, forKey: Keys.mediaKeysEnabled) }
    }

    /// Keep volume and brightness on a 5% grid instead of the system's
    /// sixteenths.
    @Published var snapLevelsToFivePercent: Bool {
        didSet { defaults.set(snapLevelsToFivePercent, forKey: Keys.snapLevels) }
    }

    // MARK: Behaviour

    /// Get out of the way when a full-screen app owns the island's display.
    @Published var hideWhenFullscreen: Bool {
        didSet { defaults.set(hideWhenFullscreen, forKey: Keys.hideWhenFullscreen) }
    }

    /// Exclude the island from screenshots, recordings and shared screens.
    @Published var hideInScreenshots: Bool {
        didSet { defaults.set(hideInScreenshots, forKey: Keys.hideInScreenshots) }
    }

    /// Whether the timer is allowed to make a sound when it finishes.
    @Published var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: Keys.soundEffectsEnabled) }
    }

    // MARK: System

    /// Backed by SMAppService, not UserDefaults.
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Set when the system refused to register the login item, so the Settings
    /// window can say why instead of silently flipping the switch back.
    @Published private(set) var launchAtLoginError: String?

    private var isApplyingLaunchAtLogin = false

    // MARK: Derived

    /// The spring used for all island state transitions.
    var springAnimation: Animation {
        switch animationSpeed {
        case .slow:   return .spring(response: 0.70, dampingFraction: 0.82)
        case .normal: return .spring(response: 0.42, dampingFraction: 0.80)
        case .fast:   return .spring(response: 0.26, dampingFraction: 0.82)
        }
    }

    // MARK: Persistence

    /// Short on purpose. Two seconds felt like the island was refusing to
    /// leave; the pointer is already off it by then.
    static let defaultCollapseDelay = 0.5

    /// Bumped when a default changes in a way existing installs should follow.
    private static let settingsVersion = 1

    private let defaults: UserDefaults

    private enum Keys {
        static let islandSize        = "islandSize"
        static let preferredDisplay  = "preferredDisplay"
        static let animationSpeed    = "animationSpeed"
        static let autoCollapseDelay = "autoCollapseDelay"
        static let settingsVersion   = "settingsVersion"
        static let language          = "language"
        static let musicEnabled      = "musicEnabled"
        static let volumeEnabled     = "volumeEnabled"
        static let brightnessEnabled = "brightnessEnabled"
        static let batteryEnabled    = "batteryEnabled"
        static let timerEnabled      = "timerEnabled"
        static let bluetoothEnabled  = "bluetoothEnabled"
        static let privacyEnabled    = "privacyEnabled"
        static let shelfEnabled      = "shelfEnabled"
        static let calendarEnabled   = "calendarEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let soundEffectsEnabled = "soundEffectsEnabled"
        static let snapLevels        = "snapLevelsToFivePercent"
        static let downloadsEnabled  = "downloadsEnabled"
        static let mediaKeysEnabled  = "mediaKeysEnabled"
        static let hideWhenFullscreen = "hideWhenFullscreen"
        static let hideInScreenshots = "hideInScreenshots"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Register sensible defaults on first launch.
        defaults.register(defaults: [
            Keys.islandSize: IslandSize.medium.rawValue,
            Keys.animationSpeed: AnimationSpeed.normal.rawValue,
            Keys.autoCollapseDelay: Self.defaultCollapseDelay,
            Keys.musicEnabled: true,
            Keys.volumeEnabled: true,
            Keys.brightnessEnabled: true,
            Keys.batteryEnabled: true,
            Keys.timerEnabled: true,
            Keys.bluetoothEnabled: true,
            Keys.privacyEnabled: true,
            Keys.shelfEnabled: true,
            Keys.calendarEnabled: false,
            Keys.notificationsEnabled: false,
            Keys.soundEffectsEnabled: true,
            Keys.snapLevels: true,
            Keys.downloadsEnabled: true,
            Keys.mediaKeysEnabled: false,
            Keys.hideWhenFullscreen: true,
            Keys.hideInScreenshots: false,
        ])

        self.islandSize = IslandSize(rawValue: defaults.string(forKey: Keys.islandSize) ?? "")
            ?? .medium
        self.preferredDisplay = DisplayPreference(
            storageValue: defaults.string(forKey: Keys.preferredDisplay) ?? "automatic")
        self.animationSpeed = AnimationSpeed(rawValue: defaults.string(forKey: Keys.animationSpeed) ?? "")
            ?? .normal
        self.autoCollapseDelay = defaults.double(forKey: Keys.autoCollapseDelay)

        self.musicEnabled = defaults.bool(forKey: Keys.musicEnabled)
        self.volumeEnabled = defaults.bool(forKey: Keys.volumeEnabled)
        self.brightnessEnabled = defaults.bool(forKey: Keys.brightnessEnabled)
        self.batteryEnabled = defaults.bool(forKey: Keys.batteryEnabled)
        self.timerEnabled = defaults.bool(forKey: Keys.timerEnabled)
        self.bluetoothEnabled = defaults.bool(forKey: Keys.bluetoothEnabled)
        self.privacyEnabled = defaults.bool(forKey: Keys.privacyEnabled)
        self.shelfEnabled = defaults.bool(forKey: Keys.shelfEnabled)
        self.calendarEnabled = defaults.bool(forKey: Keys.calendarEnabled)
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        self.soundEffectsEnabled = defaults.bool(forKey: Keys.soundEffectsEnabled)
        self.snapLevelsToFivePercent = defaults.bool(forKey: Keys.snapLevels)
        self.downloadsEnabled = defaults.bool(forKey: Keys.downloadsEnabled)
        self.mediaKeysEnabled = defaults.bool(forKey: Keys.mediaKeysEnabled)
        self.hideWhenFullscreen = defaults.bool(forKey: Keys.hideWhenFullscreen)
        self.hideInScreenshots = defaults.bool(forKey: Keys.hideInScreenshots)
        // Default to Turkish when the Mac is set to Turkish, English otherwise.
        let systemPrefersTurkish = Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
        let storedLanguage = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:))
        self.language = storedLanguage ?? (systemPrefersTurkish ? .turkish : .english)

        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        // Every string reads this static, so it has to be right before any view
        // is built. Set here rather than in the property's initialiser, which
        // runs before the object is fully formed.
        Localization.language = language

        // One-time: anyone still on the old two-second default gets the new one.
        // A value they chose themselves is left alone. Runs last, because it
        // reads a property back and every stored property must exist by then.
        if defaults.integer(forKey: Keys.settingsVersion) < Self.settingsVersion {
            if abs(autoCollapseDelay - 2.0) < 0.001 {
                autoCollapseDelay = Self.defaultCollapseDelay
            }
            defaults.set(Self.settingsVersion, forKey: Keys.settingsVersion)
        }
    }

    // MARK: Login item

    private func applyLaunchAtLogin() {
        guard !isApplyingLaunchAtLogin else { return }

        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // Registration fails for a copy running out of a build folder, so
            // report it rather than leaving a switch that lies.
            launchAtLoginError = error.localizedDescription
            isApplyingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isApplyingLaunchAtLogin = false
        }
    }
}
