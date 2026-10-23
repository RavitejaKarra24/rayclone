import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var launcherHotKey: GlobalHotKey?
    private var clipboardHotKey: GlobalHotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        LauncherController.shared.setup()
        setupStatusItem()
        registerHotKeys()

        if AppSettings.shared.clipboardEnabled {
            ClipboardStore.shared.start()
        }
        SnippetExpander.shared.start()

        NotificationCenter.default.addObserver(
            forName: .hotkeysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.registerHotKeys()
            }
        }

        // Keep derived state (feature toggles, theme) in sync with the launcher.
        AppSettings.shared.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyFeatureState() }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.stop()
        SnippetExpander.shared.stop()
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        if let launcherHotKey { GlobalHotKeyCenter.shared.unregister(launcherHotKey) }
        if let clipboardHotKey { GlobalHotKeyCenter.shared.unregister(clipboardHotKey) }
        launcherHotKey = nil
        clipboardHotKey = nil

        let settings = AppSettings.shared
        launcherHotKey = GlobalHotKeyCenter.shared.register(
            HotKeyCombo(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
        ) {
            LauncherController.shared.toggle()
        }
        clipboardHotKey = GlobalHotKeyCenter.shared.register(
            HotKeyCombo(keyCode: settings.clipboardHotkeyKeyCode, modifiers: settings.clipboardHotkeyModifiers)
        ) {
            LauncherController.shared.show(mode: .clipboard)
        }
    }

    private func applyFeatureState() {
        if AppSettings.shared.clipboardEnabled {
            ClipboardStore.shared.start()
        } else {
            ClipboardStore.shared.stop()
        }
        if AppSettings.shared.snippetsEnabled {
            SnippetExpander.shared.start()
        } else {
            SnippetExpander.shared.stop()
        }
        LauncherController.shared.refresh()
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "command.square.fill",
                accessibilityDescription: "Rayclone"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Launcher", action: #selector(openLauncher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clipboard History", action: #selector(openClipboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Search Snippets", action: #selector(openSnippets), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Emoji & Symbols", action: #selector(openEmoji), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Window Management", action: #selector(openWindows), keyEquivalent: "").target = self
        menu.addItem(withTitle: "System Actions", action: #selector(openSystem), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Rayclone", action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func openLauncher() { LauncherController.shared.show(mode: .root) }
    @objc private func openClipboard() { LauncherController.shared.show(mode: .clipboard) }
    @objc private func openSnippets() { LauncherController.shared.show(mode: .snippets) }
    @objc private func openEmoji() { LauncherController.shared.show(mode: .emoji) }
    @objc private func openWindows() { LauncherController.shared.show(mode: .windowManagement) }
    @objc private func openSystem() { LauncherController.shared.show(mode: .system) }
    @objc private func openSettings() { SettingsWindowController.present() }
    @objc private func quit() { NSApp.terminate(nil) }
}
