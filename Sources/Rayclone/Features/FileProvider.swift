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

    /// Scanning every Spotlight hit is what keeps folders visible; cap it so a
    /// two-letter term cannot stall the main actor.
    private static let scanLimit = 1200

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
        query.valueListAttributes = [
            NSMetadataItemPathKey,
            NSMetadataItemFSNameKey,
            NSMetadataItemContentTypeKey,
            NSMetadataItemContentTypeTreeKey,
        ]
        self.query = query
        isSearching = true
        query.start()
    }

    private func finish(_ query: NSMetadataQuery) {
        guard query === self.query else { return }
        query.disableUpdates()
        let limit = max(1, AppSettings.shared.fileSearchResultLimit)
        let showHidden = AppSettings.shared.fileSearchShowHidden
        let term = activeTerm ?? ""

        // Spotlight can only sort by content-change date, so collect every
        // match (bounded) and rank by name here. Truncating the raw result set
        // is what hid folders: their modification dates are usually older than
        // the files that happen to share the substring and changed recently.
        var folders: [FileCandidate] = []
        var files: [FileCandidate] = []
        for index in 0..<min(query.resultCount, Self.scanLimit) {
            guard let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            guard showHidden || !Self.isNoise(path) else { continue }
            let url = URL(fileURLWithPath: path)
            let isDirectory = Self.isDirectory(result) ?? Self.isDirectoryOnDisk(url)
            let candidate = FileCandidate(
                item: makeItem(url: url, isDirectory: isDirectory),
                isDirectory: isDirectory,
                pathDepth: path.reduce(0) { $1 == "/" ? $0 + 1 : $0 },
                evidenceOrder: index
            )
            if isDirectory { folders.append(candidate) } else { files.append(candidate) }
        }
        query.enableUpdates()
        query.stop()
        isSearching = false

        let items = FileResultRanking.ordered(folders: folders, files: files, term: term, limit: limit)
        if !term.isEmpty {
            resultsByTerm[term] = items
        }
        onResultsUpdated?()
    }

    /// Folder detection from the indexed content type, which avoids a `stat`
    /// per result. Returns `nil` when the metadata does not say.
    private static func isDirectory(_ result: NSMetadataItem) -> Bool? {
        if let type = result.value(forAttribute: NSMetadataItemContentTypeKey) as? String {
            if type == "public.folder" { return true }
            if type == "public.item" { return nil }
            return false
        }
        if let tree = result.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] {
            return tree.contains("public.folder")
        }
        return nil
    }

    private static func isDirectoryOnDisk(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// Paths Spotlight indexes that only ever add noise to a launcher: hidden
    /// (dot) paths, system locations, and `~/Library` are skipped unless the
    /// user opts into hidden results. iCloud Drive lives under `~/Library` but
    /// is ordinary user content, so it stays.
    private static func isNoise(_ path: String) -> Bool {
        if path.contains("/.") { return true }
        for root in ["/System/", "/Library/", "/private/", "/usr/", "/bin/", "/sbin/", "/opt/"]
        where path.hasPrefix(root) {
            return true
        }
        let library = AppPaths.home.appendingPathComponent("Library", isDirectory: true).path
        if path == library { return true }
        if path.hasPrefix(library + "/"), !path.hasPrefix(library + "/Mobile Documents/") { return true }
        return false
    }

    private func makeItem(url: URL, isDirectory: Bool) -> SearchItem {
        let displayName = FileManager.default.displayName(atPath: url.path)
        return SearchItem(
            id: "file:\(url.path)",
            title: displayName,
            subtitle: abbreviatedPath(url),
            icon: .file(url),
            section: isDirectory ? "Folders" : "Files",
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
