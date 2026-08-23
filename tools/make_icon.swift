//
//  make_icon.swift
//  Dinamik Ada
//
//  Draws the app icon and writes DynamicIsland/Resources/AppIcon.icns.
//
//  The icon is generated rather than committed as a binary blob so it can be
//  adjusted by editing numbers here — same reasoning as tools/generate_pbxproj.py.
//  Re-run it after any change:
//
//      swift tools/make_icon.swift
//
//  What it draws, and why: the app's whole subject is the notch, so the icon is
//  the notch — a black island on a lit background, with the same four bars the
//  compact pill shows while something is playing, in the same teal-to-pink the
//  album palette tends to land on.
//
//  Everything is expressed as a fraction of the canvas, so the 16 pt version is
//  the 1024 pt version and not a separate drawing. The one concession to size is
//  the hairline around the island: at 16 pt a half-point stroke disappears into
//  the background, so it is scaled up relative to the canvas and only drawn
//  where it can be seen.
//

import AppKit

// MARK: - Geometry, as fractions of the canvas

/// macOS icons leave a margin: the artwork sits in the middle ~82% of the
/// canvas, which is what makes an icon look right beside Apple's own.
let contentInset: CGFloat = 0.09
/// Corner radius of that artwork square, as a fraction of the canvas.
let squircleRadius: CGFloat = 0.185

/// The island, as fractions of the canvas.
///
/// It is flush with the top of the artwork square, not floating in the middle.
/// That is the whole reading: the inverted top corners only mean anything when
/// they have an edge to fuse into — hung in open space they curve into nothing
/// and the shape reads as a black box rather than as a notch.
let islandWidth: CGFloat = 0.50
let islandHeight: CGFloat = 0.34
let islandBottomRadius: CGFloat = 0.095
/// The concave flare where the island meets the top edge.
let islandTopFlare: CGFloat = 0.045

let barWidth: CGFloat = 0.032
let barGap: CGFloat = 0.038
/// Bar heights as fractions of the canvas, uneven the way the real waveform is.
let barHeights: [CGFloat] = [0.075, 0.115, 0.055, 0.095]

// MARK: - Colours

func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: 1)
}

/// Background: a lit graphite, brighter at the top left so the island reads as
/// sitting on a surface rather than floating in a void.
let backgroundTop = srgb(78, 80, 88)
let backgroundBottom = srgb(24, 24, 27)

/// The bars, teal to pink — where the album palette usually lands, and the one
/// place colour enters the interface.
let barStart = srgb(43, 200, 214)
let barEnd = srgb(255, 59, 107)

/// Blend around the colour wheel rather than straight through RGB.
///
/// Straight RGB interpolation from teal to pink passes through grey, so the two
/// middle bars came out washed out and the row read as a fade to nothing.
/// Interpolating hue keeps every step fully saturated — teal, blue, purple,
/// pink — which is what the album palette actually does.
func blendHue(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    var ha: CGFloat = 0, sa: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
    var hb: CGFloat = 0, sb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
    a.usingColorSpace(.sRGB)!.getHue(&ha, saturation: &sa, brightness: &ba, alpha: &aa)
    b.usingColorSpace(.sRGB)!.getHue(&hb, saturation: &sb, brightness: &bb, alpha: &ab)
    return NSColor(hue: ha + (hb - ha) * t,
                   saturation: sa + (sb - sa) * t,
                   brightness: ba + (bb - ba) * t,
                   alpha: 1)
}

// MARK: - Drawing

/// The island outline: convex at the bottom, concave where it meets the top.
func islandPath(in rect: CGRect, flare: CGFloat, bottom: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    // AppKit is y-up, so "top" here is maxY.
    let top = rect.maxY, bot = rect.minY

    path.move(to: CGPoint(x: rect.minX, y: bot + bottom))
    // Bottom-left convex corner.
    path.appendArc(withCenter: CGPoint(x: rect.minX + bottom, y: bot + bottom),
                   radius: bottom, startAngle: 180, endAngle: 270)
    path.line(to: CGPoint(x: rect.maxX - bottom, y: bot))
    path.appendArc(withCenter: CGPoint(x: rect.maxX - bottom, y: bot + bottom),
                   radius: bottom, startAngle: 270, endAngle: 360)
    path.line(to: CGPoint(x: rect.maxX, y: top - flare))
    // Top-right flare, curving outward.
    path.appendArc(withCenter: CGPoint(x: rect.maxX + flare, y: top - flare),
                   radius: flare, startAngle: 180, endAngle: 90, clockwise: true)
    path.line(to: CGPoint(x: rect.minX - flare, y: top))
    // Top-left flare.
    path.appendArc(withCenter: CGPoint(x: rect.minX - flare, y: top - flare),
                   radius: flare, startAngle: 90, endAngle: 0, clockwise: true)
    path.close()
    return path
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let context = NSGraphicsContext.current!
    context.imageInterpolation = .high
    context.cgContext.setShouldAntialias(true)

    // The artwork square.
    let inset = size * contentInset
    let art = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: art,
                                xRadius: size * squircleRadius,
                                yRadius: size * squircleRadius)
    squircle.addClip()

    NSGradient(colors: [backgroundTop, backgroundBottom])?
        .draw(in: art, angle: -90)

    // A soft highlight along the top edge, so the surface has a direction.
    if let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16),
                                       NSColor.white.withAlphaComponent(0)]) {
        sheen.draw(in: CGRect(x: art.minX, y: art.midY,
                              width: art.width, height: art.height / 2), angle: -90)
    }

    // The island, hanging from the top edge of the artwork square.
    let iw = size * islandWidth
    let ih = size * islandHeight
    let islandRect = CGRect(x: (size - iw) / 2,
                            y: art.maxY - ih,
                            width: iw, height: ih)
    let island = islandPath(in: islandRect,
                            flare: size * islandTopFlare,
                            bottom: size * islandBottomRadius)
    NSColor.black.setFill()
    island.fill()

    // Hairline, scaled so it survives at 16 pt and skipped where it cannot.
    if size >= 32 {
        NSColor.white.withAlphaComponent(0.12).setStroke()
        island.lineWidth = max(1, size * 0.004)
        island.stroke()
    }

    // The bars, centred in the island and coloured across the palette.
    let totalBars = CGFloat(barHeights.count) * size * barWidth
        + CGFloat(barHeights.count - 1) * size * barGap
    var x = islandRect.midX - totalBars / 2

    // Centred on the island's body, ignoring the flared strip at the very top.
    let barsCentre = islandRect.minY + (islandRect.height - size * islandTopFlare) / 2

    for (index, height) in barHeights.enumerated() {
        let w = size * barWidth
        let h = size * height
        let bar = CGRect(x: x, y: barsCentre - h / 2, width: w, height: h)
        let fraction = barHeights.count > 1
            ? CGFloat(index) / CGFloat(barHeights.count - 1) : 0

        blendHue(barStart, barEnd, fraction).setFill()
        NSBezierPath(roundedRect: bar, xRadius: w / 2, yRadius: w / 2).fill()
        x += w + size * barGap
    }

    image.unlockFocus()
    return image
}

// MARK: - Write the iconset

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// (point size, scale) — the ten images an .icns wants.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    let image = drawIcon(size: CGFloat(pixels))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { fatalError("could not encode \(pixels)px") }

    let name = scale == 1
        ? "icon_\(points)x\(points).png"
        : "icon_\(points)x\(points)@2x.png"
    try! png.write(to: iconset.appendingPathComponent(name))
}

let output = root.appendingPathComponent("DynamicIsland/Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(output.path)")
