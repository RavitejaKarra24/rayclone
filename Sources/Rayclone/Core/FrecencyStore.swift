import Foundation

/// Raycast-style frecency: usage events decay over time so recently and
/// frequently used commands float to the top of root search.
@MainActor
final class FrecencyStore {
    static let shared = FrecencyStore()

    struct Entry: Codable {
        var uses: [Date]
        var pinned: Bool = false
    }

    private var entries: [String: Entry] = [:]
    private let url: URL

    private init() {
        url = AppPaths.supportDirectory.appendingPathComponent("frecency.json")
        if let loaded: [String: Entry] = JSONStore.load([String: Entry].self, from: url) {
            entries = loaded
        }
    }

    func record(_ id: String) {
        var entry = entries[id] ?? Entry(uses: [])
        entry.uses.append(Date())
        if entry.uses.count > 24 { entry.uses.removeFirst(entry.uses.count - 24) }
        entries[id] = entry
        persist()
    }

    func isPinned(_ id: String) -> Bool { entries[id]?.pinned ?? false }

    func togglePin(_ id: String) {
        var entry = entries[id] ?? Entry(uses: [])
        entry.pinned.toggle()
        entries[id] = entry
        persist()
    }

    func pinnedIDs() -> [String] {
        entries.filter { $0.value.pinned }.keys.sorted()
    }

    /// Most-used item ids, best first, used to build the root search "Recent" list.
    func topIDs(limit: Int) -> [String] {
        entries
            .map { ($0.key, boost(for: $0.key)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func reset() {
        entries.removeAll()
        persist()
    }

    /// 0 … 100 boost added to the fuzzy score.
    func boost(for id: String) -> Double {
        guard let entry = entries[id] else { return 0 }
        var total = 0.0
        let now = Date()
        for date in entry.uses {
            let age = now.timeIntervalSince(date)
            switch age {
            case ..<3_600: total += 1.0
            case ..<86_400: total += 0.8
            case ..<(604_800): total += 0.6
            case ..<(2_592_000): total += 0.4
            default: total += 0.2
            }
        }
        if entry.pinned { total += 4.0 }
        // Squash so heavy usage cannot permanently dominate lexical relevance.
        return min(total, 12) * 6
    }

    private func persist() {
        JSONStore.save(entries, to: url)
    }
}
