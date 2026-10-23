import AppKit
import Foundation

/// Emoji & Symbols picker backed by the bundled dataset generated from the
/// Unicode character database.
@MainActor
final class EmojiProvider: CommandProvider {
    let id = "emoji"

    struct Emoji: Codable {
        let emoji: String
        let name: String
        let keywords: [String]
        let group: String
        let order: Int
    }

    private(set) var emojis: [Emoji] = []
    private var searchCache: [String: [SearchItem]] = [:]

    init() {
        load()
    }

    private func load() {
        guard let url = AppResources.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Emoji].self, from: data) else {
            emojis = []
            return
        }
        emojis = decoded
    }

    var isEmpty: Bool { emojis.isEmpty }

    func rootItems() -> [SearchItem] {
        recentItems()
    }

    func items(for term: String, argument: String?) -> [SearchItem] {
        guard !term.isEmpty else {
            // Empty query: recently used emoji first, then the full set so the
            // picker is browsable without typing.
            let recents = recentItems()
            let seen = Set(recents.map(\.id))
            // Browse order follows the canonical category order (faces first)
            // rather than raw code-point order, which starts mid-block.
            let rest = emojis
                .sorted { lhs, rhs in
                    let lhsRank = Self.groupRank(lhs.group)
                    let rhsRank = Self.groupRank(rhs.group)
                    if lhsRank != rhsRank { return lhsRank < rhsRank }
                    // Within a group, lead with the modern emoji planes so faces
                    // (U+1F600…) come before legacy misc symbols (U+261D…).
                    let lhsBlock = Self.blockRank(lhs.emoji)
                    let rhsBlock = Self.blockRank(rhs.emoji)
                    if lhsBlock != rhsBlock { return lhsBlock < rhsBlock }
                    return lhs.order < rhs.order
                }
                .prefix(240)
                .map(makeItem)
                .filter { !seen.contains($0.id) }
            return recents + rest
        }
        if let cached = searchCache[term] { return cached }

        var scored: [(Double, Emoji)] = []
        let lowered = term.lowercased()
        for emoji in emojis {
            var best: Double?
            if let score = FuzzyMatcher.score(lowered, in: emoji.name) { best = score }
            for keyword in emoji.keywords {
                if let score = FuzzyMatcher.score(lowered, in: keyword) {
                    best = max(best ?? score, score - 5)
                }
            }
            if let best { scored.append((best, emoji)) }
        }
        scored.sort { $0.0 > $1.0 }

        let items = scored.prefix(80).map { pair in makeItem(pair.1) }
        if searchCache.count > 200 { searchCache.removeAll() }
        searchCache[term] = items
        return items
    }

    private func makeItem(_ emoji: Emoji) -> SearchItem {
        SearchItem(
            id: "emoji:\(emoji.emoji)",
            title: emoji.name.capitalized,
            subtitle: emoji.group,
            keywords: emoji.keywords,
            icon: .emoji(emoji.emoji),
            section: "Emoji & Symbols",
            actions: [
                ItemAction(id: "paste", title: "Paste Emoji", icon: "doc.on.clipboard", shortcut: "↩") {
                    PasteService.copy(text: emoji.emoji)
                    EmojiProvider.remember(emoji.emoji)
                    PasteService.paste()
                },
                ItemAction(id: "copy", title: "Copy Emoji", icon: "doc.on.doc") {
                    PasteService.copy(text: emoji.emoji)
                    EmojiProvider.remember(emoji.emoji)
                },
            ]
        )
    }

    private func recentItems() -> [SearchItem] {
        let recents = EmojiProvider.recentEmoji()
        let lookup = Dictionary(emojis.map { ($0.emoji, $0) }, uniquingKeysWith: { first, _ in first })
        return recents.compactMap { symbol in
            guard let emoji = lookup[symbol] else { return nil }
            return SearchItem(
                id: "emoji:\(emoji.emoji)",
                title: emoji.name.capitalized,
                subtitle: "Recently used",
                icon: .emoji(emoji.emoji),
                section: "Emoji & Symbols",
                actions: [
                    ItemAction(id: "paste", title: "Paste Emoji", icon: "doc.on.clipboard", shortcut: "↩") {
                        PasteService.copy(text: emoji.emoji)
                        EmojiProvider.remember(emoji.emoji)
                        PasteService.paste()
                    }
                ]
            )
        }
    }

    private static func groupRank(_ group: String) -> Int {
        switch group {
        case "Smileys & People": return 0
        case "Animals & Nature": return 1
        case "Food & Drink": return 2
        case "Activity": return 3
        case "Travel & Places": return 4
        case "Objects": return 5
        case "Symbols": return 6
        case "Flags": return 7
        default: return 8
        }
    }

    private static func blockRank(_ emoji: String) -> Int {
        guard let first = emoji.unicodeScalars.first else { return 6 }
        switch first.value {
        case 0x1F600...0x1F64F: return 0 // emoticons / faces
        case 0x1F900...0x1F9FF: return 1 // supplemental symbols, gestures
        case 0x1F300...0x1F5FF: return 2 // misc symbols & pictographs
        case 0x1F680...0x1F6FF: return 3 // transport
        case 0x1F000...0x1F2FF: return 4 // legacy people/costumes
        case 0x2600...0x27BF: return 5     // misc symbols, dingbats
        default: return 6
        }
    }

    private static let recentsKey = "emoji.recents"

    static func remember(_ emoji: String) {
        var recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > 32 { recents.removeLast(recents.count - 32) }
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }

    static func recentEmoji() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }
}
