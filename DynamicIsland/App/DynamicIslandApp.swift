//
//  DynamicIslandApp.swift
//  DynamicIsland
//
//  App entry point.
//
//  This is a menu-bar–only agent (LSUIElement = YES in Info.plist): no Dock
//  icon, and it keeps running with no visible windows. The whole point of the
//  app is a floating overlay drawn around the MacBook notch, which lives in a
//  borderless NSPanel managed by `IslandController` (created by the
//  AppDelegate). SwiftUI is used purely for the *contents* of that panel (via
//  an NSHostingView) and for the Settings window.
//
//  The primary UI surfaces are:
//    • A `MenuBarExtra` (macOS 13+) rendered as a classic menu — Demo actions,
//      a Simulated-notch toggle, Settings…, and Quit.
//    • A SwiftUI `Settings` scene hosting the minimal Phase-1 settings form.
//
//  All the heavy lifting (notch detection, the overlay panel, hover/click
//  handling, animations, auto-collapse timing) is owned by the AppDelegate and
//  the IslandController — see App/AppDelegate.swift and Island/IslandController.swift.
//

import SwiftUI

@main
struct DynamicIslandApp: App {

    // The AppDelegate owns the shared AppState + IslandModel and builds the
    // overlay panel once the app has finished launching.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Classic status-bar menu. MenuBarExtra's default (.menu) style renders
        // Buttons / Toggles / Dividers as real NSMenu items.
        MenuBarExtra {
            MenuBarView(settings: appDelegate.appState, model: appDelegate.islandModel)
        } label: {
            // A capsule glyph evokes the island pill. "capsule.fill" is a stable
            // SF Symbol available since macOS 11, so it always resolves.
            Image(systemName: "capsule.fill")
        }
        .menuBarExtraStyle(.menu)

        // Native Settings window (opens via ⌘, or the Settings… menu item).
        Settings {
            SettingsView(settings: appDelegate.appState,
                         model: appDelegate.islandModel,
                         requestCalendarAccess: { appDelegate.controller?.requestCalendarAccess() },
                         requestNotificationAccess: { appDelegate.controller?.requestNotificationAccess() },
                         requestMediaKeyAccess: { appDelegate.controller?.requestMediaKeyAccess() })
        }
    }
}
