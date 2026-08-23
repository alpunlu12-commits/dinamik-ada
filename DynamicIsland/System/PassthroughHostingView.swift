//
//  PassthroughHostingView.swift
//  DynamicIsland
//
//  The panel spans a large rectangle at the top of the screen, but only a small
//  part of it is actually painted. Without this, that whole rectangle would
//  swallow clicks meant for the app underneath.
//
//  `hitTest` therefore returns nil for every point outside the island's current
//  shape, which makes AppKit continue the hit test in the window below — real
//  click-through, not a transparency trick.
//
//  The hit rect is kept in *global* screen coordinates on purpose: the island is
//  positioned from screen geometry, and comparing in one space avoids depending
//  on whether NSHostingView happens to be flipped.
//
//  Every press is handled here in AppKit, and SwiftUI draws only.
//
//  That is not a stylistic choice. NSHostingView does not vend child views for
//  its content: it hit-tests internally and always answers with itself, so a
//  press either reaches this class or reaches SwiftUI's own gesture system —
//  and that system does not fire reliably in a panel that never becomes key,
//  in an app that is almost never frontmost. Routing presses by geometry here
//  is the only arrangement that behaves the same whether or not the app happens
//  to be active.
//
//  `controlRects` therefore carries the transport buttons' hit areas, computed
//  from the very same function the view positions their glyphs with.
//

import AppKit
import SwiftUI

/// How far the pointer must travel before a press on a shelf chip becomes a
/// drag. Below this, the press is a click.
///
/// File-scope because a generic class cannot hold a static stored property.
private let shelfDragThreshold: CGFloat = 3

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {

    // MARK: Drag and drop

    /// Called when a file drag enters or leaves the drop zone.
    var onDragTargeting: ((Bool) -> Void)?

    /// Called with the dropped files.
    var onDrop: (([URL]) -> Void)?

    /// The file a shelf chip stands for, so it can be dragged back out.
    var draggableFile: ((CGPoint) -> URL?)?

    /// Called when a drag *out of* the shelf starts and ends.
    var onDragOutChange: ((Bool) -> Void)?

    /// True while this view is the source of a drag session.
    ///
    /// The controller has to know, because the app infers "somebody is dragging
    /// files" from the system drag pasteboard — and our own outgoing drag writes
    /// to exactly that pasteboard. Without this flag the island sees its own
    /// drag, turns itself into a drop target, and catches the file the user was
    /// trying to take *out*.
    private(set) var isDraggingOut = false {
        didSet {
            guard isDraggingOut != oldValue else { return }
            onDragOutChange?(isDraggingOut)
        }
    }

    private let dragSource = ShelfDragSource()


    /// Island rect in global (screen) coordinates. Everything outside passes through.
    var hitRect: CGRect = .zero

    /// Called when a click completes on the island's body.
    var onClick: (() -> Void)?

    /// Called when a press completes on a discrete control (a transport button).
    var onControl: ((IslandControl) -> Void)?

    /// Called continuously while a value control (volume, brightness) is pressed
    /// or dragged, with the new 0…1 value.
    var onScrub: ((IslandControl, Double) -> Void)?

    /// Called on a right-click inside the island, with whatever control was
    /// under the pointer (nil for the island's body) and the screen point to
    /// pop a menu at.
    var onContextMenu: ((IslandControl?, NSPoint) -> Void)?

    /// Hit geometry of the control center's controls, in global screen
    /// coordinates. Empty unless the control center is open.
    var controlHits: [IslandControlHit] = []

    /// True while a value control is being dragged. The controller leaves the
    /// panel active and the island open for the duration, even if the pointer
    /// wanders outside.
    private(set) var isTracking = false

    private var scrubbing: IslandControlHit?

    /// A press on a shelf chip that has not moved far enough to be a drag yet.
    private var pendingDrag: (url: URL, origin: NSPoint)?

    /// Belt and braces: if a mouse-up is ever missed — the button released over
    /// another Space, a display change mid-drag — tracking would otherwise latch
    /// on and hold the island open forever. The controller calls this each time
    /// it samples the pointer.
    func clearStaleTracking() {
        guard isTracking, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        scrubbing = nil
        isTracking = false
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
        dragSource.onSessionEnd = { [weak self] in self?.isDraggingOut = false }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The panel deliberately never becomes key, which means AppKit treats every
    /// click on it as a first-mouse click — and would swallow each one as a mere
    /// activation click. Accepting first mouse is what makes a single click on
    /// the island actually reach SwiftUI.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Claim the island and nothing else; everything outside falls through to
        // whatever is beneath.
        hitRect.contains(screenPoint(fromWindowPoint: point)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = screenPoint(fromWindowPoint: event.locationInWindow)

        // A shelf chip is both a button and a drag source. Starting the drag
        // here would be too eager: a dragging session takes over the mouse, so
        // the click that opens the file could never complete. Remember the
        // candidate and let mouseDragged decide.
        if let url = draggableFile?(point) {
            pendingDrag = (url, event.locationInWindow)
            return
        }

        // A value control takes effect immediately on press, then follows the
        // drag — the same feel as the sliders in Control Center.
        if let hit = controlHits.first(where: { $0.hitRect.contains(point) }),
           Self.isScrubbable(hit.control) {
            scrubbing = hit
            isTracking = true
            onScrub?(hit.control, hit.fraction(at: point))
        }
        // Anything else is decided on mouse-up, like a button.
    }

    override func mouseDragged(with event: NSEvent) {
        if let pending = pendingDrag {
            let dx = event.locationInWindow.x - pending.origin.x
            let dy = event.locationInWindow.y - pending.origin.y
            guard dx * dx + dy * dy >= shelfDragThreshold * shelfDragThreshold else { return }

            pendingDrag = nil
            beginFileDrag(pending.url, with: event)
            return
        }

        guard let scrubbing else { return }
        let point = screenPoint(fromWindowPoint: event.locationInWindow)
        onScrub?(scrubbing.control, scrubbing.fraction(at: point))
    }

    override func mouseUp(with event: NSEvent) {
        // The pointer never travelled, so the press was a click after all.
        pendingDrag = nil

        if scrubbing != nil {
            scrubbing = nil
            isTracking = false
            return
        }

        let point = screenPoint(fromWindowPoint: event.locationInWindow)

        if let hit = controlHits.first(where: { $0.hitRect.contains(point) }) {
            switch hit.control {
            case let .shelf(.open(index))
                where event.modifierFlags.intersection([.command, .shift]).isEmpty == false:
                // ⌘/⇧ turns a chip press into a selection toggle. The chip is
                // the same target either way, so the modifier — not a separate
                // hit rect — is what distinguishes them.
                onControl?(.shelf(.toggleSelection(index: index)))

            case .transport, .timer, .shelf, .artwork:
                onControl?(hit.control)
            case .tile, .seek:
                // Adjustable tiles already acted on press and drag; the battery
                // readout swallows the press rather than closing the control
                // center under the pointer.
                break
            }
            return
        }

        guard hitRect.contains(point) else { return }
        onClick?()
    }

    /// Controls that take a dragged value rather than a click.
    private static func isScrubbable(_ control: IslandControl) -> Bool {
        switch control {
        case let .tile(tile): return tile.isAdjustable
        case .seek:           return true
        default:              return false
        }
    }

    /// A right-click never scrubs, drags or opens — it only asks for a menu.
    ///
    /// AppKit's own `menu(for:)` route is not usable here: it wants an NSMenu
    /// resolved from the view before the click is dispatched, and the island's
    /// controls are hit-tested by geometry rather than being real subviews. So
    /// the point is resolved the same way every other press is, and the
    /// controller decides what the menu should say.
    override func rightMouseDown(with event: NSEvent) {
        let point = screenPoint(fromWindowPoint: event.locationInWindow)
        guard hitRect.contains(point) else {
            super.rightMouseDown(with: event)
            return
        }

        let control = controlHits.first(where: { $0.hitRect.contains(point) })?.control
        onContextMenu?(control, point)
    }

    private func beginFileDrag(_ url: URL, with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: 48, height: 48)
        let origin = NSPoint(x: event.locationInWindow.x - size.width / 2,
                             y: event.locationInWindow.y - size.height / 2)
        item.setDraggingFrame(NSRect(origin: origin, size: size), contents: icon)

        isDraggingOut = true
        beginDraggingSession(with: [item], event: event, source: dragSource)
    }

    /// `point` arrives in the window's coordinate space (for a borderless
    /// panel's content view the superview's space is the window's), so offsetting
    /// by the window origin gives screen coordinates.
    private func screenPoint(fromWindowPoint point: NSPoint) -> NSPoint {
        guard let window else { return .zero }
        return NSPoint(x: window.frame.minX + point.x,
                       y: window.frame.minY + point.y)
    }

    // MARK: Dragging destination

    // These live in the class body rather than an extension: a generic class
    // cannot vend @objc members from one, and AppKit reaches them by selector.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsFiles(sender) else { return [] }
        onDragTargeting?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsFiles(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargeting?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragTargeting?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isDraggingOut else { return false }
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func acceptsFiles(_ sender: NSDraggingInfo) -> Bool {
        // A view can be both the source and a destination, so while the user is
        // pulling a file *out* of the shelf AppKit still offers it back to us
        // the whole time the pointer is over the island. Accepting would arm the
        // island as a drop target for the very file being removed, which is
        // exactly what made dragging out look broken.
        guard !isDraggingOut else { return false }

        return sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

}

/// The drag source for files taken back off the shelf.
///
/// A separate object because NSHostingView already conforms to NSDraggingSource
/// without leaving the method open to override.
final class ShelfDragSource: NSObject, NSDraggingSource {

    /// Called when the session finishes, however it finishes.
    var onSessionEnd: (() -> Void)?

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Dragging a shelved file out copies it; the shelf keeps its own entry.
        context == .outsideApplication ? [.copy, .link] : []
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onSessionEnd?()
    }
}
