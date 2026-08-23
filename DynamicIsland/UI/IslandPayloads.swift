//
//  IslandPayloads.swift
//  DynamicIsland
//
//  The contents the island can show, one view per payload.
//
//  These views draw; they never handle input. Presses and hover are routed by
//  geometry in AppKit (see PassthroughHostingView), because NSHostingView inside
//  a non-activating panel never passes mouse events to SwiftUI's gesture system.
//  `ControlCenterMetrics` is the geometry both sides measure from, so what you
//  see and what you can press cannot drift apart.
//

import SwiftUI

// MARK: - HUD (volume / brightness / power)

/// The momentary takeover shown for a system event.
struct HUDPayload: View {

    var kind: TransientKind

    var body: some View {
        Group {
            switch kind {
            case let .volume(level, muted):
                meterRow(symbol: IslandSymbol.volume(level: level, muted: muted),
                         value: muted ? 0 : level,
                         trailing: muted ? Strings.muted : level.percentText)

            case let .brightness(level):
                meterRow(symbol: IslandSymbol.brightness(level: level),
                         value: level,
                         trailing: level.percentText)

            case let .power(snapshot, event):
                powerRow(snapshot, event)

            case let .device(device):
                deviceRow(device)

            case let .timerFinished(duration):
                timerFinishedRow(duration)

            case let .event(event):
                eventRow(event)

            case let .notification(notification):
                notificationRow(notification)

            case let .download(activity):
                downloadRow(activity)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func meterRow(symbol: String, value: Double, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 20)

            MeterBar(value: value)

            Text(trailing)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func powerRow(_ snapshot: PowerSnapshot, _ event: PowerEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: event, snapshot: snapshot))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Self.tint(for: event, snapshot: snapshot))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.headline(for: event, snapshot: snapshot))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(event.isWarning ? .orange : .white)

                if let minutes = snapshot.minutesRemaining {
                    Text(snapshot.isCharging
                         ? Strings.untilFull(Self.duration(minutes))
                         : Strings.remaining(Self.duration(minutes)))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 8)

            Text("\(snapshot.percentage)%")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
        }
    }

    /// The power moment decides the words, the glyph and the colour — the
    /// snapshot alone can't tell "just unplugged" from "still on battery".
    private static func headline(for event: PowerEvent, snapshot: PowerSnapshot) -> String {
        switch event {
        case .pluggedIn:               return Strings.powerAdapter
        case .unplugged:               return Strings.onBattery
        case .fullyCharged:            return Strings.fullyCharged
        case .lowBattery:              return Strings.lowBattery
        }
    }

    private static func symbol(for event: PowerEvent, snapshot: PowerSnapshot) -> String {
        switch event {
        case .fullyCharged: return "battery.100percent.bolt"
        case .lowBattery:   return "exclamationmark.triangle.fill"
        default:            return IslandSymbol.battery(snapshot)
        }
    }

    private static func tint(for event: PowerEvent, snapshot: PowerSnapshot) -> Color {
        switch event {
        case .fullyCharged: return .green
        case .lowBattery:   return .orange
        default:            return snapshot.isCharging ? .green : .white
        }
    }

    private func downloadRow(_ activity: DownloadActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activity.isComplete
                  ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(activity.isComplete ? .green : .white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(activity.isComplete
                     ? Strings.downloadFinished
                     : Strings.downloading(others: activity.otherCount))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            // Bytes received, not a percentage: no browser publishes a total a
            // third party can read, and an invented bar would be a lie.
            Text(Self.bytes(activity.bytes))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }

    private func deviceRow(_ device: BluetoothDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: IslandSymbol.device(named: device.name))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(Strings.connected)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            // AirPods report each bud; anything else usually reports one figure.
            HStack(spacing: 10) {
                if let left = device.left { batteryPip("L", left) }
                if let right = device.right { batteryPip("R", right) }
                if device.left == nil, device.right == nil, let single = device.single {
                    batteryPip(nil, single)
                }
                if let caseLevel = device.case_ { batteryPip("C", caseLevel) }
            }
        }
    }

    private func batteryPip(_ label: String?, _ percentage: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(percentage)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)

            if let label {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func timerFinishedRow(_ duration: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.timerFinished)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Text(Strings.minutesShort(Int((duration / 60).rounded())))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
    }

    private func notificationRow(_ notification: IslandNotification) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = Self.icon(forAppNamed: notification.appName) {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                } else {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let body = notification.body {
                    Text(body)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                } else if let app = notification.appName {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// The sending app's own icon when it can be matched to something running;
    /// the banner only gives us its name.
    private static func icon(forAppNamed name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications
            .first { $0.localizedName == name }?
            .icon
    }

    private func eventRow(_ event: UpcomingEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(event.location ?? event.timeText)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(event.relativeText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    /// "1h 24m" / "24m", the way the system menu bar phrases it.
    private static func duration(_ minutes: Int) -> String {
        Strings.duration(hours: minutes / 60, minutes: minutes % 60)
    }
}

// MARK: - Now Playing (hover)

/// Geometry of the expanded media row.
///
/// Transport used to live only in the control center, one click deeper. That was
/// a click too many for the thing people reach for most: skipping a track while
/// the pointer is already on the island.
enum ExpandedMediaMetrics {
    static let horizontalPadding: CGFloat = 16
    static let artworkSide: CGFloat = 34
    static let transportSide: CGFloat = 26
    static let transportSpacing: CGFloat = 2

    static var transportWidth: CGFloat { transportSide * 3 + transportSpacing * 2 }

    /// Gap between the cover and the text beside it.
    static let artworkGap: CGFloat = 12

    /// Slack between the text column and the transport buttons.
    static let transportGap: CGFloat = 10

    /// The cover, in payload-local coordinates. Pressable: it opens the player.
    static func artworkFrame(innerHeight: CGFloat) -> CGRect {
        CGRect(x: horizontalPadding,
               y: (innerHeight - artworkSide) / 2,
               width: artworkSide, height: artworkSide)
    }

    /// Height of the stacked title + artist lines, as drawn.
    static let textBlockHeight: CGFloat = 32
    /// The title line alone.
    static let titleLineHeight: CGFloat = 17

    /// The title, pressable like the cover.
    ///
    /// Deliberately just the one line, not the whole text block and not the
    /// whole row. The island's own body is what opens the control center, and a
    /// generous press target here ate most of the places there were left to
    /// click — reaching for "open" and getting "switch to Spotify" instead.
    static func titleFrame(islandWidth: CGFloat, innerHeight: CGFloat) -> CGRect {
        let x = horizontalPadding + artworkSide + artworkGap
        return CGRect(x: x,
                      y: (innerHeight - textBlockHeight) / 2,
                      width: textColumnWidth(islandWidth: islandWidth),
                      height: titleLineHeight)
    }

    /// Width the title and artist get.
    ///
    /// Stated rather than left to the stack. The title is a marquee, and a
    /// marquee asks for its *natural* width — so an HStack sizing itself to its
    /// children's ideals grows past the island on a long title, taking the
    /// cover off the left edge and sliding the title under the transport
    /// buttons. Worse, the marquee then measures that runaway width as its
    /// container, decides the text fits, and never scrolls at all.
    static func textColumnWidth(islandWidth: CGFloat) -> CGFloat {
        max(0, islandWidth
            - horizontalPadding - artworkSide - artworkGap
            - transportWidth - horizontalPadding - transportGap)
    }

    /// Payload-local frames (origin at the top-left of the area below the notch).
    static func transportFrames(islandWidth: CGFloat,
                                innerHeight: CGFloat) -> [(command: TransportCommand, frame: CGRect)] {
        let top = (innerHeight - transportSide) / 2
        var x = islandWidth - horizontalPadding - transportWidth

        var frames: [(TransportCommand, CGRect)] = []
        for command in [TransportCommand.previous, .playPause, .next] {
            frames.append((command, CGRect(x: x, y: top, width: transportSide, height: transportSide)))
            x += transportSide + transportSpacing
        }
        return frames
    }
}

/// The media row shown on hover, with working transport controls.
///
/// The waveform lives on the compact pill; here the same space is worth more as
/// buttons.
struct NowPlayingPayload: View {

    @ObservedObject var model: IslandModel
    var track: NowPlaying
    var islandWidth: CGFloat
    var innerHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: ExpandedMediaMetrics.artworkGap) {
                ArtworkView(image: track.artwork,
                            side: ExpandedMediaMetrics.artworkSide, cornerRadius: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(model.hoveredControl == .artwork ? 0.22 : 0))
                            .animation(.easeOut(duration: 0.12), value: model.hoveredControl)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    // A title is the one thing this row exists to show, so it
                    // scrolls rather than truncating. The artist is short enough
                    // to fit in practice and stays still — two things sliding at
                    // once reads as noise.
                    MarqueeText(text: track.title,
                                font: .system(size: 12, weight: .semibold),
                                color: .white)
                        .id(track.trackKey)

                    Text(track.artist)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // A stated width, not one inferred from the text: see
                // `textColumnWidth`. `.frame` sizes but does not cut, so the
                // clip is what actually keeps a long title off the buttons.
                .frame(width: ExpandedMediaMetrics.textColumnWidth(islandWidth: islandWidth),
                       alignment: .leading)
                .clipped()

                Spacer(minLength: 0)
            }
            .padding(.leading, ExpandedMediaMetrics.horizontalPadding)
            .padding(.trailing, ExpandedMediaMetrics.transportWidth
                     + ExpandedMediaMetrics.horizontalPadding
                     + ExpandedMediaMetrics.transportGap)
            .frame(maxWidth: .infinity, maxHeight: innerHeight, alignment: .leading)

            ForEach(Array(ExpandedMediaMetrics.transportFrames(
                islandWidth: islandWidth, innerHeight: innerHeight).enumerated()),
                    id: \.offset) { _, item in
                TransportGlyph(symbol: symbol(for: item.command),
                               size: item.command == .playPause ? 14 : 12,
                               isHovered: model.hoveredControl == .transport(item.command))
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func symbol(for command: TransportCommand) -> String {
        switch command {
        case .previous:  return "backward.fill"
        case .next:      return "forward.fill"
        case .playPause: return track.isPlaying ? "pause.fill" : "play.fill"
        // Seeking lives in the control center, and is a bar rather than a
        // button in any case.
        case .seek:      return ""
        }
    }
}

// MARK: - Quick stats (hover, nothing playing)

/// What a hover is worth when there is no media: the three numbers you'd
/// otherwise go to the menu bar for.
struct QuickStatsPayload: View {

    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 8) {
            if let power = model.power {
                StatChip(symbol: IslandSymbol.battery(power), value: "\(power.percentage)%")
            }
            if let volume = model.volume {
                StatChip(symbol: IslandSymbol.volume(level: volume, muted: false),
                         value: volume.percentText)
            }
            if let brightness = model.brightness {
                StatChip(symbol: IslandSymbol.brightness(level: brightness),
                         value: brightness.percentText)
            }
            if model.power == nil, model.volume == nil, model.brightness == nil {
                Text(Strings.dynamicIsland)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Control center

/// A row in the control center. The stack of visible sections decides every
/// vertical position, so adding a section is one line here rather than a fresh
/// tangle of conditionals.
enum CCSection: Hashable {
    case media
    case calendar
    case timer
    case shelf
    case system
}

/// Geometry of the control center, in payload-local coordinates (origin at the
/// top-left of the area below the notch).
///
/// Every element is placed from these numbers and every hit rect is derived from
/// them, so what is drawn and what is clickable are the same rectangle by
/// construction rather than by careful maintenance.
enum ControlCenterMetrics {
    static let horizontalPadding: CGFloat = 18
    static let headerHeight: CGFloat = 11
    static let headerSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16
    static let bottomMargin: CGFloat = 16

    static let mediaRowHeight: CGFloat = 46
    /// Room the scrubber and its two times add to the media row.
    static let mediaProgressExtra: CGFloat = 26
    static let seekBarHeight: CGFloat = 3
    static let calendarRowHeight: CGFloat = 38
    static let timerRowHeight: CGFloat = 34
    static let shelfRowHeight: CGFloat = 54
    static let tileHeight: CGFloat = 56

    static let tileSpacing: CGFloat = 10
    /// Inset from a tile's edge to its meter — the extent a drag maps onto.
    static let tileInset: CGFloat = 10
    static let transportSide: CGFloat = 28
    static let transportSpacing: CGFloat = 4
    static let presetWidth: CGFloat = 54
    static let presetSpacing: CGFloat = 8
    static let shelfChipWidth: CGFloat = 66
    static let shelfChipSpacing: CGFloat = 8
    static let shelfRemoveSide: CGFloat = 16
    static let actionHeight: CGFloat = 16
    static let actionSpacing: CGFloat = 12

    /// The presets the island offers directly. A free-form duration needs a
    /// keyboard, and this panel can never become key — the menu bar carries the
    /// longer list instead.
    static let presets = [5, 10, 25]

    // MARK: Section stack

    static func rowHeight(_ section: CCSection, _ sections: ControlCenterSections) -> CGFloat {
        switch section {
        case .media:    return mediaRowHeight + (sections.mediaProgress ? mediaProgressExtra : 0)
        case .calendar: return calendarRowHeight
        case .timer:    return timerRowHeight
        case .shelf:    return shelfRowHeight
        case .system:   return tileHeight
        }
    }

    static func visibleSections(_ sections: ControlCenterSections) -> [CCSection] {
        var stack: [CCSection] = [.media]
        if sections.calendar { stack.append(.calendar) }
        if sections.timer { stack.append(.timer) }
        if sections.shelf { stack.append(.shelf) }
        stack.append(.system)
        return stack
    }

    /// Top of a section's header, or nil when that section isn't showing.
    static func headerTop(_ section: CCSection, _ sections: ControlCenterSections) -> CGFloat? {
        var y: CGFloat = 0
        for candidate in visibleSections(sections) {
            if candidate == section { return y }
            y += headerHeight + headerSpacing + rowHeight(candidate, sections) + sectionSpacing
        }
        return nil
    }

    /// Top of a section's content row.
    static func rowTop(_ section: CCSection, _ sections: ControlCenterSections) -> CGFloat? {
        headerTop(section, sections).map { $0 + headerHeight + headerSpacing }
    }

    /// Total height the visible sections need, plus a bottom margin.
    static func contentHeight(_ sections: ControlCenterSections) -> CGFloat {
        let stack = visibleSections(sections)
        let body = stack.reduce(0) { $0 + headerHeight + headerSpacing + rowHeight($1, sections) }
        let gaps = sectionSpacing * CGFloat(max(0, stack.count - 1))
        return body + gaps + bottomMargin
    }

    /// Room the transport controls occupy, so the track title stops short of them.
    static var transportWidth: CGFloat { transportSide * 3 + transportSpacing * 2 }

    // MARK: Frames

    static func transportFrames(islandWidth: CGFloat,
                                sections: ControlCenterSections) -> [(command: TransportCommand, frame: CGRect)] {
        guard let row = rowTop(.media, sections) else { return [] }
        let top = row + (mediaRowHeight - transportSide) / 2
        var x = islandWidth - horizontalPadding - transportWidth

        var frames: [(TransportCommand, CGRect)] = []
        for command in [TransportCommand.previous, .playPause, .next] {
            frames.append((command, CGRect(x: x, y: top, width: transportSide, height: transportSide)))
            x += transportSide + transportSpacing
        }
        return frames
    }

    static func tileFrames(islandWidth: CGFloat, count: Int,
                           sections: ControlCenterSections) -> [CGRect] {
        guard count > 0, let top = rowTop(.system, sections) else { return [] }
        let available = islandWidth - horizontalPadding * 2 - tileSpacing * CGFloat(count - 1)
        let width = available / CGFloat(count)
        return (0..<count).map { index in
            CGRect(x: horizontalPadding + (width + tileSpacing) * CGFloat(index),
                   y: top, width: width, height: tileHeight)
        }
    }

    /// Duration buttons, shown when no countdown is running.
    static func timerPresetFrames(_ sections: ControlCenterSections) -> [(minutes: Int, frame: CGRect)] {
        guard let top = rowTop(.timer, sections) else { return [] }
        return presets.enumerated().map { index, minutes in
            (minutes, CGRect(x: horizontalPadding + (presetWidth + presetSpacing) * CGFloat(index),
                             y: top, width: presetWidth, height: timerRowHeight))
        }
    }

    /// Pause / restart / cancel, shown while a countdown exists.
    static func timerControlFrames(islandWidth: CGFloat,
                                   sections: ControlCenterSections) -> [(action: TimerAction, frame: CGRect)] {
        guard let row = rowTop(.timer, sections) else { return [] }
        let side = transportSide
        let total = side * 3 + transportSpacing * 2
        let top = row + (timerRowHeight - side) / 2
        var x = islandWidth - horizontalPadding - total

        var frames: [(TimerAction, CGRect)] = []
        for action in [TimerAction.toggle, .restart, .cancel] {
            frames.append((action, CGRect(x: x, y: top, width: side, height: side)))
            x += side + transportSpacing
        }
        return frames
    }

    /// The strip left over for the countdown readout and its progress bar.
    static func timerReadoutFrame(islandWidth: CGFloat,
                                  sections: ControlCenterSections) -> CGRect {
        let row = rowTop(.timer, sections) ?? 0
        let controlsWidth = transportSide * 3 + transportSpacing * 2 + 12
        return CGRect(x: horizontalPadding, y: row,
                      width: islandWidth - horizontalPadding * 2 - controlsWidth,
                      height: timerRowHeight)
    }

    /// The shelf's chips, left to right.
    static func shelfChipFrames(count: Int, sections: ControlCenterSections) -> [CGRect] {
        guard let top = rowTop(.shelf, sections) else { return [] }
        return (0..<count).map { index in
            CGRect(x: horizontalPadding + (shelfChipWidth + shelfChipSpacing) * CGFloat(index),
                   y: top, width: shelfChipWidth, height: shelfRowHeight)
        }
    }

    /// The small ✕ that appears on a hovered chip.
    static func shelfRemoveFrame(chip: CGRect) -> CGRect {
        CGRect(x: chip.maxX - shelfRemoveSide + 2, y: chip.minY - 2,
               width: shelfRemoveSide, height: shelfRemoveSide)
    }

    /// Copy / AirDrop / Clear, right-aligned on the shelf's header line.
    ///
    /// Widths are measured rather than tabulated: the labels are translated, and
    /// "Kopyala" does not fit the box "Copy" needed. Measuring keeps the drawn
    /// label and its hit rect the same size in any language.
    static func shelfActionFrames(islandWidth: CGFloat,
                                  sections: ControlCenterSections) -> [(action: ShelfAction, frame: CGRect)] {
        guard let header = headerTop(.shelf, sections) else { return [] }

        let labels: [(ShelfAction, String)] = [
            (.copyAll, Strings.copy), (.airDropAll, Strings.airDrop), (.clear, Strings.clear),
        ]
        let widths = labels.map { labelWidth($0.1) }
        let total = widths.reduce(0, +) + actionSpacing * CGFloat(labels.count - 1)
        var x = islandWidth - horizontalPadding - total

        return zip(labels, widths).map { label, width in
            defer { x += width + actionSpacing }
            return (label.0, CGRect(x: x, y: header - 3, width: width, height: actionHeight))
        }
    }

    /// Width of a shelf action's label as it will actually be drawn.
    static func labelWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    /// The scrubber under the media row, when the player publishes a duration.
    static func mediaSeekFrame(islandWidth: CGFloat,
                               sections: ControlCenterSections) -> CGRect? {
        guard sections.mediaProgress, let row = rowTop(.media, sections) else { return nil }
        return CGRect(x: horizontalPadding,
                      y: row + mediaRowHeight + 4,
                      width: islandWidth - horizontalPadding * 2,
                      height: seekBarHeight)
    }

    /// The title and artist block. Pressable for the same reason the cover is:
    /// it is the other half of "this is what's playing, and where from".
    static func mediaTitleFrame(islandWidth: CGFloat,
                                sections: ControlCenterSections) -> CGRect? {
        guard let row = rowTop(.media, sections) else { return nil }
        let x = horizontalPadding + mediaArtworkSide + 12
        let width = islandWidth - x - horizontalPadding - transportWidth - 12
        return CGRect(x: x, y: row, width: max(0, width), height: mediaRowHeight)
    }

    /// The control center's cover, same size the media row draws it at.
    static let mediaArtworkSide: CGFloat = 44

    static func artworkFrame(_ sections: ControlCenterSections) -> CGRect? {
        guard let row = rowTop(.media, sections) else { return nil }
        return CGRect(x: horizontalPadding,
                      y: row + (mediaRowHeight - mediaArtworkSide) / 2,
                      width: mediaArtworkSide, height: mediaArtworkSide)
    }

    /// The upcoming-event row.
    static func calendarRowFrame(islandWidth: CGFloat,
                                 sections: ControlCenterSections) -> CGRect {
        let row = rowTop(.calendar, sections) ?? 0
        return CGRect(x: horizontalPadding, y: row,
                      width: islandWidth - horizontalPadding * 2, height: calendarRowHeight)
    }
}

/// Everything the control center draws.
///
/// Laid out absolutely rather than with stacks: the hit rects are computed from
/// the same metrics, and a stack's own spacing decisions would quietly move the
/// pixels out from under them. Nothing here takes a press — AppKit routes those
/// by geometry — so hover state is passed in rather than observed.
struct ControlCenterView: View {

    @ObservedObject var model: IslandModel
    var islandWidth: CGFloat
    var sections: ControlCenterSections

    private var contentWidth: CGFloat {
        islandWidth - ControlCenterMetrics.horizontalPadding * 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            header(Strings.nowPlaying)
                .offset(x: ControlCenterMetrics.horizontalPadding, y: 0)

            mediaRow
                .frame(width: contentWidth, height: ControlCenterMetrics.mediaRowHeight)
                .offset(x: ControlCenterMetrics.horizontalPadding,
                        y: (ControlCenterMetrics.rowTop(.media, sections) ?? 0))

            ForEach(Array(ControlCenterMetrics.transportFrames(islandWidth: islandWidth,
                                                               sections: sections).enumerated()),
                    id: \.offset) { _, item in
                TransportGlyph(symbol: transportSymbol(item.command),
                               size: item.command == .playPause ? 15 : 13,
                               isHovered: model.hoveredControl == .transport(item.command))
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
                    .opacity(model.nowPlaying == nil ? 0.3 : 1)
            }

            if model.nowPlaying?.hasProgress == true { mediaSeekBar }

            if sections.calendar { calendarSection }
            if sections.timer { timerSection }
            if sections.shelf { shelfSection }

            header(Strings.system)
                .offset(x: ControlCenterMetrics.horizontalPadding,
                        y: (ControlCenterMetrics.headerTop(.system, sections) ?? 0))

            let tiles = model.systemTiles
            let frames = ControlCenterMetrics.tileFrames(islandWidth: islandWidth,
                                                         count: tiles.count,
                                                         sections: sections)
            ForEach(Array(zip(tiles, frames)), id: \.0) { tile, frame in
                tileView(tile)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Media

    @ViewBuilder
    private var mediaRow: some View {
        if let track = model.nowPlaying {
            HStack(spacing: 12) {
                ArtworkView(image: track.artwork,
                            side: ControlCenterMetrics.mediaArtworkSide, cornerRadius: 9)
                    .overlay(pressableGlow(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)

                    Text(track.source.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, ControlCenterMetrics.transportWidth + 12)
        } else {
            HStack(spacing: 12) {
                ArtworkView(image: nil, side: 44, cornerRadius: 9)

                Text(Strings.nothingPlaying)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))

                Spacer(minLength: 0)
            }
        }
    }

    private func transportSymbol(_ command: TransportCommand) -> String {
        switch command {
        case .previous:  return "backward.fill"
        case .next:      return "forward.fill"
        case .playPause: return (model.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill"
        case .seek:      return ""
        }
    }

    /// The scrubber and its two times, under the media row.
    ///
    /// Reading `model.mediaTick` is what keeps it moving: the playhead is
    /// derived from the clock, so SwiftUI has nothing to invalidate on unless
    /// something published changes.
    @ViewBuilder
    private var mediaSeekBar: some View {
        if let track = model.nowPlaying,
           let frame = ControlCenterMetrics.mediaSeekFrame(islandWidth: islandWidth,
                                                           sections: sections) {
            let hovered = model.hoveredControl == .seek
            let _ = model.mediaTick

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(hovered ? 1 : 0.75))
                    .frame(width: frame.width * (track.progress ?? 0))
            }
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(y: hovered ? 1.8 : 1, anchor: .center)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .overlay(alignment: .bottomLeading) { seekTime(Self.clock(track.elapsedNow)) }
            .overlay(alignment: .bottomTrailing) {
                seekTime(Self.clock(track.duration.map { $0 - (track.elapsedNow ?? 0) },
                                    negative: true))
            }
            .offset(x: frame.minX, y: frame.minY)
        }
    }

    private func seekTime(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundColor(.white.opacity(0.45))
            .offset(y: 13)
    }

    private static func clock(_ seconds: TimeInterval?, negative: Bool = false) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "" }
        let total = Int(seconds.rounded())
        let sign = negative ? "-" : ""
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%@%d:%02d:%02d", sign, hours, minutes, secs)
            : String(format: "%@%d:%02d", sign, minutes, secs)
    }

    /// A press target with no affordance is a press target nobody finds, so the
    /// cover lifts a little under the pointer.
    @ViewBuilder
    private func pressableGlow(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(model.hoveredControl == .artwork ? 0.22 : 0))
            .animation(.easeOut(duration: 0.12), value: model.hoveredControl)
    }

    // MARK: Timer

    @ViewBuilder
    private var timerSection: some View {
        header(Strings.timer)
            .offset(x: ControlCenterMetrics.horizontalPadding,
                    y: (ControlCenterMetrics.headerTop(.timer, sections) ?? 0))

        if let countdown = model.countdown {
            let readout = ControlCenterMetrics.timerReadoutFrame(islandWidth: islandWidth,
                                                                 sections: sections)

            HStack(spacing: 12) {
                Text(countdown.text)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .opacity(countdown.isRunning ? 1 : 0.55)

                MeterBar(value: countdown.progress, height: 4)

                Spacer(minLength: 0)
            }
            .frame(width: readout.width, height: readout.height)
            .offset(x: readout.minX, y: readout.minY)

            ForEach(Array(ControlCenterMetrics.timerControlFrames(islandWidth: islandWidth,
                                                                   sections: sections).enumerated()),
                    id: \.offset) { _, item in
                TransportGlyph(symbol: timerSymbol(item.action),
                               size: item.action == .toggle ? 14 : 12,
                               isHovered: model.hoveredControl == .timer(item.action))
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
            }
        } else {
            ForEach(Array(ControlCenterMetrics.timerPresetFrames(sections).enumerated()),
                    id: \.offset) { _, item in
                presetButton(item.minutes,
                             hovered: model.hoveredControl == .timer(.start(minutes: item.minutes)))
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
            }
        }
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarSection: some View {
        header(Strings.upNext)
            .offset(x: ControlCenterMetrics.horizontalPadding,
                    y: ControlCenterMetrics.headerTop(.calendar, sections) ?? 0)

        if let event = model.upcomingEvent {
            let frame = ControlCenterMetrics.calendarRowFrame(islandWidth: islandWidth,
                                                              sections: sections)
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let location = event.location {
                        Text(location)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.timeText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)

                    Text(event.relativeText)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
        }
    }

    // MARK: Shelf

    @ViewBuilder
    private var shelfSection: some View {
        // The header carries the selection count, because the footer's words
        // ("Copy", "AirDrop") silently change meaning once chips are picked out
        // and nothing else on the row says so.
        header(model.shelfSelection.isEmpty
               ? Strings.shelf
               : "\(Strings.shelf) · \(Strings.selectedCount(model.shelfSelection.count))")
            .offset(x: ControlCenterMetrics.horizontalPadding,
                    y: (ControlCenterMetrics.headerTop(.shelf, sections) ?? 0))

        ForEach(Array(ControlCenterMetrics.shelfActionFrames(islandWidth: islandWidth,
                                                             sections: sections).enumerated()),
                id: \.offset) { _, item in
            actionLabel(title(for: item.action),
                        hovered: model.hoveredControl == .shelf(item.action))
                .frame(width: item.frame.width, height: item.frame.height)
                .offset(x: item.frame.minX, y: item.frame.minY)
        }

        let chips = ControlCenterMetrics.shelfChipFrames(count: model.shelf.count, sections: sections)
        ForEach(Array(zip(model.shelf.indices, chips)), id: \.0) { index, frame in
            let item = model.shelf[index]
            let hovered = model.hoveredControl == .shelf(.open(index: index))

            chipView(item, hovered: hovered,
                     selected: model.shelfSelection.contains(item.id))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)

            if hovered {
                let remove = ControlCenterMetrics.shelfRemoveFrame(chip: frame)
                removeBadge(hovered: model.hoveredControl == .shelf(.remove(index: index)))
                    .frame(width: remove.width, height: remove.height)
                    .offset(x: remove.minX, y: remove.minY)
            }
        }
    }

    private func chipView(_ item: ShelfItem, hovered: Bool, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 26, height: 26)

            Text(item.name)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(selected ? 1 : 0.75))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.22 : (hovered ? 0.16 : 0.08)))
        )
        // A ring rather than only a brighter fill: hover already uses fill, and
        // a selected chip must still read as selected while the pointer is on it.
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private func removeBadge(hovered: Bool) -> some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(Color.white.opacity(hovered ? 1 : 0.75),
                             Color.black.opacity(0.85))
    }

    private func actionLabel(_ title: String, hovered: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(hovered ? 1 : 0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func title(for action: ShelfAction) -> String {
        switch action {
        case .copyAll:    return Strings.copy
        case .airDropAll: return Strings.airDrop
        case .clear:      return Strings.clear
        default:          return ""
        }
    }

    private func timerSymbol(_ action: TimerAction) -> String {
        switch action {
        case .toggle:  return (model.countdown?.isRunning ?? false) ? "pause.fill" : "play.fill"
        case .restart: return "arrow.counterclockwise"
        case .cancel:  return "xmark"
        case .start:   return "timer"
        }
    }

    private func presetButton(_ minutes: Int, hovered: Bool) -> some View {
        Text(Strings.minutesShort(minutes))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(hovered ? 1 : 0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.18 : 0.10))
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    // MARK: Tiles

    private func tileView(_ tile: SystemTile) -> some View {
        let active = model.hoveredControl == .tile(tile)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: symbol(for: tile))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))

                Text(value(for: tile))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white)

                Spacer(minLength: 0)
            }

            MeterBar(value: meter(for: tile), height: tile.isAdjustable ? 6 : 5)
        }
        .padding(.horizontal, ControlCenterMetrics.tileInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(active && tile.isAdjustable ? 0.15 : 0.08))
        )
        .animation(.easeOut(duration: 0.12), value: active)
    }

    private func symbol(for tile: SystemTile) -> String {
        switch tile {
        case .volume:     return IslandSymbol.volume(level: model.volume ?? 0, muted: false)
        case .brightness: return IslandSymbol.brightness(level: model.brightness ?? 0)
        case .battery:    return model.power.map(IslandSymbol.battery) ?? "battery.50"
        case .bluetooth:  return IslandSymbol.device(named: connectedDevice?.name ?? "")
        }
    }

    private func value(for tile: SystemTile) -> String {
        switch tile {
        case .volume:     return (model.volume ?? 0).percentText
        case .brightness: return (model.brightness ?? 0).percentText
        case .battery:    return "\(model.power?.percentage ?? 0)%"
        case .bluetooth:  return connectedDevice?.headline.map { "\($0)%" } ?? "—"
        }
    }

    private func meter(for tile: SystemTile) -> Double {
        switch tile {
        case .volume:     return model.volume ?? 0
        case .brightness: return model.brightness ?? 0
        case .battery:    return Double(model.power?.percentage ?? 0) / 100
        case .bluetooth:  return Double(connectedDevice?.headline ?? 0) / 100
        }
    }

    /// The connected device the tile speaks for — the first one reporting a level.
    private var connectedDevice: BluetoothDevice? {
        model.devices.first(where: { $0.headline != nil })
    }

    private func header(_ title: String) -> some View {
        // Locale-aware: Turkish uppercases "i" to "İ", so a plain uppercased()
        // would render SISTEM where the language calls for SİSTEM.
        Text(title.uppercased(with: Localization.locale))
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.white.opacity(0.4))
            .frame(height: ControlCenterMetrics.headerHeight, alignment: .leading)
    }
}