import AppKit
import Foundation
import Quartz

/// File search backed by Spotlight (`NSMetadataQuery`).
///
/// Queries are asynchronous, so the provider returns whatever the previous
/// query for the same term produced and asks the launcher to refresh once the
/// query finishes gathering.
@MainActor
final class FileProvider: CommandProvider {
    let id = "files"

    private var resultsByTerm: [String: [SearchItem]] = [:]
    private var activeTerm: String?
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private(set) var isSearching = false

    /// Called on the main actor when new file results are ready.
    var onResultsUpdated: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let query = notification.object as? NSMetadataQuery else { return }
                self.finish(query)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func rootItems() -> [SearchItem] { [] }

    func items(for term: String, argument: String?) -> [SearchItem] {
        guard term.count >= 2 else { return [] }
        start(term)
        return resultsByTerm[term] ?? []
    }

    private func start(_ term: String) {
        guard activeTerm != term else { return }
        activeTerm = term

        query?.stop()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
        query.predicate = NSPredicate(
            format: "kMDItemFSName LIKE[cd] %@ AND (kMDItemContentTypeTree == 'public.item' OR kMDItemContentTypeTree == 'public.folder')",
            "*\(term)*"
        )
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        query.valueListAttributes = [NSMetadataItemPathKey, NSMetadataItemFSNameKey, NSMetadataItemContentTypeKey]
        self.query = query
        isSearching = true
        query.start()
    }

    private func finish(_ query: NSMetadataQuery) {
        guard query === self.query else { return }
        query.disableUpdates()
        let limit = AppSettings.shared.fileSearchResultLimit
        let showHidden = AppSettings.shared.fileSearchShowHidden

        var items: [SearchItem] = []
        for index in 0..<min(query.resultCount, limit * 3) {
            guard let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if !showHidden, path.contains("/.") { continue }
            let url = URL(fileURLWithPath: path)
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            items.append(makeItem(url: url, isDirectory: isDirectory))
            if items.count >= limit { break }
        }
        query.enableUpdates()
        query.stop()
        isSearching = false

        if let term = activeTerm {
            resultsByTerm[term] = items
        }
        onResultsUpdated?()
    }

    private func makeItem(url: URL, isDirectory: Bool) -> SearchItem {
        let displayName = FileManager.default.displayName(atPath: url.path)
        return SearchItem(
            id: "file:\(url.path)",
            title: displayName,
            subtitle: abbreviatedPath(url),
            icon: .file(url),
            section: "Files",
            staticBoost: 0,
            actions: [
                ItemAction(id: "open", title: isDirectory ? "Open Folder" : "Open File", icon: "arrow.up.forward.app", shortcut: "↩") {
                    NSWorkspace.shared.open(url)
                },
                ItemAction(id: "reveal", title: "Show in Finder", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                },
                ItemAction(id: "quicklook", title: "Quick Look", icon: "eye", shortcut: "⌘Y") {
                    QuickLookPreviewer.present(url)
                },
                ItemAction(id: "openWith", title: "Open With…", icon: "app.badge") {
                    let panel = NSOpenPanel()
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Choose an app to open \(displayName)"
                    if panel.runModal() == .OK, let appURL = panel.url {
                        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                    }
                },
                ItemAction(id: "copyPath", title: "Copy Path", icon: "doc.on.doc") {
                    PasteService.copy(text: url.path)
                },
                ItemAction(id: "copyName", title: "Copy Name", icon: "textformat") {
                    PasteService.copy(text: displayName)
                },
                ItemAction(id: "trash", title: "Move to Trash", icon: "trash", style: .destructive) {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                },
            ]
        )
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let home = AppPaths.home.path
        var path = url.deletingLastPathComponent().path
        if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
        return path
    }
}

/// Inline Quick Look panel (space bar preview) without leaving the launcher.
@MainActor
enum QuickLookPreviewer {
    private static var panel: NSPanel?
    private static var controller: QLPreviewControllerBox?

    static func present(_ url: URL) {
        let box = QLPreviewControllerBox(url: url)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = FileManager.default.displayName(atPath: url.path)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentViewController = box.controller
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        self.controller = box
    }
}

private final class QLPreviewControllerBox {
    let controller: NSViewController

    init(url: URL) {
        if let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 720, height: 520)) {
            preview.previewItem = url as NSURL
            preview.autostarts = true
            let viewController = NSViewController()
            viewController.view = preview
            controller = viewController
        } else {
            let viewController = NSViewController()
            let label = NSTextField(labelWithString: "No preview available")
            label.alignment = .center
            viewController.view = label
            controller = viewController
        }
    }
}
