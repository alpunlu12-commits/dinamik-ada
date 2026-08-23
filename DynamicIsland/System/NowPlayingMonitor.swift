//
//  NowPlayingMonitor.swift
//  DynamicIsland
//
//  Reads what Music.app and Spotify are playing, and sends transport commands
//  back.
//
//  Detection is driven by **distributed notifications**, not by polling:
//  both players broadcast every track and state change system-wide
//  (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`),
//  and the payload already carries the track name, artist, album and player
//  state. That matters for three reasons:
//
//    • It is instant. A polled query only notices a track change on the next
//      tick, which is exactly the "the song doesn't change" symptom.
//    • It needs **no permission at all**. Reading these notifications is not
//      Automation, so the island shows what's playing even if the user never
//      grants anything.
//    • It cannot silently die. An AppleScript-only design fails closed when
//      Automation is denied, and looks identical to "nothing is playing".
//
//  AppleScript is still used, but only for the things notifications can't give
//  us — album artwork, the state of a player that was already running before we
//  launched, and transport commands. Those need Automation permission, which is
//  requested at the moment it is actually needed and whose status is published
//  so the UI can explain itself instead of going quiet.
//
//  MediaRemote — the private framework that exposes system-wide Now Playing,
//  browser media included — was locked to `com.apple.*` processes in macOS 15.4.
//  It is reachable again through the vendored adapter (see MediaRemoteAdapter),
//  which runs it inside Apple's own Perl binary. When that adapter is present
//  and working it *supersedes* everything below: it needs no permission at all,
//  it sees every player rather than two, and it carries elapsed time.
//
//  The notification + AppleScript path is kept as the fallback for the two cases
//  that matter: a build with no vendored adapter (a fresh clone), and an adapter
//  that stops working because Apple closed the route. `preferAdapter` is what
//  arbitrates, and it flips at runtime — nothing has to be restarted.
//

import AppKit

/// Whether we may script a given player.
enum AutomationStatus: Equatable {
    case unknown
    case notRunning
    case granted
    case denied

    var isGranted: Bool { self == .granted }
}

final class NowPlayingMonitor {

    /// Called on the main queue whenever the track, artwork or play state changes.
    var onChange: ((NowPlaying?) -> Void)?

    /// Called on the main queue when the Automation permission picture changes.
    var onAutomationStatusChange: ((AutomationStatus) -> Void)?

    /// Called on the main queue when the Now Playing route changes.
    var onMediaRemoteStatusChange: ((MediaRemoteStatus) -> Void)?

    var mediaRemoteStatus: MediaRemoteStatus {
        guard adapter.isAvailable else { return .unavailable }
        return preferAdapter ? .active : .idle
    }

    private let scriptQueue = DispatchQueue(label: "com.abacusisland.dynamicisland.applescript")

    /// The system-wide route. Inert unless the vendored files are in the bundle.
    private let adapter = MediaRemoteAdapter()

    /// True while the adapter is producing data. Everything the fallback path
    /// publishes is suppressed while this holds, so the two can never fight over
    /// the island.
    private var preferAdapter = false

    /// Artwork decoded from the adapter's bytes, kept per track so a diff that
    /// doesn't repeat the artwork doesn't blank the cover.
    private var adapterArtwork: (key: String, image: NSImage?)?

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?

    /// Last known track per player, so two running players can be arbitrated.
    private var known: [NowPlaying.Source: NowPlaying] = [:]
    private var published: NowPlaying?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkInFlight: Set<String> = []

    private var automationStatus: AutomationStatus = .unknown {
        didSet {
            guard automationStatus != oldValue else { return }
            let status = automationStatus
            DispatchQueue.main.async { [weak self] in self?.onAutomationStatusChange?(status) }
        }
    }

    /// Safety net only — notifications do the real work. A player that was
    /// already running when we launched has not broadcast anything yet, and a
    /// notification can be missed if the player was launched mid-flight.
    private static let refreshInterval: TimeInterval = 5.0

    /// Deterministic arbitration: Music is the system player, so it wins ties.
    private static let priority: [NowPlaying.Source] = [.music, .spotify]

    // MARK: Lifecycle

    func start() {
        guard distributedObservers.isEmpty else { return }

        // The adapter is tried first and, if it works, wins. Its callbacks are
        // wired before the fallback starts so a fast adapter can suppress the
        // fallback's first publish rather than flickering past it.
        adapter.onAvailabilityChange = { [weak self] running in
            guard let self else { return }
            self.preferAdapter = running
            self.onMediaRemoteStatusChange?(self.mediaRemoteStatus)
            if running {
                // Automation is not needed on this path; say so rather than
                // leaving Settings claiming a permission is missing.
                self.automationStatus = .granted
            } else {
                // Adapter died — hand the island back to the fallback.
                self.adapterArtwork = nil
                self.refresh(askForPermission: false)
            }
        }
        adapter.onChange = { [weak self] state in
            self?.handleAdapter(state)
        }
        adapter.start()

        observeDistributed("com.apple.Music.playerInfo", source: .music)
        // Music still answers to its old name on some systems.
        observeDistributed("com.apple.iTunes.playerInfo", source: .music)
        observeDistributed("com.spotify.client.PlaybackStateChanged", source: .spotify)

        // Forget a player's track the moment it quits, rather than leaving a
        // ghost on the island until something else happens.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let source = NowPlaying.Source.scriptable.first(where: { $0.bundleIdentifier == app.bundleIdentifier })
            else { return }
            self?.known[source] = nil
            self?.publishBest()
        })

        // Pick up anything already playing, prompting for Automation once if a
        // player is running — this is the moment the permission is genuinely
        // needed, and macOS only shows the prompt the first time.
        refresh(askForPermission: true)

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh(askForPermission: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        adapter.stop()
        preferAdapter = false
        adapterArtwork = nil

        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        refreshTimer?.invalidate()
        refreshTimer = nil

        known.removeAll()
        if published != nil {
            published = nil
            onChange?(nil)
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: Distributed notifications

    private func observeDistributed(_ name: String, source: NowPlaying.Source) {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(name),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handle(note, from: source)
        }
        distributedObservers.append(observer)
    }

    /// Both players use the same iTunes-derived userInfo keys.
    private func handle(_ note: Notification, from source: NowPlaying.Source) {
        guard let info = note.userInfo else { return }

        let state = (info["Player State"] as? String) ?? ""
        guard state != "Stopped" else {
            known[source] = nil
            publishBest()
            return
        }

        let title = (info["Name"] as? String) ?? ""
        guard !title.isEmpty else { return }

        var track = NowPlaying(source: source,
                               title: title,
                               artist: (info["Artist"] as? String) ?? "",
                               isPlaying: state == "Playing",
                               artwork: nil)
        track.artwork = artworkCache[track.trackKey]

        known[source] = track
        publishBest()

        if track.artwork == nil { fetchArtwork(for: track) }
    }

    // MARK: MediaRemote adapter

    /// Whether the vendored adapter is present in this build at all.
    var isAdapterAvailable: Bool { adapter.isAvailable }

    /// Whether it is the thing currently driving the island.
    var isUsingAdapter: Bool { preferAdapter }

    private func handleAdapter(_ state: MediaRemoteState?) {
        guard let state else {
            adapterArtwork = nil
            deliver(nil)
            return
        }

        let source = NowPlaying.Source.from(bundleIdentifier: state.bundleIdentifier)
        var track = NowPlaying(source: source,
                               title: state.title,
                               artist: state.artist ?? "",
                               isPlaying: state.isPlaying,
                               artwork: nil,
                               duration: state.duration,
                               elapsed: state.elapsed,
                               elapsedSampledAt: state.elapsedSampledAt,
                               playbackRate: state.playbackRate)

        // Artwork arrives as bytes on a track change and is simply absent from
        // the diffs in between, so decode once per track and reuse it. Decoding
        // a few hundred kilobytes of PNG on every position update would be the
        // most expensive thing this app does.
        if let data = state.artworkData {
            let image = NSImage(data: data)
            adapterArtwork = (track.trackKey, image)
            track.artwork = image
        } else if let cached = adapterArtwork, cached.key == track.trackKey {
            track.artwork = cached.image
        } else {
            adapterArtwork = nil
        }

        deliver(track)
    }

    // MARK: Publishing

    private func publishBest() {
        // While the adapter is driving, the fallback is a second opinion nobody
        // asked for: it sees fewer players and has no elapsed time, so letting
        // it publish would replace a full row with a poorer one.
        guard !preferAdapter else { return }

        let candidates = Self.priority.compactMap { known[$0] }
        let best = candidates.first(where: \.isPlaying) ?? candidates.first
        deliver(best)
    }

    private func deliver(_ value: NowPlaying?) {
        guard value != published else { return }
        published = value
        onChange?(value)
    }

    // MARK: AppleScript refresh (initial state / safety net)

    private func refresh(askForPermission: Bool) {
        let running = runningSources()

        // Drop players that are no longer around.
        for source in known.keys where !running.contains(source) {
            known[source] = nil
        }

        guard !running.isEmpty else {
            automationStatus = .notRunning
            publishBest()
            return
        }

        scriptQueue.async { [weak self] in
            guard let self else { return }

            var best: AutomationStatus = .notRunning
            for source in running {
                let status = Self.automationStatus(for: source, askUserIfNeeded: askForPermission)
                if status == .granted { best = .granted }
                else if status == .denied, best != .granted { best = .denied }

                guard status.isGranted, let track = self.read(from: source) else { continue }

                DispatchQueue.main.async {
                    var fresh = track
                    fresh.artwork = self.artworkCache[track.trackKey] ?? track.artwork

                    let existing = self.known[source]
                    let sameTrack = existing?.trackKey == fresh.trackKey
                        && existing?.isPlaying == fresh.isPlaying

                    guard sameTrack, var current = existing else {
                        self.known[source] = fresh
                        self.publishBest()
                        if fresh.artwork == nil { self.fetchArtwork(for: fresh) }
                        return
                    }

                    // Same track, same state — but the *playhead* still has to
                    // come through. It used to not: this branch simply returned,
                    // so a track first seen through a notification (which
                    // carries no timing) never gained a duration, `hasProgress`
                    // stayed false and the scrubber never appeared at all.
                    //
                    // Notifications remain the source of truth for title,
                    // artist and play state; the script owns only the timing.
                    current.duration = fresh.duration
                    current.elapsed = fresh.elapsed
                    current.elapsedSampledAt = fresh.elapsedSampledAt
                    current.playbackRate = fresh.playbackRate

                    guard current != existing else { return }
                    self.known[source] = current
                    self.publishBest()
                }
            }

            DispatchQueue.main.async { self.automationStatus = best }
        }
    }

    private func runningSources() -> [NowPlaying.Source] {
        let identifiers = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.priority.filter { identifiers.contains($0.bundleIdentifier) }
    }

    /// Full read of a player's current track. Requires Automation.
    private func read(from source: NowPlaying.Source) -> NowPlaying? {
        // Position and duration come along with the rest: both players expose
        // them to AppleScript, so a scrubber does not have to wait for the
        // MediaRemote adapter to be vendored. Reading them here costs nothing
        // extra — it is the same round trip that was already being made.
        let script = """
        tell application id "\(source.bundleIdentifier)"
            set playerState to (player state as text)
            if playerState is "stopped" then return ""
            set pos to 0
            try
                set pos to player position
            end try
            set dur to 0
            try
                set dur to duration of current track
            end try
            return playerState & tab & (name of current track) & tab \
                & (artist of current track) & tab & (pos as text) & tab & (dur as text)
        end tell
        """

        guard let raw = Self.runScript(script), !raw.isEmpty else { return nil }
        let fields = raw.components(separatedBy: "\t")
        guard fields.count >= 3 else { return nil }

        var track = NowPlaying(source: source,
                               title: fields[1],
                               artist: fields[2],
                               isPlaying: fields[0] == "playing",
                               artwork: nil)

        if fields.count >= 5,
           let position = Double(fields[3].replacingOccurrences(of: ",", with: ".")),
           let rawDuration = Double(fields[4].replacingOccurrences(of: ",", with: ".")),
           rawDuration > 0 {
            // Music reports a track's length in seconds; Spotify reports it in
            // milliseconds. Nothing in the reply says which, so it is inferred:
            // no track is four hours long, and every Spotify duration in
            // milliseconds is far past that.
            let seconds = source == .spotify ? rawDuration / 1000 : rawDuration
            track.duration = seconds
            track.elapsed = min(max(0, position), seconds)
            track.elapsedSampledAt = Date()
            track.playbackRate = track.isPlaying ? 1 : 0
        }
        return track
    }

    // MARK: Artwork

    /// Artwork is the one thing notifications never carry, so it is fetched
    /// separately and folded in when it arrives. Failure is silent by design:
    /// the island shows its placeholder glyph and everything else still works.
    private func fetchArtwork(for track: NowPlaying) {
        let key = track.trackKey
        guard !artworkInFlight.contains(key), artworkCache[key] == nil else { return }
        artworkInFlight.insert(key)

        scriptQueue.async { [weak self] in
            guard let self else { return }
            let image = Self.loadArtwork(for: track)

            DispatchQueue.main.async {
                self.artworkInFlight.remove(key)
                guard let image else { return }

                if self.artworkCache.count > 12 { self.artworkCache.removeAll() }
                self.artworkCache[key] = image

                // Only apply it if that track is still the one on screen.
                if var current = self.known[track.source], current.trackKey == key {
                    current.artwork = image
                    self.known[track.source] = current
                    self.publishBest()
                }
            }
        }
    }

    private static func loadArtwork(for track: NowPlaying) -> NSImage? {
        // Only the fallback path lands here, and it only ever holds the two
        // scriptable players; anything MediaRemote surfaced brings its own
        // artwork bytes with it.
        guard track.source.isScriptable,
              automationStatus(for: track.source, askUserIfNeeded: false).isGranted
        else { return nil }

        switch track.source {
        case .other:
            return nil

        case .music:
            let data = runScriptForData("""
            tell application id "com.apple.Music"
                if (count of artworks of current track) is 0 then return ""
                return raw data of artwork 1 of current track
            end tell
            """)
            return data.flatMap(NSImage.init(data:))

        case .spotify:
            guard let urlString = runScript("""
            tell application id "com.spotify.client"
                return artwork url of current track
            end tell
            """), let url = URL(string: urlString) else { return nil }

            // Spotify hands us a CDN URL; this is the app's only network call.
            // It runs on the same serial queue as the transport commands, so it
            // gets a short timeout rather than the default two minutes.
            var request = URLRequest(url: url)
            request.timeoutInterval = 6

            var payload: Data?
            let done = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, _, _ in
                payload = data
                done.signal()
            }.resume()
            _ = done.wait(timeout: .now() + 8)

            return payload.flatMap(NSImage.init(data:))
        }
    }

    // MARK: Transport

    func send(_ command: TransportCommand) {
        // MediaRemote drives whatever the system considers the active player,
        // browser tabs included, and needs no permission — so when it is up it
        // takes every command, including the ones AppleScript could also do.
        if preferAdapter {
            switch command {
            case .playPause: adapter.send(.togglePlayPause)
            case .next:      adapter.send(.nextTrack)
            case .previous:  adapter.send(.previousTrack)
            case let .seek(fraction):
                guard let duration = published?.duration, duration > 0 else { return }
                adapter.seek(toSeconds: duration * fraction.clampedToUnit)
            }
            return
        }

        guard let source = published?.source, source.isScriptable else { return }

        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next:      verb = "next track"
        case .previous:  verb = "previous track"

        case let .seek(fraction):
            // Both players take a position in seconds. Handled here rather than
            // falling through to the verb below because it needs an argument
            // and a duration to scale it against.
            guard let duration = published?.duration, duration > 0 else { return }
            let seconds = duration * fraction.clampedToUnit

            scriptQueue.async { [weak self] in
                let status = Self.automationStatus(for: source, askUserIfNeeded: true)
                DispatchQueue.main.async { self?.automationStatus = status }
                guard status.isGranted else { return }

                _ = Self.runScript("""
                tell application id "\(source.bundleIdentifier)"
                    set player position to \(String(format: "%.2f", seconds))
                end tell
                """)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.refresh(askForPermission: false)
                }
            }
            return
        }

        scriptQueue.async { [weak self] in
            // A transport tap is an explicit user action, so it is the right
            // place to raise the Automation prompt if it hasn't been answered.
            let status = Self.automationStatus(for: source, askUserIfNeeded: true)
            DispatchQueue.main.async { self?.automationStatus = status }
            guard status.isGranted else { return }

            _ = Self.runScript("tell application id \"\(source.bundleIdentifier)\" to \(verb)")

            // Players broadcast the result, but skipping tracks while paused
            // doesn't always fire, so read back shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh(askForPermission: false)
            }
        }
    }

    // MARK: Permission

    /// Public API — unlike running a script and inspecting the failure, this can
    /// answer without side effects when `askUserIfNeeded` is false.
    private static func automationStatus(for source: NowPlaying.Source,
                                         askUserIfNeeded: Bool) -> AutomationStatus {
        var target = AEAddressDesc()
        let created = source.bundleIdentifier.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, strlen(pointer), &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }

        switch AEDeterminePermissionToAutomateTarget(&target,
                                                     AEEventClass(typeWildCard),
                                                     AEEventID(typeWildCard),
                                                     askUserIfNeeded) {
        case noErr:                            return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound):           return .notRunning
        default:                               return .unknown
        }
    }

    // MARK: AppleScript plumbing

    private static func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }

    private static func runScriptForData(_ source: String) -> Data? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let data = result.data
        return data.isEmpty ? nil : data
    }
}
