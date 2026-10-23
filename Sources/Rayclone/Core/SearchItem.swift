import SwiftUI
import AppKit

/// A resolved action shown in the action panel and bound to ⏎ / ⌘K shortcuts.
struct ItemAction: Identifiable {
    enum Style { case normal, destructive }

    let id: String
    let title: String
    let icon: String
    var shortcut: String? = nil
    var style: Style = .normal
    let perform: () -> Void
}

enum ItemIcon {
    case symbol(String)
    case app(URL)
    case file(URL)
    case emoji(String)
    case image(NSImage)
    case monogram(String, Color)

    var nsImage: NSImage? {
        switch self {
        case .app(let url), .file(let url):
            return NSWorkspace.shared.icon(forFile: url.path)
        case .image(let image):
            return image
        default:
            return nil
        }
    }
}

/// One row in the launcher list. Produced by a `CommandProvider`, ranked by the
/// command center, then rendered by `RootView`.
struct SearchItem: Identifiable {
    let id: String
    var title: String
    var subtitle: String?
    var accessory: String?
    var keywords: [String] = []
    var icon: ItemIcon = .symbol("magnifyingglass")
    var section: String = "Results"
    /// Higher boosts rank independently of the fuzzy score (frecency, recency).
    var staticBoost: Double = 0
    var actions: [ItemAction] = []

    var primaryAction: ItemAction? { actions.first }
}

extension SearchItem {
    static func == (lhs: SearchItem, rhs: SearchItem) -> Bool { lhs.id == rhs.id }
}

/// A source of launcher rows. Providers stay synchronous so typing feels
/// instant; anything slow is pre-indexed in the background.
@MainActor
protocol CommandProvider {
    var id: String { get }
    /// Rows for an empty query (root search state).
    func rootItems() -> [SearchItem]
    /// Rows for a non-empty query. Return `[]` when the provider has nothing.
    func items(for term: String, argument: String?) -> [SearchItem]
}

extension CommandProvider {
    func items(for term: String, argument: String?) -> [SearchItem] { [] }
}
