//
//  IslandLayout.swift
//  DynamicIsland
//
//  Single source of truth for island geometry.
//
//  Two coordinate spaces are used:
//    • Global (Cocoa screen) coordinates — origin bottom-left of the main
//      display. Used for the panel frame and for pointer hit tests.
//    • Panel-local coordinates — origin bottom-left of the overlay panel.
//
//  The panel is always sized for the *largest* state so the island can grow and
//  shrink inside it without ever resizing the window (resizing a window every
//  animation frame looks terrible and drops frames).
//
//  The compact pill has two widths: bare, and with the leading/trailing media
//  accessories that flank the notch while something is playing. Every size query
//  therefore takes `hasAccessories`.
//

import Foundation
import CoreGraphics

struct IslandLayout: Equatable {

    var metrics: NotchMetrics
    var size: IslandSize
    /// Which optional rows the control center is reserving space for.
    var sections: ControlCenterSections
    /// What the expanded state is showing, which decides how wide it gets.
    var expandedPayload: ExpandedPayloadKind

    /// Slack around the island inside the panel so the drop shadow isn't clipped.
    static let shadowPadding: CGFloat = 28

    /// Widest the two compact slots can get together, used to size the panel.
    static let maxAccessoryWidth: CGFloat = 96

    // MARK: State sizes

    /// Hugs the real notch (or the simulated pill), plus accessories when media
    /// is playing.
    func compactSize(accessories: CompactAccessories) -> CGSize {
        CGSize(width: max(metrics.notchWidth, 120) + accessories.totalWidth,
               height: max(metrics.notchHeight, 28))
    }

    /// Sized to the payload rather than to the widest payload: a fixed width
    /// left black wings either side of anything short, which is most of them.
    var expandedSize: CGSize {
        let width = expandedPayload.width * (size == .small ? 0.88 : 1)
        return CGSize(width: max(width, compactSize(accessories: .none).width + 40),
                      height: notchHeight + expandedPayload.innerHeight)
    }

    /// Exactly as tall as its contents need — ControlCenterMetrics owns that
    /// number, so adding a row there resizes the island automatically.
    var controlCenterSize: CGSize {
        CGSize(width: size == .small ? 400 : 460,
               height: notchHeight + ControlCenterMetrics.contentHeight(sections))
    }

    /// Deliberately generous: the drop zone is the one state the user is aiming
    /// at with a file in hand, and a small target is a dropped file.
    var dropZoneSize: CGSize {
        CGSize(width: size == .small ? 380 : 440, height: notchHeight + 132)
    }

    func size(for state: IslandState, accessories: CompactAccessories) -> CGSize {
        switch state {
        case .compact:       return compactSize(accessories: accessories)
        case .expanded:      return expandedSize
        case .controlCenter: return controlCenterSize
        case .dropZone:      return dropZoneSize
        }
    }

    /// Height of the notch itself — the strip every payload has to stay below,
    /// because on a real notched Mac those points are physically covered.
    var notchHeight: CGFloat { max(metrics.notchHeight, 28) }

    // MARK: Corner radii

    /// Size of the concave flare where the island meets the top of the screen.
    ///
    /// Zero while compact: that pill sits inside the physical cutout, and a
    /// shoulder there would only paint black onto the menu bar beside the
    /// camera — the same reason the compact state draws no shadow. The flare
    /// grows in as the island opens, which is when it has screen to flare onto.
    func topRadius(for state: IslandState, accessories: CompactAccessories = .none) -> CGFloat {
        guard state == .compact else { return 10 }
        // A bare pill sits *inside* the physical cutout, where a flare would only
        // paint black onto the menu bar beside the camera — the same reason the
        // compact state draws no shadow. But the moment an accessory appears the
        // pill grows past the cutout on both sides, and those shoulders are on
        // real screen: left square they read as a hard, flat join. So the flare
        // follows the width, not the state.
        return accessories.isEmpty ? 0 : 8
    }

    /// Bottom corners are the expressive ones.
    func bottomRadius(for state: IslandState) -> CGFloat {
        switch state {
        case .compact:       return min(notchHeight / 2, 14)
        case .expanded:      return 22
        case .controlCenter: return 28
        case .dropZone:      return 26
        }
    }

    // MARK: Frames

    /// The overlay panel's frame, in global coordinates: top-centre of the
    /// island's screen, wide and tall enough for every state.
    var panelFrame: CGRect {
        let width = maxSize.width + Self.shadowPadding * 2
        let height = maxSize.height + Self.shadowPadding
        return CGRect(x: (metrics.notchCenterX - width / 2).rounded(),
                      y: metrics.screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// The island's rect for `state`, in panel-local coordinates: horizontally
    /// centred and pinned to the top edge of the panel (= top of the screen).
    /// Centred on the notch, not on the panel: the panel's origin is rounded to
    /// a whole point (window frames should be integral) and centring inside it
    /// would inherit that rounding error.
    func islandRect(for state: IslandState, accessories: CompactAccessories) -> CGRect {
        let panel = panelFrame
        let islandSize = size(for: state, accessories: accessories)
        return CGRect(x: metrics.notchCenterX - panel.minX - islandSize.width / 2
                        + centreShift(for: state, accessories: accessories),
                      y: panel.height - islandSize.height,
                      width: islandSize.width,
                      height: islandSize.height)
    }

    /// How far the compact pill slides off the notch's centre so that the strip
    /// *inside* it still lines up with the real cutout.
    ///
    /// The pill is one accessory slot, the notch, and the other accessory slot.
    /// Centring the whole thing on the notch only puts the notch strip over the
    /// cutout when both slots are the same width. With a single accessory —
    /// a download with nothing playing, say — the pill grows by half its width
    /// on *each* side, so half the glyph ends up behind the camera housing and
    /// is simply not there. Shifting by half the difference puts the strip back
    /// where it belongs and lets the pill grow only on the side that needs it.
    func centreShift(for state: IslandState, accessories: CompactAccessories) -> CGFloat {
        guard state == .compact else { return 0 }
        return ((accessories.trailing?.width ?? 0) - (accessories.leading?.width ?? 0)) / 2
    }

    /// What the view offsets the island by. Shares `centreShift` with the hit
    /// rect above, so what is drawn and what is pressable cannot drift apart.
    func horizontalOffset(for state: IslandState, accessories: CompactAccessories) -> CGFloat {
        horizontalOffsetFromPanelCentre + centreShift(for: state, accessories: accessories)
    }

    /// Same rect in global coordinates — what the pointer is tested against.
    func globalIslandRect(for state: IslandState, accessories: CompactAccessories) -> CGRect {
        let panel = panelFrame
        return islandRect(for: state, accessories: accessories)
            .offsetBy(dx: panel.minX, dy: panel.minY)
    }

    /// Hit geometry for the transport controls on the hover-expanded media row.
    func expandedControlHits(accessories: CompactAccessories) -> [IslandControlHit] {
        let island = islandRect(for: .expanded, accessories: accessories)
        let panel = panelFrame
        let payloadTop = island.maxY - notchHeight
        let inner = max(0, island.height - notchHeight)

        /// Payload-local (top-left origin) → global Cocoa (bottom-left origin).
        func global(_ frame: CGRect) -> CGRect {
            CGRect(x: panel.minX + island.minX + frame.minX,
                   y: panel.minY + payloadTop - frame.maxY,
                   width: frame.width, height: frame.height)
        }

        var hits = ExpandedMediaMetrics.transportFrames(islandWidth: island.width,
                                                        innerHeight: inner).map { item in
            let rect = global(item.frame)
            return IslandControlHit(control: .transport(item.command),
                                    hitRect: rect, valueRect: rect)
        }

        // The cover opens the player it came from.
        let cover = ExpandedMediaMetrics.artworkFrame(innerHeight: inner)
        let coverRect = global(cover)
        hits.append(IslandControlHit(control: .artwork,
                                     hitRect: coverRect, valueRect: coverRect))

        return hits
    }

    /// Hit geometry for every control the control center shows, in global
    /// coordinates.
    ///
    /// Derived from the same `ControlCenterMetrics` calls the views position
    /// themselves with, then mapped from payload-local (top-left origin) into
    /// Cocoa's bottom-left screen space.
    func controlHits(tiles: [SystemTile],
                     hasMedia: Bool,
                     countdown: CountdownState?,
                     shelfCount: Int,
                     hoveredShelfIndex: Int?) -> [IslandControlHit] {
        let island = islandRect(for: .controlCenter, accessories: .none)
        let panel = panelFrame
        let payloadTop = island.maxY - notchHeight

        /// payload-local (y down) -> global (y up)
        func global(_ frame: CGRect) -> CGRect {
            CGRect(x: panel.minX + island.minX + frame.minX,
                   y: panel.minY + payloadTop - frame.maxY,
                   width: frame.width,
                   height: frame.height)
        }

        var hits: [IslandControlHit] = []

        if hasMedia, let cover = ControlCenterMetrics.artworkFrame(sections) {
            let rect = global(cover)
            hits.append(IslandControlHit(control: .artwork, hitRect: rect, valueRect: rect))
        }

        // The scrubber goes in *before* the title. A 3 pt bar needs a press area
        // grown vertically to be catchable at all, and that grown area reaches
        // back up into the title block — first match wins, so whichever is added
        // first owns the overlap, and it has to be the one you cannot otherwise
        // hit.
        if hasMedia, let bar = ControlCenterMetrics.mediaSeekFrame(islandWidth: island.width,
                                                                   sections: sections) {
            let rect = global(bar)
            hits.append(IslandControlHit(control: .seek,
                                         hitRect: rect.insetBy(dx: 0, dy: -8),
                                         valueRect: rect))
        }

        if hasMedia {
            for item in ControlCenterMetrics.transportFrames(islandWidth: island.width, sections: sections) {
                let rect = global(item.frame)
                hits.append(IslandControlHit(control: .transport(item.command),
                                             hitRect: rect,
                                             valueRect: rect))
            }
        }

        if sections.timer {
            if countdown == nil {
                for item in ControlCenterMetrics.timerPresetFrames(sections) {
                    let rect = global(item.frame)
                    hits.append(IslandControlHit(control: .timer(.start(minutes: item.minutes)),
                                                 hitRect: rect, valueRect: rect))
                }
            } else {
                for item in ControlCenterMetrics.timerControlFrames(islandWidth: island.width, sections: sections) {
                    let rect = global(item.frame)
                    hits.append(IslandControlHit(control: .timer(item.action),
                                                 hitRect: rect, valueRect: rect))
                }
            }
        }

        if sections.shelf {
            let chips = ControlCenterMetrics.shelfChipFrames(count: shelfCount, sections: sections)
            for (index, chip) in chips.enumerated() {
                // The remove button sits on top of the chip, so it is registered
                // first and wins the hit test.
                if hoveredShelfIndex == index {
                    let remove = ControlCenterMetrics.shelfRemoveFrame(chip: chip)
                    let rect = global(remove)
                    hits.append(IslandControlHit(control: .shelf(.remove(index: index)),
                                                 hitRect: rect, valueRect: rect))
                }
                let rect = global(chip)
                hits.append(IslandControlHit(control: .shelf(.open(index: index)),
                                             hitRect: rect, valueRect: rect))
            }

            for item in ControlCenterMetrics.shelfActionFrames(islandWidth: island.width,
                                                               sections: sections) {
                let rect = global(item.frame)
                hits.append(IslandControlHit(control: .shelf(item.action),
                                             hitRect: rect, valueRect: rect))
            }
        }

        let frames = ControlCenterMetrics.tileFrames(islandWidth: island.width,
                                                     count: tiles.count,
                                                     sections: sections)
        for (tile, frame) in zip(tiles, frames) {
            let rect = global(frame)
            hits.append(IslandControlHit(
                control: .tile(tile),
                // The whole tile is the target: a 6pt meter is far too fine to
                // aim at, and Control Center's own sliders behave the same way.
                hitRect: rect,
                valueRect: rect.insetBy(dx: ControlCenterMetrics.tileInset, dy: 0)
            ))
        }

        return hits
    }

    /// How far the island sits from the panel's own centre, so the SwiftUI
    /// layout lands on the same axis the hit rects are measured from.
    var horizontalOffsetFromPanelCentre: CGFloat {
        let panel = panelFrame
        return metrics.notchCenterX - panel.midX
    }

    private var maxSize: CGSize {
        let compact = CGSize(width: max(metrics.notchWidth, 120) + Self.maxAccessoryWidth,
                             height: max(metrics.notchHeight, 28))
        // The panel never resizes as the payload changes, so it is measured
        // against the largest the expanded state could ever be — in *both*
        // axes. Height has to be a constant for the same reason width is: the
        // media row grew a scrubber, so `expandedSize.height` now varies with
        // what is playing, and measuring against it would resize the window
        // every time a track with a known duration started.
        let widths = [compact.width, ExpandedPayloadKind.maxWidth,
                      controlCenterSize.width, dropZoneSize.width]
        let heights = [compact.height, notchHeight + ExpandedPayloadKind.maxInnerHeight,
                       controlCenterSize.height, dropZoneSize.height]
        return CGSize(width: widths.max() ?? 0, height: heights.max() ?? 0)
    }
}

/// Publishes the current layout to SwiftUI. Kept separate from the controller so
/// the view doesn't hold a reference back to AppKit machinery.
final class IslandLayoutStore: ObservableObject {
    @Published var layout: IslandLayout

    init(layout: IslandLayout) {
        self.layout = layout
    }
}
