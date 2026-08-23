//
//  IslandPayload.swift
//  DynamicIsland
//
//  What the island is currently showing, independent of how big it is.
//
//  Two kinds of content share the island:
//    • Ambient — Now Playing. It persists for as long as something is playing
//      and gives the compact pill its leading/trailing accessories.
//    • Transient — volume, brightness and power changes. These take the island
//      over for a moment and then hand it back, like the system HUDs they
//      replace.
//

import AppKit

/// A track playing (or paused) somewhere on the system.
struct NowPlaying: Equatable {

    /// Where the track is coming from.
    ///
    /// Music and Spotify are named because they are the two players this app can
    /// *script* — that is what the AppleScript fallback needs. Everything else
    /// only ever arrives through MediaRemote, which identifies a player by its
    /// bundle id, so `.other` carries that instead of trying to enumerate every
    /// app that can play a sound.
    enum Source: Hashable {
        case music
        case spotify
        case other(bundleIdentifier: String)

        /// The players the AppleScript path knows how to talk to.
        static let scriptable: [Source] = [.music, .spotify]

        var isScriptable: Bool { Self.scriptable.contains(self) }

        var bundleIdentifier: String {
            switch self {
            case .music:                    return "com.apple.Music"
            case .spotify:                  return "com.spotify.client"
            case let .other(bundleID):      return bundleID
            }
        }

        /// Stable, short identity for keying caches.
        var key: String {
            switch self {
            case .music:                    return "Music"
            case .spotify:                  return "Spotify"
            case let .other(bundleID):      return bundleID
            }
        }

        /// What to call this player in the interface. For anything unknown the
        /// installed app's own name is used, so "com.google.Chrome" shows up as
        /// "Google Chrome" rather than as a reverse-DNS string.
        var displayName: String {
            switch self {
            case .music:   return "Music"
            case .spotify: return "Spotify"
            case let .other(bundleID):
                guard let url = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
                return FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
            }
        }

        static func from(bundleIdentifier: String) -> Source {
            switch bundleIdentifier {
            case "com.apple.Music", "com.apple.iTunes": return .music
            case "com.spotify.client":                  return .spotify
            default:                                    return .other(bundleIdentifier: bundleIdentifier)
            }
        }
    }

    var source: Source
    var title: String
    var artist: String
    var isPlaying: Bool
    var artwork: NSImage?

    /// Track length, when the player publishes it. Only MediaRemote does.
    var duration: TimeInterval?

    /// Position at `elapsedSampledAt`. Extrapolated by `elapsedNow` rather than
    /// ticked, because MediaRemote reports a position and a time, not a clock.
    var elapsed: TimeInterval?
    var elapsedSampledAt: Date?
    var playbackRate: Double?

    /// Stable per-track identity, used to avoid re-fetching artwork every poll.
    var trackKey: String { "\(source.key)|\(title)|\(artist)" }

    /// Where the playhead is right now.
    var elapsedNow: TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let elapsedSampledAt else { return elapsed }
        let projected = elapsed + Date().timeIntervalSince(elapsedSampledAt) * (playbackRate ?? 1)
        guard let duration else { return max(0, projected) }
        return min(max(0, projected), duration)
    }

    /// 0…1, or nil when the player doesn't say how long the track is — in which
    /// case the row shows no bar at all rather than an empty one.
    var progress: Double? {
        guard let duration, duration > 0, let elapsed = elapsedNow else { return nil }
        return (elapsed / duration).clampedToUnit
    }

    var hasProgress: Bool { duration != nil && elapsed != nil }
}

/// What the compact pill shows in the strips beside the notch.
///
/// The notch costs the same width whether or not anything is in it, so these
/// slots are free real estate — the island only grows by what an accessory
/// actually needs.
enum CompactAccessory: Equatable {
    case artwork(NSImage?)
    case waveform(playing: Bool, palette: ArtworkPalette)
    case countdown(String)
    case timerGlyph
    case privacy(camera: Bool, microphone: Bool)
    case shelf(count: Int)
    case download

    var width: CGFloat {
        switch self {
        case .countdown:                  return 48
        case let .privacy(camera, mic):   return camera && mic ? 40 : 28
        case .shelf:                      return 34
        case .download:                   return 34
        default:                          return 34
        }
    }
}

/// The pair of slots flanking the notch.
struct CompactAccessories: Equatable {
    var leading: CompactAccessory?
    var trailing: CompactAccessory?

    static let none = CompactAccessories(leading: nil, trailing: nil)

    var totalWidth: CGFloat { (leading?.width ?? 0) + (trailing?.width ?? 0) }
    var isEmpty: Bool { leading == nil && trailing == nil }
}

/// A countdown owned by the island.
struct CountdownState: Equatable {
    /// What the timer was started with, for restarting.
    var duration: TimeInterval
    var remaining: TimeInterval
    var isRunning: Bool

    var isFinished: Bool { remaining <= 0 }

    /// 0…1 elapsed, for the progress ring.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return ((duration - remaining) / duration).clampedToUnit
    }

    /// "4:32", or "1:04:32" once there is an hour to show.
    var text: String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// What a press on the timer row does.
enum TimerAction: Equatable {
    case start(minutes: Int)
    case toggle
    case restart
    case cancel
}

/// A tile in the control center's SYSTEM row.
enum SystemTile: Hashable {
    case volume
    case brightness
    case battery
    case bluetooth

    /// Volume and brightness are controls; the rest are readouts.
    var isAdjustable: Bool { self == .volume || self == .brightness }
}

/// What a press on the shelf does.
enum ShelfAction: Equatable {
    /// Indices refer to the shelf's current order, which is what the row draws.
    case open(index: Int)
    case remove(index: Int)
    /// ⌘- or ⇧-click: add or remove the chip from the selection instead of
    /// opening it. Same index space as `.open`, because it is the same chip —
    /// only the modifier tells them apart.
    case toggleSelection(index: Int)
    case copyAll
    case airDropAll
    case clear
}

/// Anything on the island the pointer can act on.
enum IslandControl: Equatable {
    case transport(TransportCommand)
    /// The album cover. Pressing it brings the player that owns the track to
    /// the front — the cover is the most direct thing on the island that stands
    /// for "the app this is coming from".
    case artwork
    /// The progress bar. A value control like the volume tile — press and drag
    /// map to a position — so it is its own case rather than a `.transport`
    /// carrying a fraction, which could never compare equal for hover testing.
    case seek
    case tile(SystemTile)
    case timer(TimerAction)
    case shelf(ShelfAction)
}

/// What the expanded island is showing.
///
/// The expanded state used to be one fixed width for every payload, which left
/// wide black wings around anything short. Each payload now says how much room
/// it actually needs.
enum ExpandedPayloadKind: Equatable {
    /// Volume or brightness: icon, meter, percentage.
    case meter
    /// Power, device or event: an icon, two lines of text and a trailing value.
    case wide
    case nowPlaying
    case countdown
    /// The hover readout, which is as wide as the chips it shows.
    case quickStats(chips: Int)

    /// How wide the island grows for this payload.
    ///
    /// Deliberately tight. The island opens *on top of* whatever you were
    /// looking at, so every point it takes sideways is a point of someone
    /// else's window covered — and the payloads were sized for the widest
    /// possible content rather than the usual case. A long track title is
    /// handled by the marquee scrolling it, not by making the island wide
    /// enough to hold it.
    var width: CGFloat {
        switch self {
        case .meter:              return 300
        case .wide:               return 360
        case .nowPlaying:         return 360
        case .countdown:          return 288
        case let .quickStats(n):  return n == 0 ? 200 : 34 + CGFloat(n) * 74 + CGFloat(n - 1) * 8
        }
    }

    /// Height of the area below the notch. One number: the hover row is a
    /// single line of information and the scrubber lives a click deeper.
    var innerHeight: CGFloat { 56 }

    /// The panel is sized once, for the widest and tallest the island can be.
    /// Must be the largest `width` above, or the widest payload gets clipped.
    static let maxWidth: CGFloat = 360
    static let maxInnerHeight: CGFloat = 56
}

/// Which optional sections the control center is currently showing. Sizes and
/// hit rects are both derived from this, so they cannot disagree about where a
/// row begins.
struct ControlCenterSections: Equatable {
    var calendar: Bool
    var timer: Bool
    var shelf: Bool
    /// Whether the media row carries a scrubber, which makes it taller.
    ///
    /// Part of the layout identity rather than a detail the view checks: the
    /// panel is sized from this, so a track that starts publishing a duration
    /// has to resize the island, not overflow it.
    var mediaProgress: Bool = false

    static let none = ControlCenterSections(calendar: false, timer: false, shelf: false)
}

/// One control's geometry, in global screen coordinates.
struct IslandControlHit {
    let control: IslandControl
    /// Where a press counts.
    let hitRect: CGRect
    /// The horizontal extent a dragged value maps onto.
    let valueRect: CGRect

    /// 0…1 for a pointer position, for the controls that take a value.
    func fraction(at point: CGPoint) -> Double {
        guard valueRect.width > 0 else { return 0 }
        return ((point.x - valueRect.minX) / valueRect.width).clampedToUnit
    }
}

/// Commands the island can send back to the active player.
enum TransportCommand: Equatable {
    case playPause
    case next
    case previous
    /// Jump to a fraction of the track. Only reachable when the player publishes
    /// a duration, which in practice means the MediaRemote path.
    case seek(fraction: Double)
}

/// Why the island is showing the power state.
///
/// The snapshot alone can't say this: 42% on battery is the same reading
/// whether the charger was just pulled out or the level simply drifted down
/// past a threshold, and the two deserve different words.
enum PowerEvent: Equatable {
    case pluggedIn
    case unplugged
    case fullyCharged
    /// Crossed one of the warning thresholds on battery.
    case lowBattery(threshold: Int)

    /// Warnings are drawn in orange and held a little longer.
    var isWarning: Bool {
        if case .lowBattery = self { return true }
        return false
    }
}

/// Snapshot of the power source.
struct PowerSnapshot: Equatable {
    var percentage: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Minutes to full / to empty, when the system is willing to estimate.
    var minutesRemaining: Int?
}

/// A Bluetooth audio device and whatever battery it reports.
struct BluetoothDevice: Equatable {
    var name: String
    /// Percentages, when the device publishes them. AirPods report per bud and
    /// case; most other headsets report a single figure.
    var left: Int?
    var right: Int?
    var case_: Int?
    var single: Int?

    /// The figure to show when there is only room for one.
    var headline: Int? { single ?? [left, right].compactMap { $0 }.min() }
    var hasBattery: Bool { headline != nil || case_ != nil }
}

/// Whether the camera and microphone are in use by anything on the system.
struct PrivacyState: Equatable {
    var cameraActive: Bool
    var microphoneActive: Bool

    var isActive: Bool { cameraActive || microphoneActive }
    static let idle = PrivacyState(cameraActive: false, microphoneActive: false)
}

/// A short-lived takeover of the island.
enum TransientKind: Equatable {
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)
    case power(PowerSnapshot, PowerEvent)
    case device(BluetoothDevice)
    case timerFinished(TimeInterval)
    case event(UpcomingEvent)
    case notification(IslandNotification)
    case download(DownloadActivity)

    /// How long the island holds this. A notification carries words to read, so
    /// it gets longer than a volume bar does.
    var dwell: TimeInterval {
        switch self {
        case .notification:            return 4.2
        case let .power(_, event):     return event.isWarning ? 3.4 : 2.2
        case .event:                   return 3.0
        case let .download(activity):  return activity.isComplete ? 3.4 : 2.6
        default:                       return 1.7
        }
    }
}
