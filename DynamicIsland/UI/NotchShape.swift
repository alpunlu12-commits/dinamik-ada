//
//  NotchShape.swift
//  DynamicIsland
//
//  The island's outline: convex at the bottom, **concave** where it meets the
//  top of the screen.
//
//  The two corners are not the same kind of corner, and that is the whole idea.
//  The bottom corners round the way any floating panel's would — they are the
//  expressive ones, opening up as the island grows. The top corners do the
//  opposite: instead of curving in and leaving the island sitting *on* the
//  bezel like a tab, they flare outward into the screen, so the island reads as
//  something the top edge widens into. It is the shape the hardware notch
//  itself has, and it is what stops a black rectangle at the top of the display
//  from looking stuck on.
//
//  The flares are drawn *outside* the rect they are given, by exactly the top
//  radius on each side. That keeps the island's body at its full width — an
//  inset body would quietly narrow every payload — and the overhang is well
//  inside the panel's shadow padding, so nothing is clipped. Those few points
//  are decoration and sit outside the hit rect, which is correct: there is
//  nothing to press out there.
//
//  Both radii are exposed through `animatableData` so the spring interpolates
//  the outline itself instead of cross-fading between two shapes. A compact
//  island passes a top radius of zero, which collapses the flares to nothing —
//  the pill sits inside the physical cutout, where a shoulder would only smear
//  black onto the menu bar beside the camera.
//

import SwiftUI

struct NotchShape: Shape {

    /// Size of the concave flare where the island meets the top of the screen.
    var topRadius: CGFloat

    /// Ordinary convex rounding on the two bottom corners.
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let bottom = max(0, min(bottomRadius, min(rect.width, rect.height) / 2))
        // The flare is bounded by height alone, not by width: it grows outward,
        // so a wide island never runs out of room for it.
        let top = max(0, min(topRadius, rect.height / 2))

        var path = Path()

        // SwiftUI's path space is y-down, so *increasing* angles run clockwise
        // on screen — which is why the convex corners below pass
        // `clockwise: false` and the concave ones, which sweep backwards,
        // pass `clockwise: true`.

        // Left side, bottom to top.
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))

        // Top-left flare: out and up, into the screen.
        path.addArc(center: CGPoint(x: rect.minX - top, y: rect.minY + top),
                    radius: top,
                    startAngle: .degrees(0), endAngle: .degrees(270),
                    clockwise: true)

        // The top edge, overhanging the body by the flare on each side.
        path.addLine(to: CGPoint(x: rect.maxX + top, y: rect.minY))

        // Top-right flare: back down and in.
        path.addArc(center: CGPoint(x: rect.maxX + top, y: rect.minY + top),
                    radius: top,
                    startAngle: .degrees(270), endAngle: .degrees(180),
                    clockwise: true)

        // Right side, down to the convex bottom corners.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(center: CGPoint(x: rect.maxX - bottom, y: rect.maxY - bottom),
                    radius: bottom,
                    startAngle: .degrees(0), endAngle: .degrees(90),
                    clockwise: false)

        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bottom, y: rect.maxY - bottom),
                    radius: bottom,
                    startAngle: .degrees(90), endAngle: .degrees(180),
                    clockwise: false)

        path.closeSubpath()
        return path
    }
}
