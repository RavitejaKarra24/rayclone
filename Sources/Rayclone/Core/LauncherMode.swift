import Foundation

/// Raycast's "command views": a mode scopes root search to one command family.
enum LauncherMode: String, CaseIterable, Identifiable {
    case root
    case commands
    case applications
    case files
    case calculator
    case clipboard
    case snippets
    case emoji
    case quicklinks
    case scripts
    case windowManagement
    case system
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .root: return "Root Search"
        case .commands: return "Search Commands"
        case .applications: return "Applications"
        case .files: return "Search Files"
        case .calculator: return "Calculator History"
        case .clipboard: return "Clipboard History"
        case .snippets: return "Snippets"
        case .emoji: return "Emoji & Symbols"
        case .quicklinks: return "Quicklinks"
        case .scripts: return "Script Commands"
        case .windowManagement: return "Window Management"
        case .system: return "System Actions"
        case .settings: return "Settings"
        }
    }

    var placeholder: String {
        switch self {
        case .root: return "Search for apps and commands…"
        case .commands: return "Search commands…"
        case .applications: return "Search applications…"
        case .files: return "Search files…"
        case .calculator: return "Calculator history…"
        case .clipboard: return "Search clipboard history…"
        case .snippets: return "Search snippets…"
        case .emoji: return "Search emoji…"
        case .quicklinks: return "Search quicklinks…"
        case .scripts: return "Search script commands…"
        case .windowManagement: return "Move and resize windows…"
        case .system: return "Search system actions…"
        case .settings: return "Search settings…"
        }
    }

    var symbol: String {
        switch self {
        case .root: return "magnifyingglass"
        case .commands: return "command"
        case .applications: return "app.dashed"
        case .files: return "doc.text.magnifyingglass"
        case .calculator: return "plus.forwardslash.minus"
        case .clipboard: return "doc.on.clipboard"
        case .snippets: return "text.badge.checkmark"
        case .emoji: return "face.smiling"
        case .quicklinks: return "link"
        case .scripts: return "terminal"
        case .windowManagement: return "rectangle.split.2x2"
        case .system: return "gearshape.2"
        case .settings: return "switch.2"
        }
    }
}
