//
//  OverlayPanel.swift
//  DynamicIsland
//
//  A borderless, transparent, non-activating floating panel that hosts the
//  island. Key design points:
//
//    • .nonactivatingPanel  — receives mouse events (hover/click) WITHOUT
//      stealing focus from or activating over the frontmost app.
//    • .borderless          — no title bar / chrome.
//    • level .statusBar     — floats above normal windows and the menu bar.
//    • canJoinAllSpaces + fullScreenAuxiliary — visible on every Space and over
//      full-screen apps.
//    • clear background, no shadow at the window level (the SwiftUI island draws
//      its own shadow) so only the island pixels are visible.
//
//  Clicks that land *outside* the island's current shape pass straight through
//  to whatever is beneath — that behaviour is implemented in
//  PassthroughHostingView via hitTest, not here.
//

import AppKit

final class OverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar                       // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                        // island draws its own shadow

        isMovable = false
        isMovableByWindowBackground = false
        // Default: the island is part of the screen, so it belongs in a
        // screenshot of it. `setHiddenFromCapture` flips this for anyone who
        // would rather it stayed out of recordings and shared screens.
        sharingType = .readOnly
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true

        // Inert until the pointer is actually over the island. The controller
        // flips this as the pointer enters and leaves.
        //
        // hitTest alone is not enough: the island's drop shadow paints
        // semi-transparent pixels well outside its outline, and the window
        // server routes clicks on any non-transparent pixel to this panel. Those
        // clicks then die here instead of reaching the menu bar behind us.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Keep the island out of screenshots, screen recordings and shared screens.
    ///
    /// `sharingType = .none` tells the window server not to include this window
    /// in any capture — the same switch a password field uses. It costs nothing
    /// and is reversible, so it is offered as a preference rather than imposed:
    /// on a call you want the island hidden, in a screenshot for a bug report
    /// you want it visible.
    func setHiddenFromCapture(_ hidden: Bool) {
        let wanted: NSWindow.SharingType = hidden ? .none : .readOnly
        guard sharingType != wanted else { return }
        sharingType = wanted
    }
}
