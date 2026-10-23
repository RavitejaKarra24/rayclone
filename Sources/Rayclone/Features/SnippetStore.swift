import AppKit
import Carbon.HIToolbox

/// Text snippets with Raycast-style dynamic placeholders
/// (`{date}`, `{time}`, `{datetime}`, `{clipboard}`, `{cursor}`, `{uuid}`).
@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    struct Snippet: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var name: String
        var keyword: String
        var content: String
        var createdAt: Date = Date()
    }

    @Published private(set) var snippets: [Snippet] = []
    private let fileURL = AppPaths.supportDirectory.appendingPathComponent("snippets.json")

    private init() {
        snippets = JSONStore.load([Snippet].self, from: fileURL) ?? []
    }

    func save() {
        JSONStore.save(snippets, to: fileURL)
    }

    func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    static func expand(_ template: String) -> String {
        var result = template
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let datetimeFormatter = DateFormatter()
        datetimeFormatter.dateStyle = .short
        datetimeFormatter.timeStyle = .short

        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{datetime}", with: datetimeFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{uuid}", with: UUID().uuidString)
        result = result.replacingOccurrences(
            of: "{clipboard}",
            with: NSPasteboard.general.string(forType: .string) ?? ""
        )
        result = result.replacingOccurrences(of: "{cursor}", with: "")
        return result
    }

    func items(for term: String) -> [SearchItem] {
        snippets.compactMap { snippet in
            if !term.isEmpty,
               FuzzyMatcher.score(term, in: snippet.name) == nil,
               FuzzyMatcher.score(term, in: snippet.keyword) == nil,
               FuzzyMatcher.score(term, in: snippet.content) == nil {
                return nil
            }
            let expanded = Self.expand(snippet.content)
            return SearchItem(
                id: "snippet:\(snippet.id.uuidString)",
                title: snippet.name,
                subtitle: snippet.keyword.isEmpty ? preview(snippet.content) : "\(snippet.keyword) · \(preview(snippet.content))",
                icon: .symbol("text.badge.checkmark"),
                section: "Snippets",
                staticBoost: 50,
                actions: [
                    ItemAction(id: "paste", title: "Paste Snippet", icon: "doc.on.clipboard", shortcut: "↩") {
                        PasteService.copy(text: expanded)
                        PasteService.paste()
                    },
                    ItemAction(id: "copy", title: "Copy Snippet", icon: "doc.on.doc") {
                        PasteService.copy(text: expanded)
                    },
                    ItemAction(id: "edit", title: "Edit Snippet", icon: "pencil") {
                        SnippetEditorWindowController.present(existing: snippet) { updated in
                            SnippetStore.shared.update(updated)
                        }
                    },
                    ItemAction(id: "delete", title: "Delete Snippet", icon: "trash", style: .destructive) {
                        SnippetStore.shared.delete(snippet.id)
                    },
                ]
            )
        }
    }

    private func preview(_ content: String) -> String {
        content.replacingOccurrences(of: "\n", with: " ")
    }
}

/// Watches typed text system-wide and expands snippet keywords.
///
/// Requires Accessibility trust: expansion deletes the keyword characters with
/// synthetic keystrokes and pastes the snippet body.
@MainActor
final class SnippetExpander {
    static let shared = SnippetExpander()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var isRunning = false
    /// Suppresses the tap while we inject our own keystrokes.
    private var isInjecting = false

    var isEnabled: Bool { AppSettings.shared.snippetsEnabled }

    func start() {
        guard !isRunning, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let expander = Unmanaged<SnippetExpander>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated {
                    expander.handle(event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        buffer = ""
    }

    private func handle(event: CGEvent) {
        guard !isInjecting, isEnabled else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        guard let characters = event.keyboardString else {
            buffer = ""
            return
        }
        buffer += characters.lowercased()
        if buffer.count > 64 { buffer.removeFirst(buffer.count - 64) }

        let candidates = SnippetStore.shared.snippets.filter { !$0.keyword.isEmpty }
        for snippet in candidates where buffer.hasSuffix(snippet.keyword.lowercased()) {
            let keywordCount = snippet.keyword.count
            buffer = ""
            expand(snippet, keywordLength: keywordCount)
            return
        }
    }

    private func expand(_ snippet: SnippetStore.Snippet, keywordLength: Int) {
        let body = SnippetStore.expand(snippet.content)
        isInjecting = true
        PasteService.copy(text: body)
        for _ in 0..<keywordLength {
            PasteService.postKey(keyCode: CGKeyCode(kVK_Delete), flags: [])
        }
        PasteService.paste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isInjecting = false
        }
    }
}

extension CGEvent {
    /// The characters a key event produced, if any (control keys return nil).
    var keyboardString: String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        // Ignore control characters and arrow/navigation keys.
        guard let scalar = text.unicodeScalars.first, scalar.properties.generalCategory != .control else { return nil }
        return text
    }
}
