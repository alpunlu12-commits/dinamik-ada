//
//  MenuBarView.swift
//  DynamicIsland
//
//  Contents of the status-bar menu. With MenuBarExtra's `.menu` style these
//  Buttons / Toggles / Dividers are rendered as real NSMenu items, so the menu
//  looks and behaves like any other system menu.
//
//  The menu doubles as the app's diagnostics surface. A menu-bar agent has no
//  window to complain in, so when something isn't working — no player running,
//  Automation refused — it has to be legible from here rather than leaving the
//  island mysteriously empty.
//

import AppKit
import SwiftUI

struct MenuBarView: View {

    @ObservedObject var settings: AppState
    @ObservedObject var model: IslandModel

    var body: some View {
        nowPlayingStatus

        Divider()

        timerSection

        Divider()

        shelfSection

        Divider()

        calendarSection

        Divider()

        notificationSection

        Divider()

        Button(Strings.demoExpand) {
            model.demoExpand()
        }

        Button(model.state == .controlCenter ? Strings.demoHideCC : Strings.demoShowCC) {
            model.demoToggleControlCenter()
        }

        Divider()

        settingsItem

        Divider()

        Button(Strings.quit) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: Now Playing

    @ViewBuilder
    private var nowPlayingStatus: some View {
        if !settings.musicEnabled {
            Text(Strings.nowPlayingOff)
        } else if let track = model.nowPlaying {
            Text("\(track.isPlaying ? "▶" : "⏸")  \(track.title) — \(track.artist)")

            if model.automationStatus == .denied {
                Button(Strings.automationNeeded) {
                    AutomationSettings.open()
                }
            }
        } else if model.automationStatus == .denied {
            Button(Strings.automationDeniedMenu) {
                AutomationSettings.open()
            }
        } else {
            Text(Strings.nothingPlaying)
        }
    }

    // MARK: Timer

    /// The island offers three presets; the full list lives here, because a
    /// free-form duration needs a keyboard and the island's panel can never
    /// become key.
    @ViewBuilder
    private var timerSection: some View {
        if !settings.timerEnabled {
            Text(Strings.timerOff)
        } else if let countdown = model.countdown {
            Text(Strings.timerStatus(countdown.text, running: countdown.isRunning))

            Button(countdown.isRunning ? Strings.pauseTimer : Strings.resumeTimer) {
                model.timerAction(.toggle)
            }
            Button(Strings.restartTimer) { model.timerAction(.restart) }
            Button(Strings.cancelTimer) { model.timerAction(.cancel) }
        } else {
            Menu(Strings.startTimer) {
                ForEach([1, 3, 5, 10, 15, 20, 25, 30, 45, 60], id: \.self) { minutes in
                    Button(Strings.minutesLong(minutes)) {
                        model.timerAction(.start(minutes: minutes))
                    }
                }
            }
        }
    }

    // MARK: Shelf

    @ViewBuilder
    private var shelfSection: some View {
        if !settings.shelfEnabled {
            Text(Strings.shelfOff)
        } else if model.shelf.isEmpty {
            Text(Strings.shelfEmptyHint)
        } else {
            Text(Strings.shelfStatus(model.shelf.count))
            Button(Strings.copyShelfFiles) { model.shelfAction(.copyAll) }
            Button(Strings.airDropShelfFiles) { model.shelfAction(.airDropAll) }
            Button(Strings.clearShelf) { model.shelfAction(.clear) }
        }
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarSection: some View {
        if !settings.calendarEnabled {
            Text(Strings.calendarOff)
        } else if model.calendarAccess == .denied {
            Button(Strings.calendarDeniedMenu) { CalendarSettings.open() }
        } else if let event = model.upcomingEvent {
            Text(Strings.upNextMenu(title: event.title, time: event.timeText, relative: event.relativeText))
        } else {
            Text(Strings.nothingOnCalendar)
        }
    }

    // MARK: Notifications

    @ViewBuilder
    private var notificationSection: some View {
        if !settings.notificationsEnabled {
            Text(Strings.notificationsOff)
        } else if !model.notificationsTrusted {
            Button(Strings.notificationsNeedAccessibility) {
                NotificationMonitor.openAccessibilitySettings()
            }
        } else {
            Text(Strings.notificationsOn)
        }
    }

    // MARK: Settings

    /// `SettingsLink` is the supported way to open the Settings scene, but it is
    /// macOS 14+; on 13 fall back to the AppKit action.
    @ViewBuilder
    private var settingsItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(Strings.settingsItem)
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button(Strings.settingsItem) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// Deep link to the pane where Automation is granted, since the permission
/// cannot be re-requested once the user has said no.
enum AutomationSettings {
    static func open() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
