//
//  MarqueeText.swift
//  DynamicIsland
//
//  A single line of text that scrolls itself when it doesn't fit, and behaves
//  exactly like `Text` when it does.
//
//  The island is 400 pt wide at its widest and a media row spends most of that
//  on artwork and transport buttons, so a real track title — "Everything In Its
//  Right Place (Remastered)" — used to arrive as "Everything In Its Rig…". A
//  truncated title is the one piece of information the row exists to show.
//
//  Design notes:
//    • Scrolling only starts when the text actually overflows. Short titles get
//      no animation at all, which matters because most titles are short and a
//      pill that twitches for no reason reads as broken.
//    • The text is drawn twice with a gap between copies and the pair slides by
//      exactly one copy's width, so the loop has no visible seam and no snap
//      back to the start.
//    • Both ends fade into the island rather than being hard-clipped — a mask,
//      not an overlay, because the island's background is the panel behind it
//      and a solid gradient would paint a grey smear over black.
//
//  Widths are reported through preferences rather than written to @State from
//  inside a GeometryReader's body: mutating state during a layout pass is what
//  produces SwiftUI's "modifying state during view update" complaints. The
//  restart is driven by `.task(id:)` for the same reason the rest of the app
//  avoids the macOS 14 `onChange` overloads — the deployment target is 13.
//

import SwiftUI

struct MarqueeText: View {

    let text: String
    var font: Font
    var color: Color

    /// Points per second. Slow enough to read, fast enough to get through a long
    /// title before the island collapses.
    var speed: Double = 26

    /// Blank space between the two copies, so the loop reads as a pause rather
    /// than one long run-on string.
    var gap: CGFloat = 44

    /// How long the start of the text sits still before the scroll begins, so a
    /// title can be read from the beginning.
    var initialDelay: Double = 1.4

    /// Width of the fade at each edge.
    var fade: CGFloat = 10

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { textWidth > containerWidth + 0.5 }

    /// Everything that should restart the scroll. A track change and a resize
    /// both land here, so neither can inherit the previous run's position.
    private struct RestartToken: Equatable {
        let text: String
        let textWidth: CGFloat
        let containerWidth: CGFloat
    }

    var body: some View {
        // The layout is driven by a plain, invisible, *truncating* copy of the
        // text, and the moving copies ride along in an overlay.
        //
        // That indirection is the whole trick. The scrolling copies must be
        // `fixedSize` to keep their true width — but `fixedSize` also makes
        // this view's *minimum* width the full width of the text, and a stack
        // hands a rigid child its minimum no matter how little it proposed. The
        // symptom is nasty and quiet: dropped into a VStack, the marquee
        // measured its container as the text's own width, concluded the text
        // fit, never scrolled, and shoved everything beside it off the row.
        //
        // A truncating `Text` has no such minimum, so this view is flexible
        // again and honours whatever width it is given, wherever it is used.
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(spacing: gap) {
                    label
                        .background(widthReader(TextWidth.self))

                    // The second copy is what makes the wrap seamless. Nobody
                    // reads it, so keep it off the accessibility tree.
                    if overflows {
                        label.accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: overflows ? offset : 0)
                // The visible copies duplicate the text the hidden one already
                // announces.
                .accessibilityHidden(true)
            }
            .background(widthReader(ContainerWidth.self))
            .mask(overflows ? AnyView(edgeFade) : AnyView(Color.black))
            .clipped()
            .onPreferenceChange(TextWidth.self) { textWidth = $0 }
            .onPreferenceChange(ContainerWidth.self) { containerWidth = $0 }
            .task(id: RestartToken(text: text,
                                   textWidth: textWidth,
                                   containerWidth: containerWidth)) {
                await restart()
            }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func widthReader<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.width)
        }
    }

    /// Transparent at both edges, opaque in between. Applied as a mask so the
    /// fade reveals the island's black rather than painting over it.
    private var edgeFade: some View {
        let inset = fade / max(containerWidth, 1)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: min(inset, 0.5)),
                .init(color: .black, location: max(1 - inset, 0.5)),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    @MainActor
    private func restart() async {
        offset = 0
        guard overflows, containerWidth > 0 else { return }

        // Hold the start still long enough to read it. Sleeping rather than
        // using `.delay` keeps the pause on the first pass only — a delay baked
        // into a repeating animation stutters at every wrap.
        try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
        guard !Task.isCancelled else { return }

        let distance = textWidth + gap
        withAnimation(.linear(duration: distance / speed).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

// MARK: - Width preferences

private struct TextWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContainerWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
