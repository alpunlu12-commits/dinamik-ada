//
//  IslandComponents.swift
//  DynamicIsland
//
//  The small pieces the island's payloads are built from.
//
//  Everything here is deliberately drawn the way macOS draws it: capsule meters
//  with a translucent track and an opaque fill, stock SF Symbols rather than
//  custom glyphs, monospaced digits so numbers don't jitter as they count. The
//  island is always dark, so colours are explicit white-on-black rather than
//  semantic — it must look identical in Light and Dark mode.
//

import SwiftUI

// MARK: - Meter

/// The bar macOS uses for volume and brightness: a dim track with a solid fill.
struct MeterBar: View {

    var value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))

                Capsule()
                    .fill(Color.white)
                    // Never let the fill collapse below a round dot, the way the
                    // system HUD keeps a nub visible at zero.
                    .frame(width: max(height, proxy.size.width * value.clampedToUnit))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Waveform

/// Four bars breathing at slightly different rates — the compact accessory that
/// says "audio is playing" without spending any width.
struct WaveformView: View {

    var isPlaying: Bool

    /// The cover's own colours, spread across the bars. Empty for a cover with
    /// no usable colour — and for no cover at all — in which case the bars stay
    /// white, exactly as they were before this existed.
    var palette: ArtworkPalette = .none

    /// Resting and peak heights per bar. Uneven on purpose: equal bars read as a
    /// loading indicator rather than sound.
    private let bars: [(rest: CGFloat, peak: CGFloat)] = [
        (4, 12), (7, 16), (5, 10), (9, 14),
    ]

    @State private var animating = false

    /// Each bar takes its colour from its position along the palette, so four
    /// bars read as one gradient rather than four unrelated colours.
    private func color(_ index: Int) -> Color {
        guard bars.count > 1 else { return palette.color(at: 0) }
        return palette.color(at: Double(index) / Double(bars.count - 1))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(color(index))
                    .frame(width: 2.5, height: animating ? bars[index].peak : bars[index].rest)
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.42 + Double(index) * 0.06).repeatForever(autoreverses: true)
                            : .default,
                        value: animating
                    )
            }
        }
        .frame(height: 16)
        .onAppear { animating = isPlaying }
    }
}

// MARK: - Artwork

/// Album art with a placeholder that matches the island rather than a grey box.
struct ArtworkView: View {

    var image: NSImage?
    var side: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.42))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
    }
}

// MARK: - Stat chip

/// A glanceable icon + value pill, used when the island is hovered and there is
/// nothing playing.
struct StatChip: View {

    var symbol: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 14)

            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            Capsule().fill(Color.white.opacity(0.10))
        )
    }
}

// MARK: - Transport

/// A transport control's appearance. It is deliberately not a Button: presses
/// and hover both arrive from AppKit (see ControlCenterControls), because
/// SwiftUI's gesture and tracking machinery is unreliable inside a
/// non-activating panel that never becomes key.
struct TransportGlyph: View {

    var symbol: String
    var size: CGFloat = 13
    var isHovered: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(.white.opacity(isHovered ? 1 : 0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Circle().fill(Color.white.opacity(isHovered ? 0.14 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Symbols

enum IslandSymbol {

    static func volume(level: Double, muted: Bool) -> String {
        if muted || level <= 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func brightness(level: Double) -> String {
        level < 0.34 ? "sun.min.fill" : "sun.max.fill"
    }

    /// Apple ships a glyph for each AirPods model; anything else gets headphones.
    static func device(named name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods pro")  { return "airpodspro" }
        if lowered.contains("airpods max")  { return "airpodsmax" }
        if lowered.contains("airpods")      { return "airpods" }
        if lowered.contains("beats")        { return "beats.headphones" }
        return "headphones"
    }

    static func battery(_ snapshot: PowerSnapshot) -> String {
        if snapshot.isCharging { return "battery.100.bolt" }
        switch snapshot.percentage {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }
}

// MARK: - Helpers

extension Double {
    /// Clamped to 0…1, which every meter in the island expects.
    var clampedToUnit: Double { Swift.min(Swift.max(self, 0), 1) }

    /// Rendered the way macOS renders a percentage: whole numbers, no decimals.
    var percentText: String { "\(Int((clampedToUnit * 100).rounded()))%" }

    /// Rounded to the nearest 5%.
    ///
    /// macOS moves volume and brightness in sixteenths — 6.25% a press — so the
    /// island would otherwise count 6, 13, 19, 25, 31… Rounding only the label
    /// doesn't fix it (the sequence becomes 5, 15, 20, 30… with uneven gaps);
    /// the value itself has to sit on the grid. Once it does, the system's own
    /// ±6.25% lands within half a step of the next multiple of five, so every
    /// press moves exactly 5%.
    var snappedToFivePercent: Double {
        (clampedToUnit * 20).rounded() / 20
    }

    /// True when the value is already on the 5% grid, within floating-point dust.
    var isOnFivePercentGrid: Bool {
        abs(clampedToUnit - snappedToFivePercent) < 0.002
    }
}

extension Double {
    /// A change big enough to be a keypress rather than an app fading audio.
    static let discreteStepThreshold = 0.03
}

// MARK: - Privacy

/// The camera and microphone dots, in the colours macOS uses for its own
/// indicator so they read as the same signal rather than a second opinion.
struct PrivacyDots: View {

    var camera: Bool
    var microphone: Bool

    var body: some View {
        HStack(spacing: 5) {
            if camera {
                Image(systemName: "video.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
            }
            if microphone {
                Image(systemName: "mic.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 1.00, green: 0.62, blue: 0.04))
            }
        }
    }
}

// MARK: - Countdown

/// The expanded countdown: time on the left, progress filling the rest.
struct CountdownPayload: View {

    var countdown: CountdownState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 20)

            Text(countdown.text)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                .opacity(countdown.isRunning ? 1 : 0.55)

            MeterBar(value: countdown.progress, height: 5)

            if !countdown.isRunning {
                Text(Strings.paused)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Drop zone

/// What the island turns into while a file drag is in flight.
///
/// Deliberately the loudest thing the island ever draws: it is the one state the
/// user is aiming at with a file in hand, and it has to read as a target from
/// the corner of the eye.
struct DropZonePayload: View {

    var highlighted: Bool
    var fileCount: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: highlighted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.white.opacity(highlighted ? 1 : 0.8))
                .scaleEffect(highlighted ? 1.12 : 1)

            Text(highlighted ? Strings.releaseToKeep : Strings.dropFilesHere)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            if fileCount > 0 {
                Text(Strings.files(fileCount))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundColor(.white.opacity(highlighted ? 0.55 : 0.25))
                .padding(10)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: highlighted)
    }
}

// MARK: - Shelf accessory

/// The compact pill's badge for a non-empty shelf.
struct ShelfAccessory: View {

    var count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Text("\(count)")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 10, height: 10)
                .background(Circle().fill(Color.white))
                .offset(x: 5, y: -4)
        }
    }
}

/// The compact glyph shown while something is downloading.
///
/// An arrow that travels down a short track and fades out at the bottom, rather
/// than a spinner: the island is a black pill a few points tall, and a spinner
/// at that size is a grey smudge. Motion in the direction of the thing being
/// described reads at a glance.
///
/// Every part of it is bounded by an explicit frame. The first version stacked
/// the arrow *above* a tray glyph with a fixed negative offset, which put it
/// outside the notch strip: it was clipped by the island's own outline and read
/// as a broken half-symbol on screen. Nothing here may leave `side`.
struct DownloadAccessory: View {

    /// The square the glyph lives in, matching the other accessories.
    var side: CGFloat = 18

    @State private var animating = false

    var body: some View {
        VStack(spacing: 1.5) {
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .offset(y: animating ? 3 : -2)
                .opacity(animating ? 0 : 1)
                .frame(height: side * 0.5)

            // A lip for the arrow to fall into, so the motion has a destination.
            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: side * 0.62, height: 1.8)
        }
        .frame(width: side, height: side)
        .clipped()
        .onAppear {
            withAnimation(.easeIn(duration: 0.9).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}
