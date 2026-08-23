//
//  NotchDetector.swift
//  DynamicIsland
//
//  Detects the physical MacBook notch using the public NSScreen APIs added in
//  macOS 12 (`safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`),
//  and falls back to a "simulated notch" sized pill on Macs without one so the
//  app is demoable anywhere.
//
//  All returned geometry is in the global Cocoa coordinate space (origin at the
//  bottom-left of the main screen), which is what NSWindow.setFrame expects.
//

import AppKit

/// Which display the island lives on.
///
/// Stored by the display's UUID rather than its `CGDirectDisplayID`: the ID is
/// reassigned when a monitor is unplugged and plugged back in, so a preference
/// saved against it would quietly point at the wrong screen.
enum DisplayPreference: Hashable {
    /// The built-in notched display when there is one, otherwise the main display.
    case automatic
    case builtIn
    case display(uuid: String)

    var storageValue: String {
        switch self {
        case .automatic:          return "automatic"
        case .builtIn:            return "builtIn"
        case let .display(uuid):  return "display:\(uuid)"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "builtIn": self = .builtIn
        case let value where value.hasPrefix("display:"):
            self = .display(uuid: String(value.dropFirst("display:".count)))
        default: self = .automatic
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable across unplugging, unlike the display ID.
    var displayUUID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }
    var hasNotch: Bool { safeAreaInsets.top > 0 }
}

/// Geometry describing where and how big the island's host notch is.
struct NotchMetrics: Equatable {
    /// True when a real hardware notch was detected on the chosen screen.
    var hasPhysicalNotch: Bool
    /// Width of the notch (points).
    var notchWidth: CGFloat
    /// Height of the notch / top safe-area inset (points).
    var notchHeight: CGFloat
    /// Full frame of the screen the island is anchored to (global coordinates).
    var screenFrame: CGRect
    /// Horizontal centre of the notch in global coordinates.
    ///
    /// Not simply the screen's midpoint: the cutout is not perfectly centred on
    /// every panel — this one sits half a point to the left — and aligning to the
    /// screen instead leaves a sliver of island showing beside the camera.
    var notchCenterX: CGFloat
}

enum NotchDetector {

    /// Simulated-notch dimensions, roughly matching a real 14"/16" notch so the
    /// demo looks representative.
    private enum Simulated {
        static let height: CGFloat = 32
        static func width(for size: IslandSize) -> CGFloat {
            switch size {
            case .small:  return 180
            case .medium: return 210
            }
        }
    }

    /// Compute notch metrics for the current display configuration.
    ///
    /// A physical notch always wins. There used to be a setting that forced the
    /// simulated pill even on a notched Mac; all it could do there was draw a
    /// pill of the wrong width, leaving black sticking out on either side of the
    /// camera. Simulation is a fallback for Macs without a notch, not a mode.
    ///
    /// - Parameters:
    ///   - size: Island-size setting, used to pick a simulated width.
    ///   - preference: Which display the island should live on.
    static func detect(size: IslandSize,
                       preference: DisplayPreference = .automatic) -> NotchMetrics {
        let screen = preferredScreen(preference)
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        var width: CGFloat = 0
        var height: CGFloat = 0
        var centerX = frame.midX
        var physical = false

        if let screen {
            // safeAreaInsets/auxiliary* are macOS 12+. Deployment target is 13,
            // so they are always available here.
            let topInset = screen.safeAreaInsets.top
            if topInset > 0 {
                height = topInset
                if let left = screen.auxiliaryTopLeftArea,
                   let right = screen.auxiliaryTopRightArea {
                    let w = frame.width - left.width - right.width
                    if w > 0 {
                        width = w
                        centerX = frame.minX + left.width + w / 2
                        physical = true
                    }
                }
            }
        }

        // No notch: draw a representative pill so the app is usable anywhere.
        if !physical {
            height = height > 0 ? height : Simulated.height
            width = Simulated.width(for: size)
        }

        return NotchMetrics(
            hasPhysicalNotch: physical,
            notchWidth: width,
            notchHeight: height,
            screenFrame: frame,
            notchCenterX: centerX
        )
    }

    /// The chosen display, falling back gracefully when it is not connected —
    /// an island on no screen at all would just look like the app had crashed.
    static func preferredScreen(_ preference: DisplayPreference) -> NSScreen? {
        let screens = NSScreen.screens

        switch preference {
        case let .display(uuid):
            if let match = screens.first(where: { $0.displayUUID == uuid }) { return match }

        case .builtIn:
            if let builtIn = screens.first(where: \.isBuiltIn) { return builtIn }

        case .automatic:
            break
        }

        if let notched = screens.first(where: \.hasNotch) { return notched }
        return NSScreen.main ?? screens.first
    }
}
