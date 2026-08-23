//
//  IslandController.swift
//  DynamicIsland
//
//  Wires the panel ⇄ the model ⇄ the settings ⇄ the system monitors together:
//
//    • builds the OverlayPanel and its PassthroughHostingView,
//    • recomputes the notch geometry whenever the display configuration or the
//      relevant settings change, and repositions the panel,
//    • keeps the hit region in sync with the island's current state, and makes
//      the panel inert whenever the pointer is elsewhere,
//    • drives hover by sampling the pointer,
//    • starts and stops the Phase-2 monitors as their settings are toggled, and
//      routes their events onto the island.
//
//  Why sample the pointer instead of using a tracking area / `.onHover`: the
//  panel is `.nonactivatingPanel` and usually sits behind another app's focus.
//  Tracking areas are unreliable there, whereas `NSEvent.mouseLocation` is a
//  plain geometry read — no event tap, no Accessibility or Input Monitoring
//  permission.
//

import AppKit
import SwiftUI
import Combine

final class IslandController {

    private let appState: AppState
    private let model: IslandModel
    private let layoutStore: IslandLayoutStore

    private let panel: OverlayPanel
    private let hostingView: PassthroughHostingView<IslandView>

    private let volumeMonitor = VolumeMonitor()
    private let brightnessMonitor = BrightnessMonitor()
    private let batteryMonitor = BatteryMonitor()
    private let nowPlayingMonitor = NowPlayingMonitor()
    private let bluetoothMonitor = BluetoothMonitor()
    private let privacyMonitor = PrivacyMonitor()
    private let countdown = IslandTimer()
    private let dragMonitor = DragMonitor()
    private let shelf = FileShelf()
    private let calendarMonitor = CalendarMonitor()
    private let notificationMonitor = NotificationMonitor()
    private let mediaKeyMonitor = MediaKeyMonitor()
    private let downloadMonitor = DownloadMonitor()
    private let fullscreenDetector = FullscreenDetector()

    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?

    /// Previous sample's button state, so a press can be spotted as an edge.
    private var wasButtonDown = false

    /// True while a full-screen app owns the island's display. The panel is
    /// ordered out entirely rather than made transparent — an invisible window
    /// is still composited over every frame of whatever is playing.
    private var isHiddenForFullscreen = false

    /// Pointer samples since the progress bar was last nudged.
    private var progressTickCounter = 0

    /// The sampler runs at ~16 Hz; every fourth pass is ~4 Hz, which is smooth
    /// for a bar this size and far cheaper than redrawing on every sample.
    private static let progressTickEvery = 4

    /// How often the pointer is sampled. ~16 Hz is plenty to feel instant and is
    /// cheap enough to leave running.
    private static let hoverSampleInterval: TimeInterval = 0.06

    /// The compact pill sits exactly on the notch, where there is nothing to aim
    /// at, so hovering is forgiving well beyond the island's outline. Pressing is
    /// not: a click in this margin still belongs to whatever is underneath.
    private static let hoverMargin = CGSize(width: 12, height: 8)

    init(appState: AppState, model: IslandModel) {
        self.appState = appState
        self.model = model

        let metrics = NotchDetector.detect(size: appState.islandSize,
                                           preference: appState.preferredDisplay)
        let layout = IslandLayout(metrics: metrics,
                                  size: appState.islandSize,
                                  sections: ControlCenterSections(calendar: false,
                                                                  timer: appState.timerEnabled,
                                                                  shelf: !shelf.items.isEmpty),
                                  expandedPayload: .quickStats(chips: 0))
        self.layoutStore = IslandLayoutStore(layout: layout)

        self.panel = OverlayPanel(contentRect: layout.panelFrame)
        self.hostingView = PassthroughHostingView(
            rootView: IslandView(settings: appState, model: model, layoutStore: layoutStore)
        )

        model.autoCollapseDelay = appState.autoCollapseDelay

        hostingView.onClick = { [weak model] in model?.toggleControlCenter() }
        hostingView.onControl = { [weak self] control in
            guard let model = self?.model else { return }
            switch control {
            case let .transport(command): model.transport(command)
            case let .timer(action):      model.timerAction(action)
            case let .shelf(action):      model.shelfAction(action)
            case .artwork:                self?.openNowPlayingApp()
            // Value controls act on press and drag, not on the click.
            case .tile, .seek:            break
            }
        }
        hostingView.onScrub = { [weak self] control, value in self?.scrub(control, to: value) }
        hostingView.onContextMenu = { [weak self] control, point in
            self?.showContextMenu(for: control, at: point)
        }
        model.onTimerAction = { [weak self] action in self?.runTimer(action) }
        model.onShelfAction = { [weak self] action in self?.runShelf(action) }

        shelf.onChange = { [weak self] items in
            self?.model.shelf = items
            // A shelf appearing or emptying changes the control center's height.
            self?.refreshGeometry()
            self?.updateHitRegion()
        }
        model.shelf = shelf.items

        hostingView.onDragTargeting = { [weak self] targeting in
            self?.model.setDropTargeting(self?.dragMonitor.isDraggingFiles ?? targeting,
                                         highlighted: targeting)
        }
        hostingView.onDrop = { [weak self] urls in
            self?.shelf.add(urls)
            self?.model.setDropTargeting(false)
        }
        hostingView.draggableFile = { [weak self] point in self?.shelfFile(at: point) }
        hostingView.onDragOutChange = { [weak self] dragging in
            guard let self else { return }
            // Our own drag must never arm the island as a drop target, and the
            // control center has to stay put so the chip the user grabbed is
            // still under the pointer.
            if dragging {
                self.dragMonitor.onChange = nil
                self.model.setDropTargeting(false)
            }
            self.model.holdOpen(dragging)
            if !dragging { self.configureMonitors() }
        }

        dragMonitor.onChange = { [weak self] dragging in
            guard let self else { return }
            self.model.droppedFileCount = dragging ? self.dragMonitor.draggedURLs().count : 0
            self.model.setDropTargeting(dragging)
            self.updateHitRegion()
        }
        hostingView.frame = CGRect(origin: .zero, size: layout.panelFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setFrame(layout.panelFrame, display: true)
        panel.orderFrontRegardless()

        fullscreenDetector.onChange = { [weak self] fullscreen in
            self?.setHiddenForFullscreen(fullscreen)
        }

        observeSettings()
        observeState()
        observeScreens()
        configureMonitors()
        startHoverSampling()

        updateHitRegion()
    }

    deinit {
        hoverTimer?.invalidate()
        volumeMonitor.stop()
        brightnessMonitor.stop()
        batteryMonitor.stop()
        nowPlayingMonitor.stop()
        calendarMonitor.stop()
        notificationMonitor.stop()
        bluetoothMonitor.stop()
        privacyMonitor.stop()
        mediaKeyMonitor.stop()
        downloadMonitor.stop()
        fullscreenDetector.stop()
        countdown.cancel()
    }

    // MARK: Observation

    private func observeSettings() {
        // objectWillChange fires *before* the property is updated, so hop to the
        // next runloop pass to read the new value.
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)
    }

    private func observeState() {
        model.$renderedState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.updateHitRegion(for: state) }
            .store(in: &cancellables)

        // Accessories change the compact pill's width, so the hit region has to
        // follow whatever puts something beside the notch.
        model.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHitRegion() }
            .store(in: &cancellables)

        model.$countdown
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHitRegion() }
            .store(in: &cancellables)

        // The expanded island is sized to whatever it is showing, so a payload
        // change is a geometry change.
        model.$transient
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshGeometry()
                self?.updateHitRegion()
            }
            .store(in: &cancellables)

        model.$privacy
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHitRegion() }
            .store(in: &cancellables)

        model.$download
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHitRegion() }
            .store(in: &cancellables)
    }

    private func observeScreens() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshGeometry() }
            .store(in: &cancellables)
    }

    private func settingsChanged() {
        model.autoCollapseDelay = appState.autoCollapseDelay
        refreshGeometry()
        configureMonitors()
    }

    // MARK: Monitors

    /// Start or stop each monitor to match its setting. Safe to call repeatedly:
    /// every monitor's start/stop is idempotent.
    private func configureMonitors() {
        volumeMonitor.snapsToFivePercent = appState.snapLevelsToFivePercent
        brightnessMonitor.snapsToFivePercent = appState.snapLevelsToFivePercent

        if appState.volumeEnabled {
            volumeMonitor.onChange = { [weak self] level, muted in
                self?.model.volume = level
                self?.model.present(.volume(level: level, muted: muted))
            }
            volumeMonitor.start()
            model.volume = volumeMonitor.currentLevel()

            // Put the level on the grid once at launch, so it doesn't sit at an
            // odd number until the user happens to touch it. Brightness is left
            // alone: ambient adjustment moves it off the grid all day anyway,
            // and the reading should stay honest.
            if appState.snapLevelsToFivePercent,
               let level = model.volume, !level.isOnFivePercentGrid {
                volumeMonitor.setLevel(level)
                model.volume = level.snappedToFivePercent
            }
        } else {
            volumeMonitor.stop()
            model.volume = nil
        }

        if appState.brightnessEnabled {
            brightnessMonitor.onChange = { [weak self] level, userInitiated in
                self?.model.brightness = level
                guard userInitiated else { return }
                self?.model.present(.brightness(level: level))
            }
            brightnessMonitor.start()
            model.brightness = brightnessMonitor.currentLevel()
        } else {
            brightnessMonitor.stop()
            model.brightness = nil
        }

        if appState.batteryEnabled {
            batteryMonitor.onPowerEvent = { [weak self] snapshot, event in
                self?.model.power = snapshot
                self?.model.present(.power(snapshot, event))
            }
            batteryMonitor.start()
            model.power = batteryMonitor.snapshot
        } else {
            batteryMonitor.stop()
            model.power = nil
        }

        if appState.musicEnabled {
            nowPlayingMonitor.onChange = { [weak self] track in
                self?.model.updateNowPlaying(track)
            }
            nowPlayingMonitor.onAutomationStatusChange = { [weak self] status in
                self?.model.automationStatus = status
            }
            nowPlayingMonitor.onMediaRemoteStatusChange = { [weak self] status in
                self?.model.mediaRemote = status
                // The media row grows a scrubber once elapsed time arrives.
                self?.refreshGeometry()
                self?.updateHitRegion()
            }
            model.onTransport = { [weak self] command in
                self?.nowPlayingMonitor.send(command)
            }
            nowPlayingMonitor.start()
            model.mediaRemote = nowPlayingMonitor.mediaRemoteStatus
        } else {
            nowPlayingMonitor.stop()
            model.onTransport = nil
            model.automationStatus = .unknown
            model.mediaRemote = .unavailable
        }

        if appState.timerEnabled {
            countdown.onChange = { [weak self] state in self?.model.countdown = state }
            countdown.onFinished = { [weak self] duration in self?.timerFinished(duration) }
        } else {
            countdown.cancel()
            model.countdown = nil
        }

        if appState.bluetoothEnabled {
            bluetoothMonitor.onChange = { [weak self] devices in self?.model.devices = devices }
            bluetoothMonitor.onConnect = { [weak self] device in
                guard device.hasBattery else { return }
                self?.model.present(.device(device))
            }
            bluetoothMonitor.start()
            model.devices = bluetoothMonitor.devices
        } else {
            bluetoothMonitor.stop()
            model.devices = []
        }

        if appState.notificationsEnabled {
            notificationMonitor.onNotification = { [weak self] notification in
                self?.model.lastNotification = notification
                self?.model.present(.notification(notification))
            }
            notificationMonitor.onTrustChange = { [weak self] trusted in
                self?.model.notificationsTrusted = trusted
            }
            notificationMonitor.start()
            model.notificationsTrusted = notificationMonitor.isTrusted
        } else {
            notificationMonitor.stop()
            model.notificationsTrusted = false
            model.lastNotification = nil
        }

        if appState.calendarEnabled {
            calendarMonitor.onChange = { [weak self] event in
                self?.model.upcomingEvent = event
                self?.refreshGeometry()
                self?.updateHitRegion()
            }
            calendarMonitor.onAccessChange = { [weak self] access in
                self?.model.calendarAccess = access
            }
            calendarMonitor.onImminent = { [weak self] event in
                self?.model.present(.event(event))
            }
            calendarMonitor.start()
            model.calendarAccess = calendarMonitor.access
        } else {
            calendarMonitor.stop()
            model.upcomingEvent = nil
            model.calendarAccess = .notDetermined
        }

        if appState.shelfEnabled {
            dragMonitor.onChange = { [weak self] dragging in
                guard let self else { return }
                self.model.droppedFileCount = dragging ? self.dragMonitor.draggedURLs().count : 0
                self.model.setDropTargeting(dragging)
                self.updateHitRegion()
            }
        } else {
            dragMonitor.onChange = nil
            model.setDropTargeting(false)
        }

        if appState.privacyEnabled {
            privacyMonitor.onChange = { [weak self] state in self?.model.privacy = state }
            privacyMonitor.start()
            model.privacy = privacyMonitor.state
        } else {
            privacyMonitor.stop()
            model.privacy = .idle
        }

        if appState.downloadsEnabled {
            downloadMonitor.onChange = { [weak self] activity in
                self?.model.download = activity
                // The glyph changes the compact pill's width.
                self?.updateHitRegion()
            }
            downloadMonitor.onComplete = { [weak self] activity in
                self?.model.present(.download(activity))
            }
            downloadMonitor.start()
            model.download = downloadMonitor.activity
        } else {
            downloadMonitor.stop()
            model.download = nil
        }

        if appState.mediaKeysEnabled {
            mediaKeyMonitor.onKey = { [weak self] key, precise in
                self?.handleMediaKey(key, precise: precise) ?? false
            }
            mediaKeyMonitor.onTrustChange = { [weak self] trusted in
                self?.model.mediaKeysTrusted = trusted
            }
            mediaKeyMonitor.start()
            model.mediaKeysTrusted = mediaKeyMonitor.isTrusted
        } else {
            mediaKeyMonitor.stop()
            model.mediaKeysTrusted = false
        }

        if appState.hideWhenFullscreen {
            fullscreenDetector.screen = NotchDetector.preferredScreen(appState.preferredDisplay)
            fullscreenDetector.start()
        } else {
            fullscreenDetector.stop()
            setHiddenForFullscreen(false)
        }

        panel.setHiddenFromCapture(appState.hideInScreenshots)
    }

    // MARK: Media keys

    /// Apply a key the monitor swallowed. Returning false hands it back to the
    /// system, which is the only correct answer when we can't do the job — a
    /// key that disappears without changing anything is worse than the system
    /// HUD we were trying to avoid.
    private func handleMediaKey(_ key: MediaKey, precise: Bool) -> Bool {
        switch key {
        case .volumeUp, .volumeDown:
            guard appState.volumeEnabled else { return false }
            return volumeMonitor.step(up: key == .volumeUp, precise: precise)

        case .mute:
            guard appState.volumeEnabled else { return false }
            volumeMonitor.toggleMute()
            return true

        case .brightnessUp, .brightnessDown:
            guard appState.brightnessEnabled else { return false }
            return brightnessMonitor.step(up: key == .brightnessUp, precise: precise)
        }
    }

    /// Bring the app the current track is coming from to the front.
    ///
    /// Works for anything MediaRemote surfaces, not just the two scriptable
    /// players: `Source.bundleIdentifier` carries the real identifier for
    /// `.other`, so a track playing in a browser opens that browser.
    private func openNowPlayingApp() {
        guard let source = model.nowPlaying?.source,
              let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: source.bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)

        // The island has done its job; leaving it open over the app the user
        // just asked to see would be in the way.
        model.collapse()
    }

    /// Raise the Accessibility prompt for media-key interception.
    func requestMediaKeyAccess() {
        mediaKeyMonitor.requestAccess()
    }

    // MARK: Full screen

    private func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = hidden

        if hidden {
            // Put the island away in its resting state, so it doesn't come back
            // mid-expansion when the film ends.
            model.collapse()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Bring the panel forward unless a full-screen app currently owns the
    /// display. Every `orderFrontRegardless` goes through here, or a geometry
    /// refresh would pop the island back over a film.
    private func showPanel() {
        guard !isHiddenForFullscreen else { return }
        panel.orderFrontRegardless()
    }

    /// Index of the shelf chip under the pointer, so its remove badge gets a
    /// hit rect of its own.
    private var hoveredShelfIndex: Int? {
        if case let .shelf(.open(index)) = model.hoveredControl { return index }
        if case let .shelf(.remove(index)) = model.hoveredControl { return index }
        return nil
    }

    /// The file under the pointer, when the pointer is on a shelf chip — this is
    /// what makes a shelved file draggable back out.
    private func shelfFile(at point: CGPoint) -> URL? {
        guard model.renderedState == .controlCenter else { return nil }
        let hit = hostingView.controlHits.first { $0.hitRect.contains(point) }
        guard case let .shelf(.open(index)) = hit?.control,
              model.shelf.indices.contains(index) else { return nil }
        return model.shelf[index].url
    }

    /// Ask the user for calendar access. Called from Settings.
    func requestCalendarAccess() {
        calendarMonitor.requestAccess()
    }

    /// Raise the Accessibility prompt for notification mirroring.
    func requestNotificationAccess() {
        notificationMonitor.requestAccess()
    }

    // MARK: Shelf

    private func runShelf(_ action: ShelfAction) {
        switch action {
        case let .open(index):
            guard shelf.items.indices.contains(index) else { return }
            shelf.open(shelf.items[index])

        case let .remove(index):
            guard shelf.items.indices.contains(index) else { return }
            shelf.remove(shelf.items[index])

        case let .toggleSelection(index):
            model.toggleShelfSelection(index: index)

        // The footer acts on the selection when there is one, and on everything
        // when there isn't — see `IslandModel.effectiveShelfItems`.
        case .copyAll:    shelf.copy(model.effectiveShelfItems)
        case .airDropAll: shelf.airDrop(model.effectiveShelfItems)
        case .clear:
            let target = model.effectiveShelfItems
            // "Clear" with nothing picked out still means the whole shelf.
            if model.shelfSelection.isEmpty { shelf.clear() } else { shelf.remove(target) }
        }
        updateHitRegion()
    }

    // MARK: Context menu

    /// Build and show the right-click menu for whatever is under the pointer.
    ///
    /// The menu is assembled here rather than in the view because it acts on the
    /// shelf, and the shelf lives here. Actions that need a window of their own
    /// (Move's folder prompt) also need the app activated, which is a
    /// controller-level concern.
    private func showContextMenu(for control: IslandControl?, at point: NSPoint) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if case let .shelf(.open(index)) = control, shelf.items.indices.contains(index) {
            appendItemMenu(to: menu, index: index)
        } else if !shelf.items.isEmpty, appState.shelfEnabled {
            appendShelfMenu(to: menu)
        }

        guard !menu.items.isEmpty else { return }

        // Keep the island open underneath the menu; a menu that dismisses the
        // thing it belongs to is unusable. `popUp` runs its own event loop, so
        // this is over by the time it returns.
        //
        // `point` is already in screen space, which is what popUp wants when
        // the view argument is nil.
        model.holdOpen(true)
        menu.popUp(positioning: nil, at: point, in: nil)
        model.holdOpen(false)
    }

    /// The menu for one chip — or for the whole selection, when the chip that
    /// was right-clicked is part of it. Right-clicking inside a selection acting
    /// on just that one item is the behaviour people report as a bug in every
    /// file manager that does it.
    private func appendItemMenu(to menu: NSMenu, index: Int) {
        let item = shelf.items[index]
        let targets = model.shelfSelection.contains(item.id) ? model.effectiveShelfItems : [item]
        let many = targets.count > 1

        add(to: menu, title: many ? Strings.openCount(targets.count) : Strings.open) { [weak self] in
            targets.forEach { self?.shelf.open($0) }
        }
        add(to: menu, title: Strings.revealInFinder) { [weak self] in
            self?.shelf.reveal(targets)
        }
        menu.addItem(.separator())
        add(to: menu, title: Strings.copy) { [weak self] in self?.shelf.copy(targets) }
        add(to: menu, title: Strings.airDropEllipsis) { [weak self] in self?.shelf.airDrop(targets) }
        add(to: menu, title: Strings.moveToEllipsis) { [weak self] in self?.moveShelfItems(targets) }
        menu.addItem(.separator())
        add(to: menu, title: many ? Strings.removeCount(targets.count) : Strings.removeFromShelf) {
            [weak self] in self?.shelf.remove(targets)
        }
    }

    /// The menu for the island's body: whatever the footer offers, plus Move.
    private func appendShelfMenu(to menu: NSMenu) {
        let targets = model.effectiveShelfItems
        guard !targets.isEmpty else { return }

        add(to: menu, title: Strings.copyShelfFiles) { [weak self] in self?.shelf.copy(targets) }
        add(to: menu, title: Strings.airDropShelfFiles) { [weak self] in self?.shelf.airDrop(targets) }
        add(to: menu, title: Strings.moveToEllipsis) { [weak self] in self?.moveShelfItems(targets) }
        menu.addItem(.separator())
        add(to: menu, title: Strings.revealInFinder) { [weak self] in self?.shelf.reveal(targets) }
        menu.addItem(.separator())
        add(to: menu, title: Strings.clearShelf) { [weak self] in self?.shelf.clear() }
    }

    private func add(to menu: NSMenu, title: String, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        let target = MenuAction(action)
        item.target = target
        item.representedObject = target      // menu items don't retain their target
        menu.addItem(item)
    }

    private func moveShelfItems(_ items: [ShelfItem]) {
        shelf.move(items) { [weak self] moved, error in
            guard let self else { return }
            self.model.shelfSelection.subtract(moved.map(\.id))
            self.updateHitRegion()
            if let error { NSApp.presentError(error) }
        }
    }


    // MARK: Timer

    private func runTimer(_ action: TimerAction) {
        switch action {
        case let .start(minutes): countdown.start(minutes: minutes)
        case .toggle:             countdown.toggle()
        case .restart:            countdown.restart()
        case .cancel:             countdown.cancel()
        }
        // Presets and controls swap places, so the hit rects must follow.
        updateHitRegion()
    }

    private func timerFinished(_ duration: TimeInterval) {
        if appState.soundEffectsEnabled {
            // A stock alert rather than a bundled asset: it already matches
            // whatever the user has the system set to.
            NSSound(named: "Glass")?.play()
        }
        model.present(.timerFinished(duration))
        updateHitRegion()
    }

    // MARK: Geometry

    private func refreshGeometry() {
        let metrics = NotchDetector.detect(size: appState.islandSize,
                                           preference: appState.preferredDisplay)

        // A display being plugged in or unplugged reaches us here and *not*
        // through settingsChanged, so the detector has to be re-pointed here or
        // it would keep watching a screen the island has already left.
        if appState.hideWhenFullscreen {
            let screen = NotchDetector.preferredScreen(appState.preferredDisplay)
            if fullscreenDetector.screen !== screen { fullscreenDetector.screen = screen }
        }

        let layout = IslandLayout(metrics: metrics,
                                  size: appState.islandSize,
                                  sections: model.sections(timerEnabled: appState.timerEnabled),
                                  expandedPayload: model.expandedPayloadKind)
        guard layout != layoutStore.layout else { return }

        // The panel only moves when its own frame changes. The layout now also
        // carries what the expanded state is showing, which changes on every
        // volume press — re-ordering the window that often would fight whatever
        // else is on screen for z-order.
        let framedMoved = layout.panelFrame != layoutStore.layout.panelFrame
        layoutStore.layout = layout

        if framedMoved {
            panel.setFrame(layout.panelFrame, display: true)
            showPanel()
        }
        updateHitRegion()
    }

    private func updateHitRegion(for state: IslandState? = nil) {
        let state = state ?? model.renderedState
        // A couple of points of slack makes the compact pill easier to catch.
        hostingView.hitRect = layoutStore.layout
            .globalIslandRect(for: state, accessories: model.compactAccessories)

        // The control center has every control; the hover state has transport,
        // so a track can be skipped without opening anything.
        switch state {
        case .controlCenter:
            hostingView.controlHits = layoutStore.layout.controlHits(
                tiles: model.systemTiles,
                hasMedia: model.nowPlaying != nil,
                countdown: model.countdown,
                shelfCount: model.shelf.count,
                hoveredShelfIndex: hoveredShelfIndex)

        case .expanded where model.nowPlaying != nil && model.transient == nil:
            hostingView.controlHits = layoutStore.layout.expandedControlHits(
                accessories: model.compactAccessories)

        default:
            hostingView.controlHits = []
        }

        if hostingView.controlHits.isEmpty { model.hoveredControl = nil }
    }

    // MARK: Hover

    private func startHoverSampling() {
        let timer = Timer(timeInterval: Self.hoverSampleInterval, repeats: true) { [weak self] _ in
            self?.sampleHover()
        }
        // .common so hovering keeps working while a menu is open or the user is
        // dragging a window around.
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    /// Nudge the progress bar along. Rides the pointer sampler that is already
    /// running rather than adding a second timer, and only fires when a moving
    /// bar is actually on screen — a paused track or a closed island costs
    /// nothing.
    private func tickProgressIfNeeded() {
        progressTickCounter += 1
        guard progressTickCounter >= Self.progressTickEvery else { return }
        progressTickCounter = 0

        guard model.renderedState > .compact,
              let track = model.nowPlaying, track.isPlaying, track.hasProgress
        else { return }
        model.tickMedia()
    }

    /// Apply a dragged value to the system.
    private func scrub(_ control: IslandControl, to value: Double) {
        if case .seek = control {
            model.transport(.seek(fraction: value))
            // Show the new position immediately rather than waiting for the
            // adapter's next update, which can be a beat behind the drag.
            if var track = model.nowPlaying, let duration = track.duration {
                track.elapsed = duration * value.clampedToUnit
                track.elapsedSampledAt = Date()
                model.updateNowPlaying(track)
            }
            return
        }

        guard case let .tile(tile) = control else { return }

        switch tile {
        case .volume:
            volumeMonitor.setLevel(value)
            // The CoreAudio listener will confirm this, but updating now keeps
            // the meter glued to the pointer instead of a frame behind it.
            model.volume = value

        case .brightness:
            brightnessMonitor.setLevel(value)
            model.brightness = value

        case .battery, .bluetooth:
            // Readouts, not controls.
            break
        }
    }

    private func sampleHover() {
        // Nothing to hover while the island is out of the way, and the panel is
        // not even on screen to take the events.
        guard !isHiddenForFullscreen else { return }

        // AppKit owns the mouse for the length of an outgoing drag. Sampling
        // through it would read the held button as somebody else's file drag,
        // and would make the panel inert the moment the pointer left the island
        // — both of which break the drag we started.
        guard !hostingView.isDraggingOut else { return }

        tickProgressIfNeeded()
        hostingView.clearStaleTracking()

        // Arm the panel while a file drag is in flight, so AppKit can deliver
        // the drag to us at all — an inert window refuses drags too.
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if appState.shelfEnabled {
            dragMonitor.sample(buttonDown: buttonDown)
        }

        // A drag owns the island until the button comes up, wherever the pointer
        // goes in the meantime.
        if hostingView.isTracking {
            model.setHovering(true)
            return
        }

        let pointer = NSEvent.mouseLocation
        let island = layoutStore.layout
            .globalIslandRect(for: model.renderedState, accessories: model.compactAccessories)

        let hovering = island
            .insetBy(dx: -Self.hoverMargin.width, dy: -Self.hoverMargin.height)
            .contains(pointer)
        let pressable = island.contains(pointer)

        dismissIfClickedAway(buttonDown: buttonDown, pointerIsOnIsland: hovering)

        // The panel only takes mouse events where the island actually is. Outside
        // that it stays transparent, so the menu bar behind the overlay — and the
        // area the drop shadow bleeds into — keeps working.
        let accepting = pressable || model.isDropTargeting
        if panel.ignoresMouseEvents == accepting {
            panel.ignoresMouseEvents = !accepting
        }

        model.setHovering(hovering)
        sampleHoveredControl(inside: pressable)
    }

    /// Clicking anywhere else puts the island away, rather than making the user
    /// wait out the collapse delay. Detected from the same pointer sampling as
    /// everything else: a press that begins while the pointer is off the island.
    private func dismissIfClickedAway(buttonDown: Bool, pointerIsOnIsland: Bool) {
        defer { wasButtonDown = buttonDown }

        guard buttonDown, !wasButtonDown, !pointerIsOnIsland,
              model.renderedState > .compact,
              // A file drag holds the button down and is not a dismissal.
              !model.isDropTargeting, !hostingView.isTracking
        else { return }

        model.collapse()
    }

    /// Hover highlighting for the transport controls, from the same pointer
    /// sample — SwiftUI's `.onHover` needs tracking areas, which a background
    /// panel cannot depend on.
    private func sampleHoveredControl(inside: Bool) {
        guard inside, !hostingView.controlHits.isEmpty else {
            if model.hoveredControl != nil { model.hoveredControl = nil }
            return
        }

        let pointer = NSEvent.mouseLocation
        let hovered = hostingView.controlHits.first(where: { $0.hitRect.contains(pointer) })?.control
        guard model.hoveredControl != hovered else { return }
        model.hoveredControl = hovered
        // Hovering a shelf chip reveals its remove badge, which needs a hit rect.
        if case .shelf = hovered { updateHitRegion() }
        else if hovered == nil { updateHitRegion() }
    }
}


/// Carries a closure for an NSMenuItem.
///
/// NSMenuItem takes a target/selector pair and does not retain the target, so a
/// plain closure would be gone by the time the menu is clicked. The item holds
/// this object in `representedObject`, which does retain.
final class MenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() { action() }
}
