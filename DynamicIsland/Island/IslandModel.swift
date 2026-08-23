//
//  IslandModel.swift
//  DynamicIsland
//
//  Transient interaction state plus the content currently on the island.
//
//  Two inputs decide how the island looks:
//    • `state`  — driven by the pointer: hover expands, a click opens the
//      control center.
//    • `transient` — driven by the system: a volume, brightness or power change
//      takes the island over for a moment.
//
//  `renderedState` folds those together so the view and the hit region always
//  agree on one answer. The control center outranks everything: once the user
//  has opened it deliberately, a volume keypress must not yank it away.
//
//  Nothing here knows about geometry or AppKit — the controller feeds it events
//  and the view reads the result. Settings live in AppState.
//

import Foundation
import Combine

/// The three island sizes, ordered so they can be compared.
/// Which Now Playing route is live.
enum MediaRemoteStatus: Equatable {
    /// The vendored adapter isn't in this build — see DynamicIsland/Vendor.
    case unavailable
    /// Present, but not producing data (yet, or at all).
    case idle
    /// Driving the island: every player, no permission needed.
    case active
}

enum IslandState: Int, Comparable, CaseIterable {
    case compact = 0
    case expanded = 1
    case controlCenter = 2
    /// A drag is in flight and the island is offering to catch it.
    case dropZone = 3

    static func < (lhs: IslandState, rhs: IslandState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

final class IslandModel: ObservableObject {

    // MARK: Interaction

    /// Pointer-driven state. Only mutated through the methods below.
    @Published private(set) var state: IslandState = .compact

    /// True while the pointer is inside the island's current shape.
    @Published private(set) var isHovering: Bool = false

    /// When true the island stays open regardless of the pointer. Set by the
    /// "Demo:" menu items so the effect can be filmed without hovering.
    @Published private(set) var isPinned: Bool = false

    // MARK: Content

    /// Ambient content: what is playing, if anything.
    @Published private(set) var nowPlaying: NowPlaying?

    /// Momentary takeover: volume / brightness / power.
    @Published private(set) var transient: TransientKind?

    /// Latest power reading, shown in the control center.
    @Published var power: PowerSnapshot?

    /// Latest brightness reading, shown in the control center.
    @Published var brightness: Double?

    /// Latest output volume, shown in the control center.
    @Published var volume: Double?

    /// The running countdown, if any.
    @Published var countdown: CountdownState?

    /// Connected Bluetooth audio devices that report a battery level.
    @Published var devices: [BluetoothDevice] = []

    /// Whether the camera or microphone is in use anywhere on the system.
    @Published var privacy: PrivacyState = .idle

    /// The next thing on the calendar, when the module is on and permitted.
    @Published var upcomingEvent: UpcomingEvent?

    /// Whether the calendar module may read events.
    @Published var calendarAccess: CalendarAccess = .notDetermined


    /// Whether we may read notification banners (Accessibility).
    @Published var notificationsTrusted: Bool = false

    /// How Now Playing is currently being read, so Settings can say whether the
    /// system-wide route is in play or the app is on its two-player fallback.
    @Published var mediaRemote: MediaRemoteStatus = .unavailable

    /// Whether the media-key event tap is allowed to run. Same Accessibility
    /// grant as the notification mirror — macOS trusts the process, not the
    /// feature — but tracked separately so Settings can explain each one.
    @Published var mediaKeysTrusted: Bool = false

    /// What the banner parser last understood, shown in Settings so a misread
    /// can be reported rather than guessed at.
    @Published var lastNotification: IslandNotification?

    /// A download in flight, if any.
    @Published var download: DownloadActivity?

    /// Bumped a couple of times a second while a track is playing, so the
    /// progress bar redraws. `elapsedNow` is computed from the clock rather than
    /// stored, so without something to invalidate the view it would sit still.
    @Published private(set) var mediaTick: UInt32 = 0

    func tickMedia() { mediaTick &+= 1 }

    /// Files parked on the shelf.
    @Published var shelf: [ShelfItem] = [] {
        didSet {
            // A selection that outlives the file it pointed at would make the
            // footer act on nothing. Prune rather than clear, so removing one
            // chip doesn't drop a selection built up across several.
            let ids = Set(shelf.map(\.id))
            let pruned = shelfSelection.intersection(ids)
            if pruned != shelfSelection { shelfSelection = pruned }
        }
    }

    /// Shelf items picked out by ⌘- or ⇧-click, held by path.
    ///
    /// Transient interaction state, so it lives here and not in `FileShelf`:
    /// closing the island forgets it, exactly like a Finder window's selection
    /// does not survive being closed.
    @Published var shelfSelection: Set<String> = []

    /// True while a file drag is close enough that the island is offering to
    /// catch it.
    @Published var isDropTargeting: Bool = false

    /// True once the drag is actually over the drop zone, for the "let go now"
    /// highlight.
    @Published var isDropHighlighted: Bool = false

    /// How many files the in-flight drag carries, for the drop zone's label.
    @Published var droppedFileCount: Int = 0

    /// Whether we may script the active player. Detection works without it;
    /// artwork and the transport buttons do not.
    @Published var automationStatus: AutomationStatus = .unknown

    /// Control under the pointer, if any. Supplied by the controller's pointer
    /// sampling, since the island cannot rely on SwiftUI hover.
    @Published var hoveredControl: IslandControl?

    /// The SYSTEM tiles currently worth showing, in a fixed order. Both the view
    /// and the hit testing read this, so they always agree on how many there are.
    var systemTiles: [SystemTile] {
        var tiles: [SystemTile] = []
        if volume != nil { tiles.append(.volume) }
        if brightness != nil { tiles.append(.brightness) }
        if power != nil { tiles.append(.battery) }
        // Only worth a tile when there is a level to show.
        if devices.contains(where: { $0.headline != nil }) { tiles.append(.bluetooth) }
        return tiles
    }

    /// What the expanded island is showing, which decides how wide it gets.
    var expandedPayloadKind: ExpandedPayloadKind {
        switch transient {
        case .volume, .brightness:               return .meter
        case .power, .device, .timerFinished, .event, .notification, .download: return .wide
        case nil:                                break
        }
        if countdown != nil { return .countdown }
        if nowPlaying != nil { return .nowPlaying }
        return .quickStats(chips: [power != nil, volume != nil, brightness != nil]
            .filter { $0 }.count)
    }

    /// What the island actually draws, and what the hit region is measured from.
    @Published private(set) var renderedState: IslandState = .compact

    /// What flanks the notch while the island is compact.
    ///
    /// Leading is identity (what this is), trailing is the live value (what it
    /// is doing). An active camera or microphone outranks album art for the
    /// leading slot: knowing you are being recorded matters more than knowing
    /// what is playing.
    var compactAccessories: CompactAccessories {
        let privacyAccessory: CompactAccessory? = privacy.isActive
            ? .privacy(camera: privacy.cameraActive, microphone: privacy.microphoneActive)
            : nil

        var leading: CompactAccessory?
        var trailing: CompactAccessory?

        if let track = nowPlaying {
            leading = .artwork(track.artwork)
            trailing = countdown.map { .countdown($0.text) }
                ?? .waveform(playing: track.isPlaying, palette: track.palette)
        } else if let countdown {
            leading = .timerGlyph
            trailing = .countdown(countdown.text)
        }

        // A download in flight takes the *leading* slot — the same side the
        // album cover uses — so the pill grows to the left of the camera and the
        // glyph has room. It outranks the shelf there: one is happening now, the
        // other is just sitting there. If the cover already holds that side, the
        // trailing slot will do.
        if download != nil {
            if leading == nil { leading = .download }
            else if trailing == nil { trailing = .download }
        }

        if leading == nil, !shelf.isEmpty {
            leading = .shelf(count: shelf.count)
        }

        if let privacyAccessory {
            if leading == nil { leading = privacyAccessory }
            else if trailing == nil { trailing = privacyAccessory }
            else { leading = privacyAccessory }
        }

        return CompactAccessories(leading: leading, trailing: trailing)
    }

    // MARK: Wiring

    /// Set by the controller; forwards transport taps to the active player.
    var onTransport: ((TransportCommand) -> Void)?

    /// Set by the controller; forwards timer presses to the countdown.
    var onTimerAction: ((TimerAction) -> Void)?

    /// Set by the controller; forwards shelf presses.
    var onShelfAction: ((ShelfAction) -> Void)?

    /// Seconds to wait before collapsing once the pointer leaves. Kept in sync
    /// with AppState by the controller.
    var autoCollapseDelay: TimeInterval = 2.0


    /// How long a "Demo:" menu action holds the island open. Long enough to
    /// start a screen recording, short enough that a stray click doesn't leave
    /// the island stuck open looking like a hang.
    private static let demoPinDuration: TimeInterval = 8

    private var collapseWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var pinWork: DispatchWorkItem?

    // MARK: Pointer

    /// Called by the controller whenever the pointer enters or leaves the
    /// island's current rect.
    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering

        if hovering {
            // A real hover takes over from a demo pin.
            unpin()
            cancelCollapse()
            if state == .compact { state = .expanded }
        } else {
            scheduleCollapse()
        }
        updateRenderedState()
    }

    // MARK: Click

    /// Click on the island: open the control center, or close it again.
    func toggleControlCenter() {
        cancelCollapse()
        if state == .controlCenter {
            isPinned = false
            state = isHovering ? .expanded : .compact
        } else {
            state = .controlCenter
            // The control center is a deliberate choice; drop any HUD under it.
            clearTransient()
        }
        if !isHovering { scheduleCollapse() }
        updateRenderedState()
    }

    func transport(_ command: TransportCommand) {
        onTransport?(command)
    }

    func timerAction(_ action: TimerAction) {
        onTimerAction?(action)
    }

    func shelfAction(_ action: ShelfAction) {
        onShelfAction?(action)
    }

    /// Offer to catch a drag, or stop offering.
    func setDropTargeting(_ targeting: Bool, highlighted: Bool = false) {
        if isDropTargeting != targeting { isDropTargeting = targeting }
        let highlight = targeting && highlighted
        if isDropHighlighted != highlight { isDropHighlighted = highlight }
        updateRenderedState()
    }

    /// What a shelf-wide action should act on: the selection when there is one,
    /// otherwise the whole shelf. "Copy" with three chips picked out has an
    /// obvious meaning, and the same word with nothing picked out has another.
    var effectiveShelfItems: [ShelfItem] {
        guard !shelfSelection.isEmpty else { return shelf }
        return shelf.filter { shelfSelection.contains($0.id) }
    }

    func toggleShelfSelection(index: Int) {
        guard shelf.indices.contains(index) else { return }
        let id = shelf[index].id
        if shelfSelection.contains(id) { shelfSelection.remove(id) }
        else { shelfSelection.insert(id) }
    }

    /// Which optional control-center sections are showing.
    func sections(timerEnabled: Bool) -> ControlCenterSections {
        ControlCenterSections(calendar: upcomingEvent != nil,
                              timer: timerEnabled,
                              shelf: !shelf.isEmpty,
                              mediaProgress: nowPlaying?.hasProgress ?? false)
    }

    // MARK: Demo actions (menu bar)

    func demoExpand() {
        cancelCollapse()
        pin()
        state = .expanded
        updateRenderedState()
    }

    func demoToggleControlCenter() {
        cancelCollapse()
        if state == .controlCenter {
            unpin()
            state = .compact
        } else {
            pin()
            state = .controlCenter
        }
        updateRenderedState()
    }

    /// Keep the island open regardless of the pointer, for as long as something
    /// else owns the interaction.
    ///
    /// A right-click menu is the case this exists for: `NSMenu.popUp` runs its
    /// own event loop, so the pointer sampling stops, the island reads that as
    /// "the pointer left" and collapses out from under the menu that belongs to
    /// it. Unlike `pin()` this has no timeout — the caller says when it is over.
    func holdOpen(_ holding: Bool) {
        if holding {
            cancelCollapse()
            pinWork?.cancel()
            pinWork = nil
            isPinned = true
        } else {
            isPinned = false
            if !isHovering { scheduleCollapse() }
        }
    }

    private func pin() {
        isPinned = true
        pinWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPinned else { return }
            self.isPinned = false
            if !self.isHovering { self.scheduleCollapse() }
        }
        pinWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.demoPinDuration, execute: work)
    }

    private func unpin() {
        pinWork?.cancel()
        pinWork = nil
        isPinned = false
    }

    func collapse() {
        // A selection is scoped to the open panel; leaving and coming back
        // should not find three chips still lit from ten minutes ago.
        if !shelfSelection.isEmpty { shelfSelection.removeAll() }
        cancelCollapse()
        unpin()
        state = .compact
        updateRenderedState()
    }

    // MARK: Content updates

    func updateNowPlaying(_ track: NowPlaying?) {
        guard track != nowPlaying else { return }
        nowPlaying = track
    }

    /// Show a system event on the island for a moment.
    func present(_ kind: TransientKind) {
        // Never interrupt a control center the user opened themselves.
        guard state != .controlCenter else { return }

        transient = kind
        updateRenderedState()

        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clearTransient() }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + kind.dwell, execute: work)
    }

    private func clearTransient() {
        transientWork?.cancel()
        transientWork = nil
        guard transient != nil else { return }
        transient = nil
        updateRenderedState()
    }

    // MARK: Derived state

    private func updateRenderedState() {
        let resolved: IslandState
        if isDropTargeting {
            // A drag in flight outranks everything: it is the only state with a
            // deadline attached to it.
            resolved = .dropZone
        } else if state == .controlCenter {
            resolved = .controlCenter
        } else if transient != nil {
            resolved = .expanded
        } else {
            resolved = state
        }
        if resolved != renderedState { renderedState = resolved }
    }

    // MARK: Auto-collapse

    private func scheduleCollapse() {
        cancelCollapse()
        guard !isPinned, state != .compact else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering, !self.isPinned else { return }
            self.state = .compact
            self.updateRenderedState()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, autoCollapseDelay), execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }
}
