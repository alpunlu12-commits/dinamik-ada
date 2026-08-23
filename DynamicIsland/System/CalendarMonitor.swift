//
//  CalendarMonitor.swift
//  DynamicIsland
//
//  The next thing on the calendar.
//
//  EventKit is public API, but reading events needs the user's permission, so
//  this module is **off by default** and asks only when it is switched on. An
//  overlay that pops a calendar prompt the first time it launches has spent
//  trust it hasn't earned yet.
//
//  Nothing leaves the machine: titles are read, displayed, and dropped when the
//  event passes.
//

import AppKit
import EventKit

enum CalendarAccess: Equatable {
    case notDetermined
    case denied
    case granted

    var isGranted: Bool { self == .granted }
}

/// The next event worth mentioning.
struct UpcomingEvent: Equatable {
    var identifier: String
    var title: String
    var start: Date
    var isAllDay: Bool
    var location: String?

    /// Minutes until it starts; negative once it has begun.
    ///
    /// Rounded down, not to nearest: rounding would make the last half-minute
    /// read "in 1 min" while the half-minute before it read "now".
    var minutesUntil: Int {
        Int((start.timeIntervalSinceNow / 60).rounded(.down))
    }

    /// "in 12 min" / "12 dk sonra", the way a calendar alert reads.
    var relativeText: String {
        let minutes = minutesUntil
        if minutes <= 0 { return Strings.justNow }
        if minutes < 60 { return Strings.inMinutes(minutes) }

        let hours = Double(minutes) / 60
        let text = hours < 2
            ? String(format: "%.1f", locale: Localization.locale, hours)
            : String(Int(hours.rounded()))
        return Strings.inHours(text)
    }

    var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: start)
    }
}

final class CalendarMonitor {

    /// Called on the main queue when the next event changes.
    var onChange: ((UpcomingEvent?) -> Void)?

    /// Called on the main queue when permission changes.
    var onAccessChange: ((CalendarAccess) -> Void)?

    /// Called on the main queue once, shortly before an event starts.
    var onImminent: ((UpcomingEvent) -> Void)?


    private(set) var access: CalendarAccess = .notDetermined {
        didSet {
            guard access != oldValue else { return }
            let value = access
            DispatchQueue.main.async { [weak self] in self?.onAccessChange?(value) }
        }
    }

    private(set) var next: UpcomingEvent?


    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var announced: Set<String> = []

    /// How far ahead to look. Anything further out isn't "up next".
    private static let horizon: TimeInterval = 12 * 3600

    /// How close an event has to be before the island says so.
    private static let imminentMinutes = 5

    private static let refreshInterval: TimeInterval = 30

    // MARK: Lifecycle

    func start() {
        access = Self.currentAccess()
        guard timer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refresh()

        // Switching the module on *is* the request. Without this the module
        // came up, found no permission, and went quiet — no prompt, no events,
        // no explanation — and the only way to ever see the system prompt was
        // to find a second button in a different part of Settings. Every other
        // module in this app starts working the moment its switch is flipped.
        //
        // Same rule the Now Playing module already follows for Automation: ask
        // at the moment the permission is actually needed.
        if access == .notDetermined { requestAccess() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        announced.removeAll()

        if next != nil {
            next = nil
            onChange?(nil)
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Ask for permission. Raises the system prompt the first time only; after a
    /// refusal macOS answers immediately and the UI has to send the user to
    /// System Settings instead.
    func requestAccess(completion: ((CalendarAccess) -> Void)? = nil) {
        // A menu-bar agent is never frontmost, and the system's permission
        // sheet can open behind whatever the user is looking at. Coming
        // forward first is what makes an unmissable prompt out of one that is
        // easy to miss — and this happens once, on the first request only.
        NSApp.activate(ignoringOtherApps: true)

        let finish: (Bool) -> Void = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = Self.currentAccess()
                self.refresh()
                completion?(self.access)
            }
        }

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in finish(granted) }
        } else {
            store.requestAccess(to: .event) { granted, _ in finish(granted) }
        }
    }

    // MARK: Reading

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess:    return .granted
        case .authorized:    return .granted
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default:    return .denied
        }
    }

    private func refresh() {
        access = Self.currentAccess()
        guard access.isGranted else {
            deliver(nil)
            return
        }

        let now = Date()
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(Self.horizon),
                                                 calendars: nil)
        // All-day entries are context, not appointments; they'd sit on the
        // island all day saying nothing useful.
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now.addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }
            .first

        deliver(event.map {
            UpcomingEvent(identifier: $0.eventIdentifier ?? $0.title ?? UUID().uuidString,
                          title: $0.title ?? "Event",
                          start: $0.startDate,
                          isAllDay: $0.isAllDay,
                          location: $0.location?.isEmpty == false ? $0.location : nil)
        })
    }

    private func deliver(_ event: UpcomingEvent?) {
        if event != next {
            next = event
            onChange?(event)
        }

        // Announce once per event, when it is nearly upon us.
        //
        // The lower bound is -1, not 0: `minutesUntil` rounds down, so an event
        // that started thirty seconds ago reads as -1, and a strict `>= 0`
        // opened a minute-wide hole right at the start time. An event that has
        // just begun is still worth saying — and `refresh` already keeps events
        // for that same minute after they start.
        guard let event, event.minutesUntil <= Self.imminentMinutes,
              event.minutesUntil >= -1,
              !announced.contains(event.identifier) else { return }
        announced.insert(event.identifier)
        onImminent?(event)
    }
}
