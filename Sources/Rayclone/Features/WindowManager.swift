import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// A window geometry or window action offered by the launcher.
enum WindowTarget: Equatable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case topLeftSixth, topSixth, topRightSixth
    case bottomLeftSixth, bottomSixth, bottomRightSixth
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, center, almostMaximize
    case nextDisplay, previousDisplay
    case nextDesktop, previousDesktop
    case restore          // restore the window to the size/position saved before the last mutation
    case toggleFullScreen
    case minimize
    case close
}

/// Window management for the frontmost app's focused window through the
/// Accessibility API, with graceful degradation: every failure path returns
/// `false` and nothing is printed.
///
/// Geometry is computed in *Quartz* (top-left origin, y down) coordinates
/// because that is what the AX position/size attributes speak. AppKit screens
/// use a bottom-left origin, so screen rectangles are flipped once at the edge
/// (`quartzRect`). Menu bar and Dock are respected by using `visibleFrame`.
enum WindowManager {
    private enum Metrics {
        /// Inner breathing room kept when centering a window.
        static let centerMargin: CGFloat = 8
        /// Inset from the visible frame for `.almostMaximize`.
        static let almostMaximizeInset: CGFloat = 32
        /// Upper bound on remembered frames so the store cannot grow forever.
        static let savedFrameLimit = 64
    }

    // MARK: - Accessibility trust

    /// True when the process is trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system accessibility approval dialog (no-op when already trusted).
    static func requestAccess() {
        guard !isTrusted else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Public mutation entry point

    /// Mutates the focused window of the frontmost app.
    @discardableResult
    static func apply(_ target: WindowTarget) -> Bool {
        // AX writes and CGEvents both require the same permission; without it
        // the system silently drops the work, so report failure instead.
        guard isTrusted else { return false }

        switch target {
        case .nextDesktop:
            return postKey(CGKeyCode(kVK_RightArrow), flags: .maskControl)
        case .previousDesktop:
            return postKey(CGKeyCode(kVK_LeftArrow), flags: .maskControl)
        case .toggleFullScreen:
            return postKey(CGKeyCode(kVK_ANSI_F), flags: [.maskControl, .maskCommand])
        default:
            break
        }

        guard let focused = focusedWindow() else { return false }
        let window = focused.window

        if target == .minimize { return minimize(window) }
        if target == .close { return pressCloseButton(of: window) }

        guard let currentFrame = frame(of: window) else { return false }

        if target == .restore {
            guard let saved = rememberedFrame(for: window, pid: focused.pid) else { return false }
            return setFrame(saved, on: window)
        }

        if target == .nextDisplay {
            return moveToAdjacentDisplay(window, from: currentFrame, step: 1)
        }
        if target == .previousDisplay {
            return moveToAdjacentDisplay(window, from: currentFrame, step: -1)
        }

        guard let screen = screen(containing: currentFrame) else { return false }
        let visible = quartzRect(screen.visibleFrame)
        guard let rect = targetRect(for: target, in: visible, current: currentFrame) else { return false }

        // Remember what to return to before this mutation lands.
        remember(currentFrame, for: window, pid: focused.pid)
        return setFrame(rect, on: window)
    }

    // MARK: - Titles, symbols, ordering

    /// Human-readable title used in the launcher list, e.g. "Left Half".
    static func title(for target: WindowTarget) -> String {
        switch target {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeftQuarter: return "Top Left Quarter"
        case .topRightQuarter: return "Top Right Quarter"
        case .bottomLeftQuarter: return "Bottom Left Quarter"
        case .bottomRightQuarter: return "Bottom Right Quarter"
        case .topLeftSixth: return "Top Left Sixth"
        case .topSixth: return "Top Center Sixth"
        case .topRightSixth: return "Top Right Sixth"
        case .bottomLeftSixth: return "Bottom Left Sixth"
        case .bottomSixth: return "Bottom Center Sixth"
        case .bottomRightSixth: return "Bottom Right Sixth"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .almostMaximize: return "Almost Maximize"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        case .nextDesktop: return "Next Desktop"
        case .previousDesktop: return "Previous Desktop"
        case .restore: return "Restore Previous Size"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .minimize: return "Minimize"
        case .close: return "Close"
        }
    }

    /// SF Symbol name used in the launcher list.
    static func symbolName(for target: WindowTarget) -> String {
        switch target {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeftQuarter: return "rectangle.inset.topleft.fill"
        case .topRightQuarter: return "rectangle.inset.topright.fill"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleft.fill"
        case .bottomRightQuarter: return "rectangle.inset.bottomright.fill"
        case .topLeftSixth: return "rectangle.inset.topleft.filled"
        case .topSixth: return "rectangle.topthird.inset.fill"
        case .topRightSixth: return "rectangle.inset.topright.filled"
        case .bottomLeftSixth: return "rectangle.inset.bottomleft.filled"
        case .bottomSixth: return "rectangle.bottomthird.inset.fill"
        case .bottomRightSixth: return "rectangle.inset.bottomright.filled"
        case .leftThird: return "rectangle.leftthird.inset.fill"
        case .centerThird: return "rectangle.center.inset.fill"
        case .rightThird: return "rectangle.rightthird.inset.fill"
        case .leftTwoThirds: return "rectangle.split.2x1"
        case .rightTwoThirds: return "rectangle.split.2x1"
        case .maximize: return "rectangle.fill"
        case .center: return "arrow.down.right.and.arrow.up.left"
        case .almostMaximize: return "rectangle.inset.fill"
        case .nextDisplay: return "arrow.right.to.line"
        case .previousDisplay: return "arrow.left.to.line"
        case .nextDesktop: return "arrow.right.square"
        case .previousDesktop: return "arrow.left.square"
        case .restore: return "arrow.uturn.backward"
        case .toggleFullScreen: return "arrow.up.left.and.arrow.down.right"
        case .minimize: return "minus.circle"
        case .close: return "xmark.circle"
        }
    }

    /// All targets in menu order.
    static var allTargets: [WindowTarget] {
        [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf,
            .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
            .topLeftSixth, .topSixth, .topRightSixth,
            .bottomLeftSixth, .bottomSixth, .bottomRightSixth,
            .leftThird, .centerThird, .rightThird,
            .leftTwoThirds, .rightTwoThirds,
            .maximize, .almostMaximize, .center,
            .nextDisplay, .previousDisplay,
            .nextDesktop, .previousDesktop,
            .restore, .toggleFullScreen, .minimize, .close,
        ]
    }
}

// MARK: - AX plumbing

private extension WindowManager {
    /// The frontmost app's focused window plus its pid (pid disambiguates the
    /// restore memory when a window has no readable `CGWindowID`).
    struct FocusedWindow {
        let window: AXUIElement
        let pid: pid_t
    }

    /// `_AXUIElementGetWindow` is the undocumented but long-stable way to map an
    /// AX window element to the `CGWindowID` used by the WindowServer.
    @_silgen_name("_AXUIElementGetWindow")
    static func AXWindowNumber(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// AppKit global (bottom-left origin, y up) -> Quartz global (top-left origin, y down).
    static func quartzRect(_ rect: NSRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func focusedWindow() -> FocusedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        guard let element = axElement(copyAttribute(kAXFocusedWindowAttribute, from: axApp)) else { return nil }
        return FocusedWindow(window: element, pid: pid)
    }

    static func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// `CFTypeID` is checked first so the cast below is always valid.
    static func axValue(_ ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXValue.self)
    }

    static func axElement(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    /// Current window frame in Quartz coordinates.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(copyAttribute(kAXPositionAttribute, from: window)),
              let sizeValue = axValue(copyAttribute(kAXSizeAttribute, from: window)) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func setPosition(_ point: CGPoint, on window: AXUIElement) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    static func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    /// Size first, then position: resizing moves some windows' origin, so the
    /// position write has to come last to land exactly where we asked.
    static func setFrame(_ rect: CGRect, on window: AXUIElement) -> Bool {
        let sized = setSize(rect.size, on: window)
        let positioned = setPosition(rect.origin, on: window)
        return sized && positioned
    }

    static func minimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    static func pressCloseButton(of window: AXUIElement) -> Bool {
        guard let button = axElement(copyAttribute(kAXCloseButtonAttribute, from: window)) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
}

// MARK: - Geometry

private extension WindowManager {
    /// Screen whose frame contains the window's center, falling back to
    /// `NSScreen.main` and then the first screen.
    static func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let match = NSScreen.screens.first(where: { quartzRect($0.frame).contains(center) }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Sub-rectangle of `visible` given fractions measured from its top-left
    /// (Quartz orientation: 0,0 is the top-left corner, y grows downward).
    static func fraction(_ visible: CGRect, x: (CGFloat, CGFloat), y: (CGFloat, CGFloat)) -> CGRect {
        CGRect(
            x: visible.minX + visible.width * x.0,
            y: visible.minY + visible.height * y.0,
            width: visible.width * (x.1 - x.0),
            height: visible.height * (y.1 - y.0)
        )
    }

    static func targetRect(for target: WindowTarget, in visible: CGRect, current: CGRect) -> CGRect? {
        let full = (CGFloat(0), CGFloat(1))
        let half = CGFloat(0.5)
        let third = CGFloat(1) / 3
        let twoThirds = CGFloat(2) / 3

        switch target {
        case .leftHalf: return fraction(visible, x: (0, half), y: full)
        case .rightHalf: return fraction(visible, x: (half, 1), y: full)
        case .topHalf: return fraction(visible, x: full, y: (0, half))
        case .bottomHalf: return fraction(visible, x: full, y: (half, 1))
        case .topLeftQuarter: return fraction(visible, x: (0, half), y: (0, half))
        case .topRightQuarter: return fraction(visible, x: (half, 1), y: (0, half))
        case .bottomLeftQuarter: return fraction(visible, x: (0, half), y: (half, 1))
        case .bottomRightQuarter: return fraction(visible, x: (half, 1), y: (half, 1))
        case .topLeftSixth: return fraction(visible, x: (0, third), y: (0, third))
        case .topSixth: return fraction(visible, x: (third, twoThirds), y: (0, third))
        case .topRightSixth: return fraction(visible, x: (twoThirds, 1), y: (0, third))
        case .bottomLeftSixth: return fraction(visible, x: (0, third), y: (twoThirds, 1))
        case .bottomSixth: return fraction(visible, x: (third, twoThirds), y: (twoThirds, 1))
        case .bottomRightSixth: return fraction(visible, x: (twoThirds, 1), y: (twoThirds, 1))
        case .leftThird: return fraction(visible, x: (0, third), y: full)
        case .centerThird: return fraction(visible, x: (third, twoThirds), y: full)
        case .rightThird: return fraction(visible, x: (twoThirds, 1), y: full)
        case .leftTwoThirds: return fraction(visible, x: (0, twoThirds), y: full)
        case .rightTwoThirds: return fraction(visible, x: (third, 1), y: full)
        case .maximize: return visible
        case .almostMaximize: return visible.insetBy(dx: Metrics.almostMaximizeInset, dy: Metrics.almostMaximizeInset)
        case .center: return centered(current.size, in: visible)
        case .nextDisplay, .previousDisplay, .nextDesktop, .previousDesktop,
             .restore, .toggleFullScreen, .minimize, .close:
            return nil
        }
    }

    /// Keeps the current size (clamped to the margins) and centers the window.
    static func centered(_ size: CGSize, in visible: CGRect) -> CGRect {
        let bounds = visible.insetBy(dx: Metrics.centerMargin, dy: Metrics.centerMargin)
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func moveToAdjacentDisplay(_ window: AXUIElement, from currentFrame: CGRect, step: Int) -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }

        let currentIndex = screen(containing: currentFrame).flatMap { current in
            screens.firstIndex(where: { $0 === current })
        } ?? 0
        let targetIndex = (currentIndex + step + screens.count) % screens.count
        let visible = quartzRect(screens[targetIndex].visibleFrame)

        let width = min(currentFrame.width, visible.width)
        let height = min(currentFrame.height, visible.height)
        let rect = CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        // Only positions move here; the size is preserved (clamped if needed).
        return setFrame(rect, on: window)
    }

    /// Synthetic key events: there is no AX surface for Spaces or full screen.
    static func postKey(_ code: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            return false
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

// MARK: - Restore memory

private extension WindowManager {
    static func memoryKey(for window: AXUIElement, pid: pid_t) -> String {
        var identifier: CGWindowID = 0
        if AXWindowNumber(window, &identifier) == .success, identifier != 0 {
            return "window-\(identifier)"
        }
        if let title = copyAttribute(kAXTitleAttribute, from: window) as? String, !title.isEmpty {
            return "pid-\(pid)-title-\(title)"
        }
        return "pid-\(pid)"
    }

    static func remember(_ rect: CGRect, for window: AXUIElement, pid: pid_t) {
        let key = memoryKey(for: window, pid: pid)
        if savedFrames.count >= Metrics.savedFrameLimit, savedFrames[key] == nil {
            savedFrames.removeAll()
        }
        savedFrames[key] = rect
    }

    static func rememberedFrame(for window: AXUIElement, pid: pid_t) -> CGRect? {
        savedFrames[memoryKey(for: window, pid: pid)]
    }
}

/// One frame per window, keyed by `CGWindowID` when available and by pid+title
/// otherwise. A single slot per window is enough because only the most recent
/// mutation needs to be undone. Declared at file scope because members of a
/// `private extension` cannot hold their own mutable storage.
private var savedFrames: [String: CGRect] = [:]
