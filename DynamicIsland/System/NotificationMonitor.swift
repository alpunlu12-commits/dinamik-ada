//
//  NotificationMonitor.swift
//  DynamicIsland
//
//  Mirrors macOS notification banners onto the island.
//
//  There is no supported way to read another app's notifications. The
//  Notification Center database needs Full Disk Access and is a private SQLite
//  schema that could change with any release; the remaining route is to read the
//  banner *as drawn* through the accessibility API. That needs the user's
//  Accessibility permission, so the module is off by default and says plainly
//  what it needs — an overlay that silently does nothing is worse than one that
//  explains itself.
//
//  Banners are found by polling the notification UI's window list once a second
//  rather than by subscribing to an AX notification. Polling has no unknowns:
//  every banner that is on screen for a moment is seen, without depending on
//  which AX notification a given macOS version happens to post for a banner, and
//  a default banner stays up for about five seconds. The read is a handful of
//  accessibility calls against one process.
//
//  Nothing is stored. Text is read, shown, and dropped; the only copy kept is
//  the last one, so Settings can show what was parsed when a banner comes out
//  wrong.
//

import AppKit
import ApplicationServices

/// One banner, as far as the island is concerned.
struct IslandNotification: Equatable {
    var appName: String?
    var title: String
    var body: String?

    /// What the parser saw, for the diagnostic line in Settings.
    var rawLines: [String]

    /// Same banner shown twice shouldn't announce twice.
    var signature: String { "\(appName ?? "")|\(title)|\(body ?? "")" }
}

final class NotificationMonitor {

    /// Called on the main queue when a new banner appears.
    var onNotification: ((IslandNotification) -> Void)?

    /// Called on the main queue when the Accessibility permission changes.
    var onTrustChange: ((Bool) -> Void)?

    private(set) var isTrusted = false

    /// The last banner parsed, so Settings can show what the island understood.
    private(set) var lastParsed: IslandNotification?

    private var timer: Timer?
    private var trustObserver: NSObjectProtocol?
    private var elements: [pid_t: AXUIElement] = [:]

    /// Signatures currently on screen, so a banner is announced once.
    private var visible: Set<String> = []

    /// Banners come from the notification UI; the older alert-style presenter is
    /// checked too, since some system alerts still go through it.
    private static let bundleIdentifiers = [
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
    ]
    private static let sampleInterval: TimeInterval = 1.0

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }

        // macOS announces changes to the accessibility database; re-checking on
        // that is instant, where the poll would take up to a second.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // The database is written just before the notification lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.sample() }
        }

        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let trustObserver {
            DistributedNotificationCenter.default().removeObserver(trustObserver)
        }
        trustObserver = nil
        elements.removeAll()
        visible.removeAll()
    }

    deinit {
        timer?.invalidate()
    }

    /// Raise the system's Accessibility prompt. macOS shows it once; after that
    /// the answer is remembered and the UI has to point at System Settings.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Sampling

    private func sample() {
        let trusted = probeTrust()
        if trusted != isTrusted {
            isTrusted = trusted
            // Losing trust invalidates the element we were holding.
            if !trusted { elements.removeAll(); visible.removeAll() }
            onTrustChange?(trusted)
        }
        guard trusted else { return }

        var onScreen: Set<String> = []
        var arrived: [IslandNotification] = []

        for app in attachedElements() {
            let windows = banners(of: app)
            writeDumpIfEnabled(windows)

            for window in windows {
                guard let notification = parse(window) else { continue }
                onScreen.insert(notification.signature)
                if !visible.contains(notification.signature) { arrived.append(notification) }
            }
        }

        visible = onScreen

        // One banner per tick is plenty; a burst would just fight for the island.
        if let newest = arrived.last {
            lastParsed = newest
            onNotification?(newest)
        }
    }

    /// Whether the accessibility API actually works for us.
    ///
    /// `AXIsProcessTrusted()` is not a reliable answer: it can keep reporting
    /// false after the user has granted the permission, until the app is
    /// relaunched. The API itself is the honest test — if a read against another
    /// process comes back, we are trusted whatever the flag claims, and only a
    /// flat `apiDisabled` means we genuinely are not.
    private func probeTrust() -> Bool {
        if AXIsProcessTrusted() { return true }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            Self.bundleIdentifiers.contains($0.bundleIdentifier ?? "")
        }) else { return false }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) {
        case .success:    return true
        case .apiDisabled: return false
        default:          return false
        }
    }

    /// Accessibility elements for the notification presenters, re-fetched when
    /// one of them has been relaunched since we last looked.
    private func attachedElements() -> [AXUIElement] {
        let running = NSWorkspace.shared.runningApplications.filter {
            Self.bundleIdentifiers.contains($0.bundleIdentifier ?? "")
        }

        let pids = Set(running.map(\.processIdentifier))
        if Set(elements.keys) != pids {
            elements = elements.filter { pids.contains($0.key) }
            for pid in pids where elements[pid] == nil {
                elements[pid] = AXUIElementCreateApplication(pid)
            }
            visible.removeAll()
        }
        return Array(elements.values)
    }

    /// A banner is normally a window of the presenter. Some macOS versions hang
    /// it off the application element directly, so both shapes are read.
    private func banners(of app: AXUIElement) -> [AXUIElement] {
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement], !list.isEmpty {
            return list
        }

        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            return list
        }
        return []
    }

    // MARK: Parsing

    /// A banner's text, in the order it is laid out.
    ///
    /// Deliberately structural rather than clever: macOS has moved this layout
    /// around over the years, so the parser reads every piece of static text in
    /// the window and assigns meaning by position. The pieces it saw are carried
    /// along in `rawLines` so a misread can be diagnosed from Settings instead of
    /// guessed at.
    private func parse(_ window: AXUIElement) -> IslandNotification? {
        var lines: [String] = []
        collectText(window, into: &lines, depth: 0)

        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        switch cleaned.count {
        case 1:
            return IslandNotification(appName: nil, title: cleaned[0], body: nil, rawLines: cleaned)
        case 2:
            return IslandNotification(appName: cleaned[0], title: cleaned[1], body: nil,
                                      rawLines: cleaned)
        default:
            return IslandNotification(appName: cleaned[0],
                                      title: cleaned[1],
                                      body: cleaned.dropFirst(2).joined(separator: " "),
                                      rawLines: cleaned)
        }
    }

    private func collectText(_ element: AXUIElement, into lines: inout [String], depth: Int) {
        // The banner is drawn inside a full-screen host window, so its text sits
        // well down the tree — an earlier depth limit of 12 never reached it.
        // The bound is now generous enough to find the text and still stop a
        // pathological tree from costing a frame.
        guard depth < 40, lines.count < 16 else { return }

        // Read text wherever it is exposed. Banner labels are usually
        // AXStaticText, but the layout has changed across releases and a label
        // that arrives as a description or a title is still a label.
        if let role = string(element, kAXRoleAttribute) {
            if role == kAXStaticTextRole {
                if let value = string(element, kAXValueAttribute) { lines.append(value) }
                else if let title = string(element, kAXTitleAttribute) { lines.append(title) }
            } else if role != kAXWindowRole, role != kAXGroupRole,
                      let description = string(element, kAXDescriptionAttribute),
                      description.count > 1 {
                lines.append(description)
            }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &children) == .success,
              let list = children as? [AXUIElement]
        else { return }

        for child in list { collectText(child, into: &lines, depth: depth + 1) }
    }

    /// Dump what the accessibility tree actually looks like, so a banner the
    /// parser misreads can be fixed from evidence rather than guesswork.
    ///
    /// Off unless someone turns it on deliberately:
    ///   `defaults write com.abacusisland.dynamicisland axDebug -bool YES`
    /// It writes notification text to a file, which is exactly the thing this
    /// app otherwise refuses to keep, so it is never on by default.
    private func dump(_ element: AXUIElement, depth: Int, into text: inout String) {
        guard depth < 40 else { return }

        let role = string(element, kAXRoleAttribute) ?? "?"
        let value = string(element, kAXValueAttribute) ?? ""
        let title = string(element, kAXTitleAttribute) ?? ""
        let description = string(element, kAXDescriptionAttribute) ?? ""
        if !value.isEmpty || !title.isEmpty || !description.isEmpty || depth < 4 {
            text += String(repeating: "  ", count: depth)
                + "\(role) value=\(value) title=\(title) desc=\(description)\n"
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for child in list { dump(child, depth: depth + 1, into: &text) }
    }

    private func writeDumpIfEnabled(_ windows: [AXUIElement]) {
        guard UserDefaults.standard.bool(forKey: "axDebug") else { return }

        var text = "=== \(Date()) — \(windows.count) pencere ===\n"
        for window in windows { dump(window, depth: 0, into: &text) }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DynamicIsland-ax.log")
        if let data = text.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
