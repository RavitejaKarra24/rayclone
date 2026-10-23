import Foundation
import SwiftUI

/// Gathers rows from every provider, ranks them, and remembers what was used.
@MainActor
final class CommandCenter: ObservableObject {
    static let shared = CommandCenter()

    let applications = ApplicationsProvider()
    let files = FileProvider()
    let calculator = CalculatorProvider()
    let emoji = EmojiProvider()
    let scriptCommands = ScriptCommandProvider()

    /// Cached rows keyed by id so frecency can resolve previously used items.
    private var registry: [String: SearchItem] = [:]
    private var builtinCache: [SearchItem] = []

    private init() {
        files.onResultsUpdated = { [weak self] in
            self?.objectWillChange.send()
            LauncherController.shared.refresh()
        }
        builtinCache = BuiltinCommands.items()
        for item in builtinCache { registry[item.id] = item }
        scriptCommands.reload()
    }

    // MARK: Search

    func search(_ raw: String, mode: LauncherMode) -> [SearchItem] {
        let settings = AppSettings.shared
        let parsed = ParsedQuery.parse(raw)

        var pool: [SearchItem] = []
        pool.append(contentsOf: builtinCache)
        if settings.applicationsEnabled { pool.append(contentsOf: applications.items(for: parsed.term, argument: parsed.argument)) }
        if settings.clipboardEnabled { pool.append(contentsOf: ClipboardStore.shared.items(for: parsed.term)) }
        if settings.snippetsEnabled { pool.append(contentsOf: SnippetStore.shared.items(for: parsed.term)) }
        if settings.quicklinksEnabled { pool.append(contentsOf: QuicklinkStore.shared.items(for: parsed.term, argument: parsed.argument)) }
        if settings.webSearchEnabled { pool.append(contentsOf: WebSearchStore.shared.items(for: parsed.term, argument: parsed.argument)) }
        if settings.scriptCommandsEnabled { pool.append(contentsOf: scriptCommands.items(for: parsed.term, argument: parsed.argument)) }
        if settings.systemActionsEnabled { pool.append(contentsOf: SystemActions.items(for: parsed.term)) }
        if settings.windowManagementEnabled, mode == .root || mode == .windowManagement {
            pool.append(contentsOf: WindowManagementProvider.items(for: parsed.term))
        }
        if settings.emojiEnabled, mode == .emoji { pool.append(contentsOf: emoji.items(for: parsed.term, argument: nil)) }
        if settings.calculatorEnabled, mode == .root { pool.append(contentsOf: calculator.items(for: parsed.term, argument: nil)) }
        if settings.filesEnabled, mode == .root || mode == .files, !parsed.term.isEmpty {
            pool.append(contentsOf: files.items(for: parsed.term, argument: nil))
        }

        let scoped = applyMode(mode, to: pool)
        for item in scoped where registry[item.id] == nil { registry[item.id] = item }

        guard !parsed.term.isEmpty else {
            return rootOrdering(scoped, mode: mode)
        }

        var scored: [(SearchItem, Double)] = []
        for item in scoped {
            guard let score = relevance(parsed.term, item: item) else { continue }
            let total = score + item.staticBoost + FrecencyStore.shared.boost(for: item.id)
            scored.append((item, total))
        }
        scored.sort { lhs, rhs in
            // Group by section first so the list never repeats a header, then
            // rank inside the group by relevance.
            let lhsRank = sectionRank(lhs.0.section)
            let rhsRank = sectionRank(rhs.0.section)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if abs(lhs.1 - rhs.1) > 0.001 { return lhs.1 > rhs.1 }
            return lhs.0.title.count < rhs.0.title.count
        }
        return scored.prefix(AppSettings.shared.maxResults).map(\.0)
    }

    /// Display order of result sections.
    private func sectionRank(_ section: String) -> Int {
        ResultSectionOrder.rank(section)
    }

    private func relevance(_ term: String, item: SearchItem) -> Double? {
        var best: Double?
        if let score = FuzzyMatcher.score(term, in: item.title) { best = score }
        if let subtitle = item.subtitle, let score = FuzzyMatcher.score(term, in: subtitle) {
            best = max(best ?? 0, score * 0.7)
        }
        for keyword in item.keywords where !keyword.isEmpty {
            if let score = FuzzyMatcher.score(term, in: keyword) {
                best = max(best ?? 0, score * 0.6)
            }
        }
        return best
    }

    private func applyMode(_ mode: LauncherMode, to pool: [SearchItem]) -> [SearchItem] {
        func filter(_ predicate: (SearchItem) -> Bool) -> [SearchItem] { pool.filter(predicate) }
        switch mode {
        case .root, .commands:
            return pool
        case .applications:
            return filter { $0.id.hasPrefix("app:") }
        case .files:
            return filter { $0.id.hasPrefix("file:") }
        case .clipboard:
            return filter { $0.id.hasPrefix("clipboard:") }
        case .snippets:
            return filter { $0.id.hasPrefix("snippet:") || $0.id.hasPrefix("app:") }
        case .emoji:
            return filter { $0.id.hasPrefix("emoji:") }
        case .quicklinks:
            return filter { $0.id.hasPrefix("quicklink:") }
        case .scripts:
            return filter { $0.id.hasPrefix("script:") }
        case .windowManagement:
            return filter { $0.id.hasPrefix("window:") }
        case .system:
            return filter { $0.id.hasPrefix("system.") }
        case .calculator:
            return []
        case .settings:
            return filter { $0.id.hasPrefix("command.") }
        }
    }

    private func rootOrdering(_ pool: [SearchItem], mode: LauncherMode) -> [SearchItem] {
        switch mode {
        case .windowManagement:
            return WindowManagementProvider.items(for: "")
        case .calculator:
            return AppSettings.shared.historyEnabled ? calculator.historyItems() : []
        case .emoji:
            return emoji.items(for: "", argument: nil)
        case .settings:
            return pool
        default:
            break
        }

        var rows: [SearchItem] = []
        var seen = Set<String>()
        let allowed = Set(pool.map(\.id))

        let pinned = FrecencyStore.shared.pinnedIDs().filter { allowed.contains($0) }
        for id in pinned {
            if let item = registry[id], seen.insert(id).inserted { rows.append(item) }
        }
        let frecent = AppSettings.shared.showRecentSection
            ? FrecencyStore.shared.topIDs(limit: 8).filter { allowed.contains($0) }
            : []
        for id in frecent where !pinned.contains(id) {
            if let item = registry[id], seen.insert(id).inserted { rows.append(item) }
        }
        for item in pool where seen.insert(item.id).inserted {
            rows.append(item)
        }

        // Group sections without disturbing the frecency order inside them.
        let ordered = rows.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = sectionRank(lhs.element.section)
                let rhsRank = sectionRank(rhs.element.section)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return Array(ordered.prefix(AppSettings.shared.maxResults))
    }

    func item(withID id: String) -> SearchItem? { registry[id] }

    func register(_ items: [SearchItem]) {
        for item in items where registry[item.id] == nil { registry[item.id] = item }
    }
}

/// Window targets surfaced as launcher rows.
@MainActor
enum WindowManagementProvider {
    static func items(for term: String) -> [SearchItem] {
        var rows: [SearchItem] = []
        for target in WindowManager.allTargets {
            let title = WindowManager.title(for: target)
            if !term.isEmpty, FuzzyMatcher.score(term, in: title) == nil { continue }
            rows.append(SearchItem(
                id: "window:\(String(describing: target))",
                title: title,
                subtitle: "Window Management",
                keywords: ["window", "resize", "move"],
                icon: .symbol(WindowManager.symbolName(for: target)),
                section: "Window Management",
                actions: [
                    ItemAction(id: "apply", title: title, icon: WindowManager.symbolName(for: target), shortcut: "↩") {
                        guard WindowManager.isTrusted else {
                            // Window control needs Accessibility, so prompt instead of
                            // failing silently.
                            WindowManager.requestAccess()
                            return
                        }
                        WindowManager.apply(target)
                    }
                ]
            ))
        }
        return rows
    }
}
