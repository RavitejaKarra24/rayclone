import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private static var window: NSWindow?

    static func present() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Rayclone Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

// MARK: - Snippet editor

struct SnippetEditorView: View {
    @State var name: String
    @State var keyword: String
    @State var content: String
    let onSave: (SnippetStore.Snippet) -> Void
    let onCancel: () -> Void
    private let originalID: UUID
    private let isNew: Bool

    init(existing: SnippetStore.Snippet?, onSave: @escaping (SnippetStore.Snippet) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: existing?.name ?? "")
        _keyword = State(initialValue: existing?.keyword ?? "")
        _content = State(initialValue: existing?.content ?? "")
        originalID = existing?.id ?? UUID()
        isNew = existing == nil
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Snippet" : "Edit Snippet")
                .font(.headline)
            TextField("Name", text: $name)
            TextField("Keyword (for auto-expansion)", text: $keyword)
            Text("Content — supports {date}, {time}, {datetime}, {clipboard}, {uuid}, {cursor}")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $content)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let snippet = SnippetStore.Snippet(id: originalID, name: name, keyword: keyword, content: content)
                    onSave(snippet)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 400)
    }
}

@MainActor
enum SnippetEditorWindowController {
    private static var window: NSWindow?

    static func present(existing: SnippetStore.Snippet?, onSave: @escaping (SnippetStore.Snippet) -> Void) {
        let view = SnippetEditorView(
            existing: existing,
            onSave: { snippet in
                onSave(snippet)
                close()
            },
            onCancel: { close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = existing == nil ? "Create Snippet" : "Edit Snippet"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private static func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Quicklink editor

struct QuicklinkEditorView: View {
    @State var name: String
    @State var link: String
    let onSave: (QuicklinkStore.Quicklink) -> Void
    let onCancel: () -> Void
    private let originalID: UUID
    private let isNew: Bool

    init(existing: QuicklinkStore.Quicklink?, onSave: @escaping (QuicklinkStore.Quicklink) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: existing?.name ?? "")
        _link = State(initialValue: existing?.link ?? "")
        originalID = existing?.id ?? UUID()
        isNew = existing == nil
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Quicklink" : "Edit Quicklink")
                .font(.headline)
            TextField("Name", text: $name)
            TextField("https://example.com/search?q={query}", text: $link)
            Text("Use {query} or {argument} where the search text should go.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(QuicklinkStore.Quicklink(id: originalID, name: name, link: link))
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(name.isEmpty || link.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 210)
    }
}

@MainActor
enum QuicklinkEditorWindowController {
    private static var window: NSWindow?

    static func present(existing: QuicklinkStore.Quicklink?, onSave: @escaping (QuicklinkStore.Quicklink) -> Void) {
        let view = QuicklinkEditorView(
            existing: existing,
            onSave: { link in
                onSave(link)
                close()
            },
            onCancel: { close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = existing == nil ? "Create Quicklink" : "Edit Quicklink"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private static func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Script output

@MainActor
enum OutputWindowController {
    private static var windows: [NSWindow] = []

    static func present(title: String, text: String) {
        let hosting = NSHostingController(rootView: OutputView(text: text))
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 620, height: 420))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        if windows.count > 8 { windows.removeFirst() }
    }
}

struct OutputView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(text.isEmpty ? "(no output)" : text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Copy Output") {
                    PasteService.copy(text: text)
                }
            }
            .padding(8)
        }
    }
}
