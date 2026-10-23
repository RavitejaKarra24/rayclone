import AppKit
import Foundation

/// Web searches: the built-in engines plus user-defined ones.
@MainActor
final class WebSearchStore: ObservableObject {
    static let shared = WebSearchStore()

    struct Search: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var name: String
        var template: String
        var keyword: String
        var icon: String = "globe"
        var isBuiltIn: Bool = false
    }

    @Published private(set) var searches: [Search] = []
    private let fileURL = AppPaths.supportDirectory.appendingPathComponent("web-searches.json")

    private static let builtIns: [Search] = [
        Search(name: "Google Search", template: "https://www.google.com/search?q={query}", keyword: "google", icon: "magnifyingglass", isBuiltIn: true),
        Search(name: "DuckDuckGo Search", template: "https://duckduckgo.com/?q={query}", keyword: "ddg", icon: "shield", isBuiltIn: true),
        Search(name: "Bing", template: "https://www.bing.com/search?q={query}", keyword: "bing", icon: "magnifyingglass.circle", isBuiltIn: true),
        Search(name: "YouTube", template: "https://www.youtube.com/results?search_query={query}", keyword: "yt", icon: "play.rectangle", isBuiltIn: true),
        Search(name: "GitHub", template: "https://github.com/search?q={query}", keyword: "gh", icon: "chevron.left.forwardslash.chevron.right", isBuiltIn: true),
        Search(name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search={query}", keyword: "wiki", icon: "book", isBuiltIn: true),
        Search(name: "Stack Overflow", template: "https://stackoverflow.com/search?q={query}", keyword: "so", icon: "text.alignleft", isBuiltIn: true),
        Search(name: "Amazon", template: "https://www.amazon.com/s?k={query}", keyword: "amazon", icon: "cart", isBuiltIn: true),
        Search(name: "Google Maps", template: "https://www.google.com/maps/search/{query}", keyword: "maps", icon: "map", isBuiltIn: true),
        Search(name: "X", template: "https://x.com/search?q={query}", keyword: "x", icon: "at", isBuiltIn: true),
    ]

    private init() {
        if let loaded: [Search] = JSONStore.load([Search].self, from: fileURL) {
            searches = loaded
        } else {
            searches = Self.builtIns
            JSONStore.save(searches, to: fileURL)
        }
    }

    func save() { JSONStore.save(searches, to: fileURL) }

    func add(_ search: Search) {
        searches.append(search)
        save()
    }

    func update(_ search: Search) {
        guard let index = searches.firstIndex(where: { $0.id == search.id }) else { return }
        searches[index] = search
        save()
    }

    func delete(_ id: UUID) {
        searches.removeAll { $0.id == id && !$0.isBuiltIn }
        save()
    }

    private func url(for search: Search, query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: search.template.replacingOccurrences(of: "{query}", with: encoded))
    }

    func items(for term: String, argument: String?) -> [SearchItem] {
        guard let argument, !argument.isEmpty else { return [] }
        var rows: [SearchItem] = []
        for search in searches {
            let matchesName = FuzzyMatcher.score(term, in: search.name) != nil
            let matchesKeyword = FuzzyMatcher.score(term, in: search.keyword) != nil
            guard matchesName || matchesKeyword else { continue }
            rows.append(SearchItem(
                id: "websearch:\(search.id.uuidString)",
                title: "\(search.name): \(argument)",
                subtitle: search.template,
                icon: .symbol(search.icon),
                section: "Web Searches",
                staticBoost: 200,
                actions: [
                    ItemAction(id: "open", title: "Search \(search.name)", icon: "globe", shortcut: "↩") {
                        if let url = self.url(for: search, query: argument) {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    ItemAction(id: "copy", title: "Copy URL", icon: "doc.on.doc") {
                        if let url = self.url(for: search, query: argument) {
                            PasteService.copy(text: url.absoluteString)
                        }
                    },
                ]
            ))
        }
        return rows
    }
}
