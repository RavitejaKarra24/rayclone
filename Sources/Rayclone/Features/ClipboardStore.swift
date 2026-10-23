import AppKit

/// Clipboard history: polls the general pasteboard, dedupes, persists text,
/// images and file references, and exposes them as searchable launcher rows.
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    enum Content: Codable {
        case text(String)
        case image(Data, width: Int, height: Int)
        case files([String])
    }

    struct Entry: Codable, Identifiable {
        var id: UUID
        var createdAt: Date
        var content: Content
        var sourceApp: String?
        var pinned: Bool = false

        var searchText: String {
            switch content {
            case .text(let text): return text
            case .image: return "image screenshot"
            case .files(let paths): return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: " ")
            }
        }

        var preview: String {
            switch content {
            case .text(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            case .image(let data, let width, let height):
                return "Image \(width)×\(height) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
            case .files(let paths):
                return paths.first.map { ($0 as NSString).lastPathComponent } ?? "Files"
            }
        }
    }

    private(set) var entries: [Entry] = []
    private var timer: Timer?
    private var lastChangeCount = -1
    private let fileURL = AppPaths.supportDirectory.appendingPathComponent("clipboard.json")
    private var isEnabled = false

    private init() {
        if let loaded: [Entry] = JSONStore.load([Entry].self, from: fileURL) {
            entries = loaded
        }
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        lastChangeCount = PasteService.changeCount
        let interval = max(AppSettings.shared.clipboardPollInterval, 0.25)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
    }

    private func poll() {
        let count = PasteService.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard AppSettings.shared.clipboardEnabled else { return }
        guard let captured = capture() else { return }

        if AppSettings.shared.clipboardIgnoreConfidential,
           NSPasteboard.general.types?.contains(.init("org.nspasteboard.ConcealedType")) == true {
            return
        }

        if let first = entries.first, sameContent(first.content, captured) { return }

        var entry = Entry(id: UUID(), createdAt: Date(), content: captured)
        entry.sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        entries.insert(entry, at: 0)
        trim()
        persist()
    }

    private func capture() -> Content? {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return .files(urls.map { $0.path })
        }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(string)
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return .image(png, width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return nil
    }

    private func sameContent(_ lhs: Content, _ rhs: Content) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        case (.image(let a, _, _), .image(let b, _, _)): return a == b
        case (.files(let a), .files(let b)): return a == b
        default: return false
        }
    }

    private func trim() {
        let limit = max(AppSettings.shared.clipboardHistoryLimit, 20)
        var pinned = entries.filter(\.pinned)
        var unpinned = entries.filter { !$0.pinned }
        if unpinned.count > limit {
            unpinned.removeLast(unpinned.count - limit)
        }
        pinned.append(contentsOf: unpinned)
        entries = pinned.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        JSONStore.save(entries, to: fileURL)
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
        persist()
    }

    func copyToPasteboard(_ entry: Entry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data, _, _):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .files(let paths):
            pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) } as [NSURL])
        }
        lastChangeCount = pasteboard.changeCount
    }

    func items(for term: String) -> [SearchItem] {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
        return sorted.compactMap { entry in
            let text = entry.searchText
            if !term.isEmpty, FuzzyMatcher.score(term, in: text) == nil { return nil }
            return SearchItem(
                id: "clipboard:\(entry.id.uuidString)",
                title: entry.preview,
                subtitle: subtitle(for: entry),
                accessory: entry.pinned ? "Pinned" : nil,
                keywords: [entry.sourceApp ?? ""],
                icon: icon(for: entry),
                section: "Clipboard History",
                actions: [
                    ItemAction(id: "paste", title: "Paste", icon: "doc.on.clipboard", shortcut: "↩") { [weak self] in
                        self?.copyToPasteboard(entry)
                        PasteService.paste()
                    },
                    ItemAction(id: "copy", title: "Copy to Clipboard", icon: "doc.on.doc") { [weak self] in
                        self?.copyToPasteboard(entry)
                    },
                    ItemAction(id: "pin", title: entry.pinned ? "Unpin" : "Pin", icon: "pin") { [weak self] in
                        self?.togglePin(entry.id)
                    },
                    ItemAction(id: "save", title: "Save to File", icon: "square.and.arrow.down") {
                        if case .text(let text) = entry.content {
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "Clipboard.txt"
                            if panel.runModal() == .OK, let url = panel.url {
                                try? text.write(to: url, atomically: true, encoding: .utf8)
                            }
                        }
                    },
                    ItemAction(id: "delete", title: "Delete", icon: "trash", shortcut: "⌘⌫", style: .destructive) { [weak self] in
                        self?.delete(entry.id)
                    },
                ]
            )
        }
    }

    private func subtitle(for entry: Entry) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let age = formatter.localizedString(for: entry.createdAt, relativeTo: Date())
        if let app = entry.sourceApp { return "\(app) · \(age)" }
        return age
    }

    private func icon(for entry: Entry) -> ItemIcon {
        switch entry.content {
        case .text: return .symbol("text.alignleft")
        case .image(let data, _, _):
            if let image = NSImage(data: data) { return .image(image) }
            return .symbol("photo")
        case .files: return .symbol("doc")
        }
    }
}
