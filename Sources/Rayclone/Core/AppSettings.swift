import Foundation
import SwiftUI
import Combine
import AppKit
import Carbon.HIToolbox

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: Appearance

    @Published var themeID: String {
        didSet { defaults.set(themeID, forKey: Keys.themeID) }
    }

    @Published var followSystemAppearance: Bool {
        didSet { defaults.set(followSystemAppearance, forKey: Keys.followSystem) }
    }

    // MARK: Launcher behaviour

    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    @Published var hotkeyModifiers: Int {
        didSet { defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    @Published var clipboardHotkeyKeyCode: Int {
        didSet { defaults.set(clipboardHotkeyKeyCode, forKey: Keys.clipboardHotkeyKeyCode) }
    }

    @Published var clipboardHotkeyModifiers: Int {
        didSet { defaults.set(clipboardHotkeyModifiers, forKey: Keys.clipboardHotkeyModifiers) }
    }

    /// `true` pastes into the frontmost app, `false` only copies.
    @Published var pasteOnPrimaryAction: Bool {
        didSet { defaults.set(pasteOnPrimaryAction, forKey: Keys.pasteOnPrimary) }
    }

    @Published var maxResults: Int {
        didSet { defaults.set(maxResults, forKey: Keys.maxResults) }
    }

    @Published var showRecentSection: Bool {
        didSet { defaults.set(showRecentSection, forKey: Keys.showRecent) }
    }

    // MARK: Feature switches

    @Published var applicationsEnabled: Bool { didSet { defaults.set(applicationsEnabled, forKey: Keys.applications) } }
    @Published var filesEnabled: Bool { didSet { defaults.set(filesEnabled, forKey: Keys.files) } }
    @Published var calculatorEnabled: Bool { didSet { defaults.set(calculatorEnabled, forKey: Keys.calculator) } }
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboard) } }
    @Published var snippetsEnabled: Bool { didSet { defaults.set(snippetsEnabled, forKey: Keys.snippets) } }
    @Published var emojiEnabled: Bool { didSet { defaults.set(emojiEnabled, forKey: Keys.emoji) } }
    @Published var quicklinksEnabled: Bool { didSet { defaults.set(quicklinksEnabled, forKey: Keys.quicklinks) } }
    @Published var webSearchEnabled: Bool { didSet { defaults.set(webSearchEnabled, forKey: Keys.webSearch) } }
    @Published var windowManagementEnabled: Bool { didSet { defaults.set(windowManagementEnabled, forKey: Keys.windowManagement) } }
    @Published var systemActionsEnabled: Bool { didSet { defaults.set(systemActionsEnabled, forKey: Keys.systemActions) } }
    @Published var scriptCommandsEnabled: Bool { didSet { defaults.set(scriptCommandsEnabled, forKey: Keys.scriptCommands) } }
    @Published var historyEnabled: Bool { didSet { defaults.set(historyEnabled, forKey: Keys.history) } }

    // MARK: Clipboard

    @Published var clipboardHistoryLimit: Int {
        didSet { defaults.set(clipboardHistoryLimit, forKey: Keys.clipboardLimit) }
    }

    @Published var clipboardPollInterval: Double {
        didSet { defaults.set(clipboardPollInterval, forKey: Keys.clipboardInterval) }
    }

    @Published var clipboardIgnoreConfidential: Bool {
        didSet { defaults.set(clipboardIgnoreConfidential, forKey: Keys.clipboardConfidential) }
    }

    // MARK: File search

    @Published var fileSearchShowHidden: Bool {
        didSet { defaults.set(fileSearchShowHidden, forKey: Keys.filesHidden) }
    }

    @Published var fileSearchResultLimit: Int {
        didSet { defaults.set(fileSearchResultLimit, forKey: Keys.filesLimit) }
    }

    private enum Keys {
        static let themeID = "themeID"
        static let followSystem = "followSystemAppearance"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let clipboardHotkeyKeyCode = "clipboardHotkeyKeyCode"
        static let clipboardHotkeyModifiers = "clipboardHotkeyModifiers"
        static let pasteOnPrimary = "pasteOnPrimaryAction"
        static let maxResults = "maxResults"
        static let showRecent = "showRecentSection"
        static let applications = "applicationsEnabled"
        static let files = "filesEnabled"
        static let calculator = "calculatorEnabled"
        static let clipboard = "clipboardEnabled"
        static let snippets = "snippetsEnabled"
        static let emoji = "emojiEnabled"
        static let quicklinks = "quicklinksEnabled"
        static let webSearch = "webSearchEnabled"
        static let windowManagement = "windowManagementEnabled"
        static let systemActions = "systemActionsEnabled"
        static let scriptCommands = "scriptCommandsEnabled"
        static let history = "historyEnabled"
        static let clipboardLimit = "clipboardHistoryLimit"
        static let clipboardInterval = "clipboardPollInterval"
        static let clipboardConfidential = "clipboardIgnoreConfidential"
        static let filesHidden = "fileSearchShowHidden"
        static let filesLimit = "fileSearchResultLimit"
    }

    private init() {
        defaults.register(defaults: [
            Keys.themeID: Theme.raycastDark.id,
            Keys.followSystem: true,
            // ⌥Space — Raycast's default is ⌘Space, which Spotlight owns.
            Keys.hotkeyKeyCode: Int(kVK_Space),
            Keys.hotkeyModifiers: Int(optionKey),
            Keys.clipboardHotkeyKeyCode: Int(kVK_ANSI_V),
            Keys.clipboardHotkeyModifiers: Int(optionKey | shiftKey),
            Keys.pasteOnPrimary: true,
            Keys.maxResults: 60,
            Keys.showRecent: true,
            Keys.applications: true,
            Keys.files: true,
            Keys.calculator: true,
            Keys.clipboard: true,
            Keys.snippets: true,
            Keys.emoji: true,
            Keys.quicklinks: true,
            Keys.webSearch: true,
            Keys.windowManagement: true,
            Keys.systemActions: true,
            Keys.scriptCommands: true,
            Keys.history: true,
            Keys.clipboardLimit: 500,
            Keys.clipboardInterval: 0.6,
            Keys.clipboardConfidential: true,
            Keys.filesHidden: false,
            Keys.filesLimit: 12,
        ])

        themeID = defaults.string(forKey: Keys.themeID) ?? Theme.raycastDark.id
        followSystemAppearance = defaults.bool(forKey: Keys.followSystem)
        hotkeyKeyCode = defaults.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = defaults.integer(forKey: Keys.hotkeyModifiers)
        clipboardHotkeyKeyCode = defaults.integer(forKey: Keys.clipboardHotkeyKeyCode)
        clipboardHotkeyModifiers = defaults.integer(forKey: Keys.clipboardHotkeyModifiers)
        pasteOnPrimaryAction = defaults.bool(forKey: Keys.pasteOnPrimary)
        maxResults = defaults.integer(forKey: Keys.maxResults)
        showRecentSection = defaults.bool(forKey: Keys.showRecent)
        applicationsEnabled = defaults.bool(forKey: Keys.applications)
        filesEnabled = defaults.bool(forKey: Keys.files)
        calculatorEnabled = defaults.bool(forKey: Keys.calculator)
        clipboardEnabled = defaults.bool(forKey: Keys.clipboard)
        snippetsEnabled = defaults.bool(forKey: Keys.snippets)
        emojiEnabled = defaults.bool(forKey: Keys.emoji)
        quicklinksEnabled = defaults.bool(forKey: Keys.quicklinks)
        webSearchEnabled = defaults.bool(forKey: Keys.webSearch)
        windowManagementEnabled = defaults.bool(forKey: Keys.windowManagement)
        systemActionsEnabled = defaults.bool(forKey: Keys.systemActions)
        scriptCommandsEnabled = defaults.bool(forKey: Keys.scriptCommands)
        historyEnabled = defaults.bool(forKey: Keys.history)
        clipboardHistoryLimit = defaults.integer(forKey: Keys.clipboardLimit)
        clipboardPollInterval = defaults.double(forKey: Keys.clipboardInterval)
        clipboardIgnoreConfidential = defaults.bool(forKey: Keys.clipboardConfidential)
        fileSearchShowHidden = defaults.bool(forKey: Keys.filesHidden)
        fileSearchResultLimit = defaults.integer(forKey: Keys.filesLimit)
    }

    var activeTheme: Theme {
        if followSystemAppearance {
            let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let selected = Theme.named(themeID)
            if selected.appearance == (isDark ? .dark : .light) { return selected }
            return isDark ? .raycastDark : .raycastLight
        }
        return Theme.named(themeID)
    }
}

