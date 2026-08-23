//
//  MediaRemoteAdapter.swift
//  DynamicIsland
//
//  System-wide Now Playing — browser media included — via ungive/mediaremote-adapter.
//
//  ## Why this exists
//
//  macOS keeps one system-wide Now Playing record, in the private MediaRemote
//  framework. It is what the media keys, Control Center and the Lock Screen all
//  read, and it covers *everything*: Safari, Chrome, YouTube, VLC, IINA,
//  Podcasts. In macOS 15.4 Apple restricted the framework to processes whose
//  bundle identifier begins with `com.apple.`, which is why this app's Now
//  Playing has been limited to the two players that broadcast their own
//  notifications (see NowPlayingMonitor).
//
//  ## The mechanism
//
//  `/usr/bin/perl` is an Apple binary and reports the bundle identifier
//  `com.apple.perl5`, so it satisfies that check. The adapter is a Perl script
//  that loads a small helper framework into the Perl process, talks to
//  MediaRemote from there, and prints the result to stdout as JSON lines. We run
//  it as a subprocess and read those lines:
//
//      /usr/bin/perl <script>.pl <framework path> stream --micros
//
//  Nothing private is linked into this app; the private framework is only ever
//  touched inside a process Apple already trusts with it. If Apple closes this
//  route, the subprocess fails to start, `isRunning` stays false and the caller
//  falls back to the notification path — the app degrades, it does not break.
//
//  ## Stream semantics
//
//  Each line is `{"type":"data","diff":<bool>,"payload":{…}}`. A payload with
//  `diff: false` is the complete state; `diff: true` carries only what changed
//  and must be merged onto the last full payload. That is why state is kept as a
//  raw dictionary and merged as one, rather than decoded into a struct per line:
//  a struct cannot tell "this key was absent" from "this key was set to null",
//  and those mean different things here (unchanged vs. cleared).
//
//  ## Vendored files
//
//  `MediaRemoteAdapter.framework` and `mediaremote-adapter.pl` are not in this
//  repository — they are BSD-3-Clause artefacts that have to be built from
//  https://github.com/ungive/mediaremote-adapter. Drop them in `Vendor/` and
//  they are copied into the app bundle; see Vendor/README.md. Without them
//  `isAvailable` is false and nothing here runs.
//

import AppKit

/// A snapshot of the system-wide Now Playing record.
struct MediaRemoteState: Equatable {
    var bundleIdentifier: String
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool

    /// Seconds. Nil when the player doesn't publish them.
    var duration: TimeInterval?
    var elapsed: TimeInterval?

    /// When `elapsed` was measured, so it can be extrapolated between updates.
    var elapsedSampledAt: Date?
    var playbackRate: Double?

    var artworkData: Data?

    /// Elapsed time right now, carried forward from the last sample while
    /// playing. MediaRemote reports a position and a timestamp, not a ticking
    /// clock, so a progress bar that didn't do this would only move when the
    /// track changed.
    var elapsedNow: TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let sampledAt = elapsedSampledAt else { return elapsed }
        let rate = playbackRate ?? 1
        let projected = elapsed + Date().timeIntervalSince(sampledAt) * rate
        guard let duration else { return max(0, projected) }
        return min(max(0, projected), duration)
    }

    /// 0…1 for the progress bar, when there is enough to say.
    var progress: Double? {
        guard let duration, duration > 0, let elapsed = elapsedNow else { return nil }
        return (elapsed / duration).clampedToUnit
    }
}

final class MediaRemoteAdapter {

    /// Called on the main queue whenever the state changes, or with nil when
    /// nothing is playing.
    var onChange: ((MediaRemoteState?) -> Void)?

    /// Called on the main queue when the adapter starts or stops working, so the
    /// caller can switch to (or back from) its fallback.
    var onAvailabilityChange: ((Bool) -> Void)?

    /// True when the vendored framework and script are both present. False on a
    /// build where nobody dropped them in, which is the normal state of a fresh
    /// clone.
    var isAvailable: Bool { paths != nil }

    /// True while the subprocess is up and has produced at least one line.
    private(set) var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            let running = isRunning
            DispatchQueue.main.async { [weak self] in self?.onAvailabilityChange?(running) }
        }
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var buffer = Data()

    /// The last complete (non-diff) payload, with every diff merged onto it.
    private var merged: [String: Any] = [:]
    private var published: MediaRemoteState?

    private var restartAttempts = 0
    private var restartWork: DispatchWorkItem?
    private var stopping = false

    /// Give up relaunching after this many consecutive failures. A permanent
    /// failure (Apple closed the route, the framework is the wrong architecture)
    /// should end as "unavailable", not as a process being respawned forever.
    private static let maxRestartAttempts = 5

    private static let perl = "/usr/bin/perl"

    /// Where the vendored files live inside the built app.
    private var paths: (script: String, framework: String)? {
        let bundle = Bundle.main
        guard let script = bundle.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let framework = bundle.path(forResource: "MediaRemoteAdapter", ofType: "framework"),
              FileManager.default.fileExists(atPath: Self.perl)
        else { return nil }
        return (script, framework)
    }

    // MARK: Lifecycle

    func start() {
        guard isAvailable, process == nil else { return }
        stopping = false
        launch()
    }

    func stop() {
        stopping = true
        restartWork?.cancel()
        restartWork = nil
        restartAttempts = 0

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil

        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil

        buffer.removeAll()
        merged.removeAll()
        published = nil
        isRunning = false
    }

    deinit {
        stop()
    }

    private func launch() {
        guard let paths else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perl)
        // --micros keeps the time fields as integers, which avoids the floating
        // point drift a seek position would otherwise pick up on the way back.
        process.arguments = [paths.script, paths.framework, "stream", "--micros"]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // The adapter is chatty on stderr about things we can't act on; a pipe
        // nobody drains would eventually fill and block the child.
        process.standardError = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(chunk) }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.processEnded() }
        }

        do {
            try process.run()
        } catch {
            // Nothing to fall back to here; the caller's fallback covers it.
            scheduleRestart()
            return
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
    }

    private func processEnded() {
        guard !stopping else { return }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        process = nil
        isRunning = false
        scheduleRestart()
    }

    /// Exponential backoff, capped. A player quitting can take the adapter down
    /// with it, and relaunching in a tight loop would be worse than the problem.
    private func scheduleRestart() {
        guard !stopping, restartAttempts < Self.maxRestartAttempts else {
            publish(nil)
            return
        }
        restartAttempts += 1
        let delay = min(pow(2.0, Double(restartAttempts - 1)), 16)

        let work = DispatchWorkItem { [weak self] in self?.launch() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Reading

    private func consume(_ chunk: Data) {
        buffer.append(chunk)

        // Lines can straddle reads, so only whole ones are parsed and the
        // remainder is kept for the next chunk.
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }

        // A malformed stream must not grow the buffer without bound.
        if buffer.count > 8 * 1024 * 1024 { buffer.removeAll() }
    }

    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (object["type"] as? String) == "data"
        else { return }

        restartAttempts = 0
        isRunning = true

        let isDiff = object["diff"] as? Bool ?? false

        guard let payload = object["payload"] as? [String: Any] else {
            // A null payload is the adapter saying nothing is playing.
            merged.removeAll()
            publish(nil)
            return
        }

        if isDiff {
            // Merge, honouring explicit nulls: a diff that sets `artist` to null
            // means the next track has no artist, not that it kept the old one.
            for (key, value) in payload {
                if value is NSNull { merged.removeValue(forKey: key) }
                else { merged[key] = value }
            }
        } else {
            merged = payload.filter { !($0.value is NSNull) }
        }

        publish(state(from: merged))
    }

    private func state(from payload: [String: Any]) -> MediaRemoteState? {
        // The adapter guarantees these three whenever anything is playing.
        guard let bundleIdentifier = payload["bundleIdentifier"] as? String,
              let title = payload["title"] as? String
        else { return nil }

        var artwork: Data?
        if let base64 = payload["artworkData"] as? String {
            artwork = Data(base64Encoded: base64)
        } else if let data = payload["artworkData"] as? Data {
            artwork = data
        }

        return MediaRemoteState(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: payload["artist"] as? String,
            album: payload["album"] as? String,
            isPlaying: payload["playing"] as? Bool ?? false,
            duration: Self.seconds(payload["duration"]),
            elapsed: Self.seconds(payload["elapsedTime"]),
            elapsedSampledAt: Self.date(payload["timestamp"]),
            playbackRate: Self.double(payload["playbackRate"]),
            artworkData: artwork
        )
    }

    private func publish(_ state: MediaRemoteState?) {
        // Artwork is a few hundred kilobytes and only arrives on a track change;
        // comparing whole states each tick would mean memcmp'ing it every time.
        guard state != published else { return }
        published = state
        onChange?(state)
    }

    // MARK: Commands

    /// MediaRemote command numbers, from the adapter's documented table.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
        case goBackFifteenSeconds = 12
        case skipFifteenSeconds = 13
    }

    func send(_ command: Command) {
        run(["send", String(command.rawValue)])
    }

    /// Jump to a position, in seconds.
    func seek(toSeconds seconds: TimeInterval) {
        let micros = Int64(max(0, seconds) * 1_000_000)
        run(["seek", String(micros)])
    }

    /// One-shot invocations. Commands are separate short-lived processes rather
    /// than being written to the streaming one — the stream's stdin is not a
    /// command channel, and a command that hung would take Now Playing with it.
    private func run(_ arguments: [String]) {
        guard let paths else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perl)
        process.arguments = [paths.script, paths.framework] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: Field coercion

    /// Microseconds → seconds.
    ///
    /// Unconditional, because the stream is always started with `--micros`.
    /// A "looks too big, must be micros" heuristic was tried and is wrong at the
    /// small end: 0.05 s is 50 000 µs, which is under any sane threshold and
    /// would be read back as 50 000 *seconds* — a fresh track would show a
    /// playhead 14 hours in.
    private static func seconds(_ value: Any?) -> TimeInterval? {
        guard let number = value as? NSNumber else { return nil }
        let micros = number.doubleValue
        guard micros >= 0 else { return nil }
        return micros / 1_000_000
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// The sample time, as an offset from the Unix epoch.
    ///
    /// Unlike a duration, this one *can* be told apart by magnitude without
    /// risk: the epoch in seconds is ~1.7e9 and in microseconds ~1.7e15, so any
    /// threshold between them separates the two for the next several thousand
    /// years. Worth handling, because `--micros` converting this field as well
    /// is an implementation detail of the adapter rather than a promise.
    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1_000_000 : raw)
    }
}
