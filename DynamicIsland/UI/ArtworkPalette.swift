//
//  ArtworkPalette.swift
//  DynamicIsland
//
//  The two or three colours an album cover is actually *about*, used to tint
//  the waveform on the compact pill.
//
//  Why not the average colour: averaging a cover with a red corner and a blue
//  field gives muddy purple — a colour that appears nowhere on the sleeve. What
//  reads as "this record's colour" is the dominant *hues*, so pixels are binned
//  by hue and the fullest bins win.
//
//  Three filters do most of the work, and each exists because of a specific way
//  the naive version looks wrong:
//
//    • Near-black and near-white pixels are ignored. Most sleeves are mostly
//      background, and without this every cover comes back grey.
//    • Washed-out pixels are ignored for the same reason — a pale wash covers
//      a lot of area and says little about the record.
//    • Whatever survives is lifted to a floor of saturation and brightness,
//      because the result is drawn on a black pill at 2.5 pt wide. A colour
//      that is technically correct but invisible there has failed.
//
//  A cover with no usable colour at all — a black-and-white photograph, a plain
//  sleeve — yields an empty palette, and the waveform stays white. Degrading to
//  the old appearance is the right answer; inventing a hue is not.
//
//  Extraction is cheap (a 24×24 redraw, 576 pixels) but not free, and the
//  answer only changes when the track does, so results are cached by track key.
//  The cache takes a lock rather than being pinned to the main actor: it is read
//  from `IslandModel.compactAccessories`, which the controller calls while
//  building hit regions, and forcing that whole path onto the main actor to
//  satisfy a colour cache would be the tail wagging the dog.
//

import AppKit
import SwiftUI

/// The colours pulled off one cover, most prominent first.
struct ArtworkPalette: Equatable {

    /// Empty when the cover had no colour worth using.
    var colors: [NSColor]

    static let none = ArtworkPalette(colors: [])

    var isEmpty: Bool { colors.isEmpty }

    /// The colour at `fraction` along the palette, so a row of bars can be
    /// spread across it rather than each bar picking one.
    func color(at fraction: Double) -> Color {
        guard !colors.isEmpty else { return Color.white.opacity(0.85) }
        guard colors.count > 1 else { return Color(colors[0]) }

        let position = fraction.clampedToUnit * Double(colors.count - 1)
        let index = min(Int(position), colors.count - 2)
        return Color(Self.blend(colors[index], colors[index + 1],
                                amount: position - Double(index)))
    }

    private static func blend(_ a: NSColor, _ b: NSColor, amount: Double) -> NSColor {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return a }
        let t = CGFloat(amount.clampedToUnit)
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: 1)
    }
}

enum ArtworkPaletteExtractor {

    /// Cached per track. Bounded because a long listening session would
    /// otherwise keep every cover's palette for the life of the process.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: ArtworkPalette] = [:]
    nonisolated(unsafe) private static var order: [String] = []
    private static let cacheLimit = 24

    /// Side of the square the cover is redrawn into. Small on purpose: this is
    /// a question about broad areas of colour, and 576 pixels answer it as well
    /// as a million would.
    private static let sampleSide = 24

    /// Hue bins. Twelve is 30° each — wide enough that a gradient stays in one
    /// bin, narrow enough to keep red and orange apart.
    private static let hueBins = 12

    /// Below these a pixel is background rather than colour.
    ///
    /// There is deliberately no brightness *ceiling*. An earlier version had
    /// one, to skip near-white pixels, and it silently discarded every fully
    /// saturated colour: a solid red sleeve renders at brightness 1.0, so the
    /// whole cover was filtered away and came back with no palette at all.
    /// Near-white is low saturation, which the first test already catches.
    private static let minSaturation: CGFloat = 0.18
    private static let minBrightness: CGFloat = 0.15

    /// Floors applied to the result so it survives being drawn on black.
    private static let outputSaturationFloor: CGFloat = 0.55
    private static let outputBrightnessFloor: CGFloat = 0.72

    static func palette(for image: NSImage, key: String) -> ArtworkPalette {
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached { return cached }

        // Extracted outside the lock: it is the slow half, and computing the
        // same cover twice in a race is harmless — both answers are identical.
        let palette = extract(from: image)

        lock.lock()
        if cache[key] == nil {
            cache[key] = palette
            order.append(key)
            if order.count > cacheLimit {
                cache.removeValue(forKey: order.removeFirst())
            }
        }
        lock.unlock()
        return palette
    }

    // MARK: Extraction

    private static func extract(from image: NSImage) -> ArtworkPalette {
        guard let pixels = sample(image) else { return .none }

        // Per hue bin: accumulated weight, and the summed components of the
        // pixels that landed in it, so the bin can report its own average
        // rather than the middle of its hue range.
        var weights = [CGFloat](repeating: 0, count: hueBins)
        var hueSum = [CGFloat](repeating: 0, count: hueBins)
        var satSum = [CGFloat](repeating: 0, count: hueBins)
        var brightSum = [CGFloat](repeating: 0, count: hueBins)

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let color = NSColor(srgbRed: CGFloat(pixels[offset]) / 255,
                                green: CGFloat(pixels[offset + 1]) / 255,
                                blue: CGFloat(pixels[offset + 2]) / 255,
                                alpha: 1)

            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            guard saturation >= minSaturation, brightness >= minBrightness else { continue }

            // A vivid pixel says more about the record than a dull one, so it
            // counts for more than its area.
            let weight = saturation * brightness
            let bin = min(Int(hue * CGFloat(hueBins)), hueBins - 1)

            weights[bin] += weight
            hueSum[bin] += hue * weight
            satSum[bin] += saturation * weight
            brightSum[bin] += brightness * weight
        }

        let ranked = weights.indices
            .filter { weights[$0] > 0 }
            .sorted { weights[$0] > weights[$1] }

        guard let strongest = ranked.first else { return .none }

        // Anything much fainter than the leader is noise, not a second colour.
        let floor = weights[strongest] * 0.18
        let chosen = ranked.prefix(3).filter { weights[$0] >= floor }

        let colors = chosen.map { bin -> NSColor in
            let weight = weights[bin]
            return usable(hue: hueSum[bin] / weight,
                          saturation: satSum[bin] / weight,
                          brightness: brightSum[bin] / weight)
        }
        return ArtworkPalette(colors: colors)
    }

    /// Lift a colour to something that reads as itself on a black pill.
    private static func usable(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> NSColor {
        NSColor(hue: hue,
                saturation: max(saturation, outputSaturationFloor),
                brightness: max(brightness, outputBrightnessFloor),
                alpha: 1)
    }

    /// Redraw the cover small and hand back its raw RGBA bytes.
    private static func sample(_ image: NSImage) -> [UInt8]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        let ok: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? pixels : nil
    }
}

extension NowPlaying {
    /// The cover's own colours. Cached by track, so reading this on every
    /// render costs a dictionary lookup.
    var palette: ArtworkPalette {
        guard let artwork else { return .none }
        return ArtworkPaletteExtractor.palette(for: artwork, key: trackKey)
    }
}
