//
//  DragMonitor.swift
//  DynamicIsland
//
//  Notices that a file drag is happening anywhere on the system, so the island
//  can arm itself as a drop target before the pointer ever reaches it.
//
//  The overlay panel is inert unless the pointer is on the island — that is what
//  keeps the menu bar clickable — but a window that ignores mouse events also
//  refuses drags. Something has to un-inert the panel *while a drag is in
//  flight*, and AppKit will not tell us about a drag that has not entered one of
//  our views yet.
//
//  So the drag is inferred from two cheap facts, neither of which needs a
//  permission or an event tap:
//
//    • The system drag pasteboard's `changeCount` moves when any app starts a
//      drag, and its contents say whether files are involved.
//    • The left button is held for the whole of a drag.
//
//  Together — button down, and the drag pasteboard has changed since the last
//  time the button was up — those mean "a drag is in progress right now", and
//  the pasteboard says whether it carries files.
//

import AppKit

final class DragMonitor {

    /// Called on the main queue when a file drag starts or finishes.
    var onChange: ((Bool) -> Void)?

    private(set) var isDraggingFiles = false

    /// The change count last seen with the button up: anything newer than this,
    /// while the button is down, belongs to a drag that is still happening.
    private var idleChangeCount: Int

    private var lastInspectedChangeCount: Int
    private var lastInspectionSawFiles = false

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.pasteboard = pasteboard
        self.idleChangeCount = pasteboard.changeCount
        self.lastInspectedChangeCount = pasteboard.changeCount
    }

    /// Called from the controller's pointer sampling. `buttonDown` is passed in
    /// rather than read here so the logic can be exercised in isolation.
    @discardableResult
    func sample(buttonDown: Bool) -> Bool {
        let changeCount = pasteboard.changeCount

        guard buttonDown else {
            // Between drags the pasteboard keeps whatever the last one left in
            // it, so the baseline has to move forward whenever nothing is held.
            idleChangeCount = changeCount
            set(false)
            return isDraggingFiles
        }

        guard changeCount != idleChangeCount else {
            set(false)
            return isDraggingFiles
        }

        set(carriesFiles(changeCount: changeCount))
        return isDraggingFiles
    }

    /// URLs currently on the drag pasteboard, for previewing what would land.
    func draggedURLs() -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self],
                               options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    // MARK: Internals

    /// Reading the pasteboard's types is more expensive than reading its change
    /// count, so the answer is cached until the contents actually change.
    private func carriesFiles(changeCount: Int) -> Bool {
        if changeCount != lastInspectedChangeCount {
            lastInspectedChangeCount = changeCount
            lastInspectionSawFiles = pasteboard.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
        }
        return lastInspectionSawFiles
    }

    private func set(_ dragging: Bool) {
        guard dragging != isDraggingFiles else { return }
        isDraggingFiles = dragging
        onChange?(dragging)
    }
}
