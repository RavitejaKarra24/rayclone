import AppKit
import SwiftUI

/// A borderless, non-activating panel that can still become key so the search
/// field receives typing without switching Spaces or stealing the Dock.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Metric.windowWidth, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}

@MainActor
final class LauncherController: ObservableObject {
    static let shared = LauncherController()

    @Published var query: String = "" {
        didSet { if query != oldValue { recompute() } }
    }
    @Published private(set) var mode: LauncherMode = .root
    @Published private(set) var results: [SearchItem] = []
    @Published var selection: Int = 0
    @Published var actionsVisible = false
    @Published var actionSelection: Int = 0
    /// Bumped on every presentation so the SwiftUI tree is rebuilt and the
    /// search field re-acquires focus reliably.
    @Published private(set) var presentationCount = 0

    private(set) var panel: LauncherPanel?
    private var hostingView: NSHostingView<LauncherRootView>?
    private var keyMonitor: Any?
    private var previousAppPID: pid_t?
    private var suppressAutoHide = false
    private var becameKeyAt: Date?

    var theme: Theme { AppSettings.shared.activeTheme }
    var selectedItem: SearchItem? {
        guard results.indices.contains(selection) else { return results.first }
        return results[selection]
    }

    // MARK: Lifecycle

    func setup() {
        let controller = self
        let root = LauncherRootView(controller: controller)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        let panel = LauncherPanel()
        panel.contentView = hosting
        self.panel = panel
        self.hostingView = hosting

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else { return event }
            return self.handleKeyDown(event)
        }

        // A non-activating panel can lose key status transiently (another app
        // grabs focus, a system alert appears). Re-assert key so typing never
        // silently leaks into whatever app is underneath, but never steal key
        // from one of our own windows (settings, snippet editor, script output).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard panel.isVisible, !panel.isKeyWindow else { return }
                    if let keyWindow = NSApp.keyWindow, keyWindow !== panel { return }
                    panel.makeKey()
                }
            }
        }
    }

    func toggle(mode newMode: LauncherMode? = nil) {
        if let panel, panel.isVisible, newMode == nil || newMode == mode {
            hide()
            return
        }
        show(mode: newMode)
    }

    func show(mode newMode: LauncherMode? = nil) {
        guard let panel else { return }
        previousAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        mode = newMode ?? .root
        query = ""
        actionsVisible = false
        recompute()
        selection = 0
        panel.setContentSize(NSSize(width: Metric.windowWidth, height: currentHeight()))
        positionPanel()
        // A `.nonactivatingPanel` becomes key without making Rayclone the active
        // app, so the previously frontmost app keeps focus for pasting.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        presentationCount += 1
        focusSearchField()
        NotificationCenter.default.post(name: .launcherDidShow, object: nil)
    }

    /// SwiftUI's `@FocusState` only fires on first appearance, so the panel also
    /// focuses the backing text view directly.
    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let contentView = self.panel?.contentView else { return }
            if let field = contentView.firstTextResponder() {
                self.panel?.makeFirstResponder(field)
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        query = ""
        actionsVisible = false
        previousAppPID = nil
    }

    func setMode(_ newMode: LauncherMode) {
        suppressAutoHide = true
        mode = newMode
        query = ""
        selection = 0
        actionsVisible = false
        recompute()
        objectWillChange.send()
        focusSearchField()
        NotificationCenter.default.post(name: .launcherDidShow, object: nil)
    }

    func resetToRoot() {
        mode = .root
        query = ""
        selection = 0
        recompute()
    }

    func refresh() { recompute() }

    // MARK: Ranking

    private func recompute() {
        results = CommandCenter.shared.search(query, mode: mode)
        if selection >= results.count { selection = max(results.count - 1, 0) }
        if actionSelection >= (selectedItem?.actions.count ?? 0) { actionSelection = 0 }
        resizeToFit()
    }

    private func resizeToFit() {
        guard let panel else { return }
        let height = currentHeight()
        if abs(panel.frame.height - height) > 0.5 {
            var frame = panel.frame
            frame.size.height = height
            // Keep the top edge anchored while the list grows.
            frame.origin.y = frame.maxY - height
            panel.setFrame(frame, display: true)
        }
    }

    private func currentHeight() -> CGFloat {
        // Fields mirrored from `LauncherRootView`: 6pt vertical padding inside the
        // list, 40pt rows, ~22pt section headers.
        let listPadding: CGFloat = 12
        let sectionHeight: CGFloat = 22
        let rowHeight = Metric.rowHeight
        let chrome = Metric.headerHeight + Metric.footerHeight
        let maxListHeight = CGFloat(8) * rowHeight + sectionHeight + listPadding

        // Walk the rows exactly as the view lays them out so the panel never
        // ends on a half-clipped row.
        var used = listPadding
        for index in results.indices {
            var rowExtent = rowHeight
            if index == 0 || results[index - 1].section != results[index].section {
                rowExtent += sectionHeight
            }
            if used + rowExtent > maxListHeight { break }
            used += rowExtent
        }
        let listHeight = max(used, rowHeight + listPadding)
        return chrome + listHeight
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let width = Metric.windowWidth
        let height = currentHeight()
        let x = visible.midX - width / 2
        let y = visible.maxY - height - visible.height * 0.18
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: Selection

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        if actionsVisible {
            let count = selectedItem?.actions.count ?? 0
            guard count > 0 else { return }
            actionSelection = (actionSelection + delta + count) % count
            return
        }
        selection = (selection + delta + results.count) % results.count
    }

    func toggleActions() {
        guard selectedItem?.actions.isEmpty == false else { return }
        actionsVisible.toggle()
        actionSelection = 0
    }

    func performSelected() {
        guard let item = selectedItem else { return }
        if actionsVisible, item.actions.indices.contains(actionSelection) {
            perform(item: item, action: item.actions[actionSelection])
            return
        }
        guard let action = item.primaryAction else { return }
        perform(item: item, action: action)
    }

    func perform(item: SearchItem, action: ItemAction) {
        FrecencyStore.shared.record(item.id)
        suppressAutoHide = false
        action.perform()
        if suppressAutoHide {
            // The action switched the launcher into another command view.
            recompute()
            objectWillChange.send()
        } else {
            // Let the action's side effects run before tearing the panel down.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.hide()
            }
        }
    }

    // MARK: Key handling

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), event.charactersIgnoringModifiers == "," {
            SettingsWindowController.present()
            hide()
            return nil
        }
        if flags.contains(.command), event.charactersIgnoringModifiers == "k" {
            toggleActions()
            return nil
        }
        if flags.contains(.command), event.charactersIgnoringModifiers == "w" {
            hide()
            return nil
        }

        switch event.keyCode {
        case 125: // ↓
            moveSelection(1)
            return nil
        case 126: // ↑
            moveSelection(-1)
            return nil
        case 36, 76: // ⏎
            performSelected()
            return nil
        case 53: // ⎋
            if actionsVisible {
                actionsVisible = false
            } else if mode != .root {
                resetToRoot()
            } else if !query.isEmpty {
                query = ""
            } else {
                hide()
            }
            return nil
        case 48: // ⇥
            toggleActions()
            return nil
        case 51 where flags.contains(.command): // ⌘⌫
            if let item = selectedItem, item.id.hasPrefix("clipboard:") {
                if let action = item.actions.first(where: { $0.id == "delete" }) {
                    perform(item: item, action: action)
                }
            }
            return nil
        default:
            break
        }

        // ⌘1 … ⌘9 triggers the Nth action when the action panel is open.
        if actionsVisible, flags.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), digit >= 1, digit <= 9,
           let item = selectedItem, item.actions.indices.contains(digit - 1) {
            perform(item: item, action: item.actions[digit - 1])
            return nil
        }

        return event
    }
}

extension Notification.Name {
    static let launcherDidShow = Notification.Name("launcherDidShow")
}

extension NSView {
    /// Finds the editable text view SwiftUI uses for `TextField`.
    func firstTextResponder() -> NSView? {
        if self is NSTextField || self is NSTextView { return self }
        for subview in subviews {
            if let found = subview.firstTextResponder() { return found }
        }
        return nil
    }
}
