//
//  SettingsView.swift
//  DynamicIsland
//
//  Native settings form. Every control writes straight through to AppState (and
//  therefore UserDefaults), and the live island reacts as you change them — no
//  Apply button, no restart.
//
//  Only modules that are actually implemented get a switch. A toggle for a
//  feature that does nothing is worse than no toggle at all; later phases add
//  theirs here as they land.
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: AppState
    @ObservedObject var model: IslandModel

    /// Supplied by the app so Settings can raise the permission prompts.
    var requestCalendarAccess: () -> Void = {}
    var requestNotificationAccess: () -> Void = {}
    var requestMediaKeyAccess: () -> Void = {}

    var body: some View {
        Form {
            Section(Strings.modules) {
                Toggle(Strings.nowPlaying, isOn: $settings.musicEnabled)
                Toggle(Strings.volume, isOn: $settings.volumeEnabled)
                Toggle(Strings.brightness, isOn: $settings.brightnessEnabled)
                Toggle(Strings.battery, isOn: $settings.batteryEnabled)
                Toggle(Strings.timer, isOn: $settings.timerEnabled)
                Toggle(Strings.bluetoothDevices, isOn: $settings.bluetoothEnabled)
                Toggle(Strings.cameraMicrophone, isOn: $settings.privacyEnabled)
                Toggle(Strings.fileShelf, isOn: $settings.shelfEnabled)
                Toggle(Strings.downloads, isOn: $settings.downloadsEnabled)

                if settings.downloadsEnabled {
                    Text(Strings.downloadsHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle(Strings.calendar, isOn: $settings.calendarEnabled)
                Toggle(Strings.notifications, isOn: $settings.notificationsEnabled)

                if settings.notificationsEnabled {
                    LabeledContent(Strings.accessibility) {
                        HStack(spacing: 8) {
                            Text(model.notificationsTrusted ? Strings.granted : Strings.notGranted)
                                .foregroundColor(model.notificationsTrusted ? .green : .orange)

                            if !model.notificationsTrusted {
                                Button(Strings.allow) { requestNotificationAccess() }
                                Button(Strings.openSettings) {
                                    NotificationMonitor.openAccessibilitySettings()
                                }
                            }
                        }
                    }

                    Text(Strings.notificationsHint)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let last = model.lastNotification {
                        Text(Strings.lastBanner(last.rawLines.joined(separator: " · ")))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if settings.calendarEnabled {
                    LabeledContent(Strings.calendarAccess) {
                        HStack(spacing: 8) {
                            Text(calendarLabel)
                                .foregroundColor(calendarColor)

                            switch model.calendarAccess {
                            case .notDetermined:
                                Button(Strings.allow) { requestCalendarAccess() }
                            case .denied:
                                Button(Strings.openSettings) { CalendarSettings.open() }
                            case .granted:
                                EmptyView()
                            }
                        }
                    }

                    Text(Strings.calendarHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                LabeledContent(Strings.systemWideMedia) {
                    Text(mediaRemoteLabel).foregroundColor(mediaRemoteColor)
                }

                Text(model.mediaRemote == .unavailable
                     ? Strings.mediaRemoteHintMissing
                     : Strings.mediaRemoteHintActive)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Automation only matters on the fallback path; saying anything
                // about it while MediaRemote is driving would be noise about a
                // permission nothing is asking for.
                if model.mediaRemote != .active {
                LabeledContent(Strings.automation) {
                    HStack(spacing: 8) {
                        Text(automationLabel)
                            .foregroundColor(automationColor)
                        if model.automationStatus == .denied {
                            Button(Strings.openSettings) { AutomationSettings.open() }
                        }
                    }
                }

                Text(automationExplanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section(Strings.appearance) {
                Picker(Strings.display, selection: $settings.preferredDisplay) {
                    Text(Strings.automatic).tag(DisplayPreference.automatic)
                    Text(Strings.builtIn).tag(DisplayPreference.builtIn)
                    ForEach(externalDisplays, id: \.uuid) { display in
                        Text(display.name).tag(DisplayPreference.display(uuid: display.uuid))
                    }
                }

                Text(Strings.displayHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                LabeledContent(Strings.notch, value: notchDescription)

                Picker(Strings.islandSize, selection: $settings.islandSize) {
                    ForEach(IslandSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }

                Picker(Strings.animationSpeed, selection: $settings.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $settings.autoCollapseDelay, in: 0...5, step: 0.25) {
                        Text(Strings.autoCollapseDelay)
                    }
                    Text(Strings.autoCollapseHint(settings.autoCollapseDelay))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(Strings.behaviour) {
                Toggle(Strings.mediaKeys, isOn: $settings.mediaKeysEnabled)

                if settings.mediaKeysEnabled {
                    LabeledContent(Strings.accessibility) {
                        HStack(spacing: 8) {
                            Text(model.mediaKeysTrusted ? Strings.granted : Strings.notGranted)
                                .foregroundColor(model.mediaKeysTrusted ? .green : .orange)

                            if !model.mediaKeysTrusted {
                                Button(Strings.allow) { requestMediaKeyAccess() }
                                Button(Strings.openSettings) {
                                    MediaKeyMonitor.openAccessibilitySettings()
                                }
                            }
                        }
                    }
                }

                Text(Strings.mediaKeysHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(Strings.hideWhenFullscreen, isOn: $settings.hideWhenFullscreen)
                Text(Strings.hideWhenFullscreenHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(Strings.hideInScreenshots, isOn: $settings.hideInScreenshots)
                Text(Strings.hideInScreenshotsHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(Strings.general) {
                Picker(Strings.language, selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }

                Toggle(Strings.snapLevels, isOn: $settings.snapLevelsToFivePercent)
                Text(Strings.snapLevelsHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(Strings.soundEffects, isOn: $settings.soundEffectsEnabled)
                Text(Strings.soundEffectsHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(Strings.launchAtLogin, isOn: $settings.launchAtLogin)

                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: MediaRemote status

    private var mediaRemoteLabel: String {
        switch model.mediaRemote {
        case .active:      return Strings.mediaRemoteActive
        case .idle:        return Strings.mediaRemoteIdle
        case .unavailable: return Strings.mediaRemoteMissing
        }
    }

    private var mediaRemoteColor: Color {
        switch model.mediaRemote {
        case .active:      return .green
        case .idle:        return .secondary
        case .unavailable: return .orange
        }
    }

    // MARK: Automation status

    private var automationLabel: String {
        switch model.automationStatus {
        case .granted:    return Strings.granted
        case .denied:     return Strings.denied
        case .notRunning: return Strings.noPlayerRunning
        case .unknown:    return Strings.notRequested
        }
    }

    private var automationColor: Color {
        switch model.automationStatus {
        case .granted: return .green
        case .denied:  return .orange
        default:       return .secondary
        }
    }

    private var automationExplanation: String {
        switch model.automationStatus {
        case .denied:
            return Strings.automationHintDenied
        default:
            return Strings.automationHint
        }
    }


    // MARK: Calendar

    private var calendarLabel: String {
        switch model.calendarAccess {
        case .granted:       return Strings.granted
        case .denied:        return Strings.denied
        case .notDetermined: return Strings.notRequested
        }
    }

    private var calendarColor: Color {
        switch model.calendarAccess {
        case .granted: return .green
        case .denied:  return .orange
        default:       return .secondary
        }
    }

    // MARK: Displays

    /// Connected displays other than the built-in one, for the picker.
    private var externalDisplays: [(uuid: String, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard !screen.isBuiltIn, let uuid = screen.displayUUID else { return nil }
            return (uuid, screen.localizedName)
        }
    }

    private var notchDescription: String {
        let metrics = NotchDetector.detect(size: settings.islandSize,
                                           preference: settings.preferredDisplay)
        guard metrics.hasPhysicalNotch else { return Strings.noNotch }
        return Strings.notchDetected(width: Int(metrics.notchWidth), height: Int(metrics.notchHeight))
    }
}

/// Deep link to the pane where calendar access is granted.
enum CalendarSettings {
    static func open() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
