import AppKit
import Foundation

/// Quicklinks expand a URL template and open it. Raycast placeholders:
/// `{query}` (typed text) and `{argument}` (explicit arg after the command name).
@MainActor
final class QuicklinkStore: ObservableObject {
    static let shared = QuicklinkStore()

    struct Quicklink: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var name: String
        var link: String
        var icon: String = "link"
        var createdAt: Date = Date()
    }

    @Published private(set) var quicklinks: [Quicklink] = []
    private let fileURL = AppPaths.supportDirectory.appendingPathComponent("quicklinks.json")

    private init() {
        quicklinks = JSONStore.load([Quicklink].self, from: fileURL) ?? []
    }

    func save() { JSONStore.save(quicklinks, to: fileURL) }

    func add(_ link: Quicklink) {
        quicklinks.append(link)
        save()
    }

    func update(_ link: Quicklink) {
        guard let index = quicklinks.firstIndex(where: { $0.id == link.id }) else { return }
        quicklinks[index] = link
        save()
    }

    func delete(_ id: UUID) {
        quicklinks.removeAll { $0.id == id }
        save()
    }

    static func expand(_ template: String, term: String, argument: String?) -> URL? {
        var text = template
        let query = argument ?? term
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        text = text.replacingOccurrences(of: "{query}", with: encoded)
        text = text.replacingOccurrences(of: "{argument}", with: encoded)
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)
    }

    func items(for term: String, argument: String?) -> [SearchItem] {
        quicklinks.compactMap { link in
            let nameMatches = term.isEmpty || FuzzyMatcher.score(term, in: link.name) != nil
            guard nameMatches else { return nil }
            return SearchItem(
                id: "quicklink:\(link.id.uuidString)",
                title: link.name,
                subtitle: link.link,
                icon: .symbol(link.icon),
                section: "Quicklinks",
                staticBoost: 50,
                actions: [
                    ItemAction(id: "open", title: "Open Quicklink", icon: "arrow.up.forward.app", shortcut: "↩") {
                        if let url = Self.expand(link.link, term: term, argument: argument) {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    ItemAction(id: "copy", title: "Copy URL", icon: "doc.on.doc") {
                        if let url = Self.expand(link.link, term: term, argument: argument) {
                            PasteService.copy(text: url.absoluteString)
                        }
                    },
                    ItemAction(id: "edit", title: "Edit Quicklink", icon: "pencil") {
                        QuicklinkEditorWindowController.present(existing: link) { updated in
                            QuicklinkStore.shared.update(updated)
                        }
                    },
                    ItemAction(id: "delete", title: "Delete Quicklink", icon: "trash", style: .destructive) {
                        QuicklinkStore.shared.delete(link.id)
                    },
                ]
            )
        }
    }
}

