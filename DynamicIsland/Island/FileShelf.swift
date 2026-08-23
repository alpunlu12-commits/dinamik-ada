//
//  FileShelf.swift
//  DynamicIsland
//
//  The temporary shelf dropped files land on.
//
//  Paths are persisted rather than bookmarks: the app is unsandboxed, so it can
//  reach a file by path alone, and a shelf is explicitly *temporary* — a file
//  that moved or was thrown away should quietly leave the shelf rather than
//  linger as a bookmark that resolves somewhere surprising. Anything missing is
//  dropped when the shelf is loaded.
//

import AppKit

/// One file on the shelf.
struct ShelfItem: Equatable, Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// The icon Finder would show. Looked up once, when the item is created.
    let icon: NSImage
}

final class FileShelf {

    /// Called on the main queue whenever the contents change.
    var onChange: (([ShelfItem]) -> Void)?

    private(set) var items: [ShelfItem] = []

    /// A shelf is a staging area, not a file manager.
    static let capacity = 6

    private let defaults: UserDefaults
    private static let storageKey = "shelfPaths"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Contents

    func add(_ urls: [URL]) {
        var changed = false

        for url in urls {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }

            // Re-dropping something already on the shelf moves it to the front
            // rather than duplicating it.
            items.removeAll { $0.url == standardized }
            items.insert(ShelfItem(url: standardized,
                                   icon: NSWorkspace.shared.icon(forFile: standardized.path)),
                         at: 0)
            changed = true
        }

        guard changed else { return }
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
        commit()
    }

    func remove(_ item: ShelfItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        items.removeAll { $0.id == item.id }
        commit()
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        commit()
    }

    // MARK: Actions

    /// Put the given files on the general pasteboard.
    ///
    /// Writing the URLs covers Finder and anything modern — that alone already
    /// produces both `public.file-url` and the legacy `NSFilenamesPboardType`.
    /// The paths are added as plain text as well, so pasting into a text field,
    /// a terminal or a chat box gives something useful instead of nothing.
    func copy(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }

        let urls = items.map(\.url)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func copyAll() { copy(items) }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func revealAll() { reveal(items) }

    /// Hand files to AirDrop. The picker is Apple's own, so the island never
    /// sees who the file goes to.
    func airDrop(_ items: [ShelfItem]) {
        guard !items.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items.map(\.url))
    }

    func airDropAll() { airDrop(items) }

    func remove(_ items: [ShelfItem]) {
        let ids = Set(items.map(\.id))
        guard self.items.contains(where: { ids.contains($0.id) }) else { return }
        self.items.removeAll { ids.contains($0.id) }
        commit()
    }

    /// Move files somewhere the user picks, then drop them from the shelf.
    ///
    /// Move was left out of the first shelf on purpose: moving without asking
    /// where is how people lose files. The destination prompt is what makes the
    /// operation safe, so it is not optional — no folder, no move.
    ///
    /// `completion` reports what actually moved, because a partial failure
    /// (permissions, a name collision the user declined) must not silently
    /// remove a chip whose file is still sitting where it was.
    func move(_ items: [ShelfItem], completion: (([ShelfItem], Error?) -> Void)? = nil) {
        guard !items.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = Strings.moveHere
        panel.message = Strings.moveMessage(items.count)

        // A menu-bar agent is not frontmost, and an open panel from a background
        // app opens behind everything. Activating first is what puts it in front.
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }

            var moved: [ShelfItem] = []
            var failure: Error?

            for item in items {
                let target = Self.availableURL(in: destination,
                                               named: item.url.lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: item.url, to: target)
                    moved.append(item)
                } catch {
                    failure = error
                }
            }

            // Only what really moved leaves the shelf.
            self.remove(moved)
            completion?(moved, failure)
        }
    }

    /// A free name in `directory`, so a move never overwrites something already
    /// there. "report.pdf" becomes "report 2.pdf", the way Finder names copies.
    private static func availableURL(in directory: URL, named name: String) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension

        for suffix in 2...999 {
            var next = directory.appendingPathComponent("\(base) \(suffix)")
            if !ext.isEmpty { next.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        // 998 collisions is not a real scenario; a unique name still beats a
        // silent overwrite.
        return directory.appendingPathComponent("\(base) \(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    // MARK: Persistence

    private func commit() {
        defaults.set(items.map(\.url.path), forKey: Self.storageKey)
        onChange?(items)
    }

    private func load() {
        let paths = defaults.stringArray(forKey: Self.storageKey) ?? []
        items = paths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let url = URL(fileURLWithPath: path)
            return ShelfItem(url: url, icon: NSWorkspace.shared.icon(forFile: path))
        }
        // Prune anything that vanished while we weren't running.
        if items.count != paths.count { defaults.set(items.map(\.url.path), forKey: Self.storageKey) }
    }
}
