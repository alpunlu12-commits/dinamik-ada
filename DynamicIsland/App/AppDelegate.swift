//
//  AppDelegate.swift
//  DynamicIsland
//
//  Owns the app-wide state and builds the overlay once launching completes.
//
//  Ownership graph:
//    AppDelegate
//      ├─ appState    (AppState)      persisted user settings
//      ├─ islandModel (IslandModel)   transient interaction state (hover/click)
//      └─ controller  (IslandController) the NSPanel + hosting view + wiring
//
//  Everything runs on the main actor (UI + AppKit).
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Persisted settings, shared with the menu, the Settings window and the
    /// island view.
    let appState = AppState()

    /// Transient interaction state (hover / click / demo), shared with the menu
    /// and the island view.
    let islandModel = IslandModel()

    /// The overlay controller. Created in `applicationDidFinishLaunching` so the
    /// screen geometry is available.
    private(set) var controller: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: LSUIElement in Info.plist already makes us an
        // accessory (no Dock icon), but set it explicitly too.
        NSApp.setActivationPolicy(.accessory)

        // Build and show the notch overlay.
        controller = IslandController(appState: appState, model: islandModel)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu-bar agent: keep running when the Settings window is closed.
        false
    }
}
