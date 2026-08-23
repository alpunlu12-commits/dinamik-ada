//
//  IslandView.swift
//  DynamicIsland
//
//  The island itself: one shape that changes size and contents.
//
//  Everything is laid out below the notch height, because on a real notched Mac
//  those top points are physically covered by the camera housing — except the
//  compact accessories, which deliberately sit *beside* the notch in that strip.
//
//  The island is always dark, like the hardware it grows out of, so every colour
//  is explicit rather than semantic: it must look identical in Light and Dark
//  mode.
//
//  This view draws only. No layer here accepts a press: AppKit routes every
//  click by geometry, and the pointer sampling supplies hover — see
//  PassthroughHostingView and IslandController.
//

import SwiftUI

struct IslandView: View {

    @ObservedObject var settings: AppState
    @ObservedObject var model: IslandModel
    @ObservedObject var layoutStore: IslandLayoutStore

    private var layout: IslandLayout { layoutStore.layout }
    private var state: IslandState { model.renderedState }

    private var accessories: CompactAccessories { model.compactAccessories }

    private var islandSize: CGSize {
        layout.size(for: state, accessories: accessories)
    }

    private var shape: NotchShape {
        NotchShape(topRadius: layout.topRadius(for: state, accessories: accessories),
                   bottomRadius: layout.bottomRadius(for: state))
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                // The notch is not perfectly centred on the panel, so nudge the
                // island onto its true axis rather than the view's midpoint —
                // and, when only one accessory is showing, off that axis again
                // so the notch strip inside the pill still covers the cutout.
                .offset(x: layout.horizontalOffset(for: state, accessories: accessories))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(settings.springAnimation, value: state)
        .animation(settings.springAnimation, value: accessories)
    }

    // MARK: Island

    private var island: some View {
        payload
            .frame(width: islandSize.width, height: islandSize.height)
            .background(shape.fill(Color.black))
            .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .clipShape(shape)
            // The compact pill sits *inside* the notch cutout, where a shadow
            // would only smear a dark halo onto the screen around the camera.
            // Shadow belongs to the states that actually float over content.
            .shadow(color: .black.opacity(state == .compact ? 0 : 0.35),
                    radius: state == .compact ? 0 : 12,
                    y: state == .compact ? 0 : 6)
    }

    private var payload: some View {
        ZStack(alignment: .top) {
            compactAccessories
                .frame(height: layout.notchHeight)
                .opacity(state == .compact ? 1 : 0)
                .allowsHitTesting(false)

            belowNotch
                .padding(.top, layout.notchHeight)
        }
    }

    // MARK: Compact

    /// The strips flanking the notch. They cost nothing until something needs
    /// them, and the notch's own width sits between them untouched.
    @ViewBuilder
    private var compactAccessories: some View {
        if !accessories.isEmpty {
            HStack(spacing: 0) {
                accessoryView(accessories.leading)
                    .frame(width: accessories.leading?.width ?? 0)

                Spacer(minLength: 0)
                    .frame(width: layout.compactSize(accessories: .none).width)

                accessoryView(accessories.trailing)
                    .frame(width: accessories.trailing?.width ?? 0)
            }
        }
    }

    @ViewBuilder
    private func accessoryView(_ accessory: CompactAccessory?) -> some View {
        switch accessory {
        case let .artwork(image):
            ArtworkView(image: image, side: 20, cornerRadius: 5)

        case let .waveform(playing, palette):
            WaveformView(isPlaying: playing, palette: palette).id(playing)

        case let .countdown(text):
            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)

        case .timerGlyph:
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

        case let .privacy(camera, microphone):
            PrivacyDots(camera: camera, microphone: microphone)

        case let .shelf(count):
            ShelfAccessory(count: count)

        case .download:
            DownloadAccessory()
                .frame(width: CompactAccessory.download.width)

        case nil:
            EmptyView()
        }
    }

    // MARK: Expanded / control center

    /// Height available to a payload: the island minus the strip the notch
    /// itself occupies.
    private var innerHeight: CGFloat {
        max(0, islandSize.height - layout.notchHeight)
    }

    /// The payload area.
    ///
    /// Every layer is pinned to `innerHeight` individually, not just the ZStack
    /// around them. Constraining only the ZStack is not enough: it still sizes
    /// itself to its tallest child, so the hidden control center (much taller
    /// than a HUD) would stretch it, and the visible payload — centred in that
    /// stretched box — would slide below the island's edge and get clipped away.
    private var belowNotch: some View {
        ZStack(alignment: .top) {
            expandedContent
                .frame(width: islandSize.width, height: innerHeight, alignment: .top)
                .opacity(state == .expanded ? 1 : 0)
                .allowsHitTesting(false)

            ControlCenterView(model: model,
                              islandWidth: islandSize.width,
                              sections: layout.sections)
                .frame(width: islandSize.width, height: innerHeight, alignment: .top)
                .opacity(state == .controlCenter ? 1 : 0)
                .allowsHitTesting(false)

            DropZonePayload(highlighted: model.isDropHighlighted,
                            fileCount: model.droppedFileCount)
                .frame(width: islandSize.width, height: innerHeight, alignment: .top)
                .opacity(state == .dropZone ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: islandSize.width, height: innerHeight, alignment: .top)
    }

    @ViewBuilder
    private var expandedContent: some View {
        Group {
            if let transient = model.transient {
                HUDPayload(kind: transient)
                    .transition(.opacity)
            } else if let countdown = model.countdown {
                CountdownPayload(countdown: countdown)
                    .transition(.opacity)
            } else if let track = model.nowPlaying {
                NowPlayingPayload(model: model, track: track,
                                  islandWidth: islandSize.width, innerHeight: innerHeight)
                    .transition(.opacity)
            } else {
                QuickStatsPayload(model: model)
                    .transition(.opacity)
            }
        }
        .animation(settings.springAnimation, value: model.transient)
        .animation(settings.springAnimation, value: model.nowPlaying)
        .animation(settings.springAnimation, value: model.countdown == nil)
    }
}
