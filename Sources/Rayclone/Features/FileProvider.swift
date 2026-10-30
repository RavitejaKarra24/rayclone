import AppKit
import Foundation
import Quartz

/// File search backed by Spotlight (`NSMetadataQuery`), completed by direct
/// listings of the folders Spotlight withholds from this app.
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
    /// Rows built from the local index per kind. `FileResultRanking` re-ranks
    /// and cuts them, so this only bounds how many `displayName`/icon lookups
    /// one query can trigger.
    private static let localCandidateLimit = 120

    /// What one Spotlight query produced, kept so a late index rebuild can
    /// republish the same term without re-running the query.
    private struct Snapshot {
        var folders: [FileCandidate] = []
        var files: [FileCandidate] = []
        var paths = Set<String>()
    }

    private var resultsByTerm: [String: [SearchItem]] = [:]
    private var snapshot: (term: String, value: Snapshot)?
    private var activeTerm: String?
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var showObserver: NSObjectProtocol?
    private(set) var isSearching = false

    private let localIndex = LocalFileIndex()

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

        // The index only covers folders Spotlight hides, so it is refreshed
        // every time the launcher opens — a file that just landed in
        // `~/Downloads` has to be findable immediately — and again, at most
        // every few minutes, while a search runs.
        localIndex.onUpdated = { [weak self] in self?.republishFromIndex() }
        showObserver = NotificationCenter.default.addObserver(
            forName: .launcherDidShow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.localIndex.refreshIfNeeded(
                    showHidden: AppSettings.shared.fileSearchShowHidden,
                    maxAge: LocalFileIndex.refreshInterval
                )
            }
        }
        localIndex.refreshIfNeeded(showHidden: AppSettings.shared.fileSearchShowHidden)
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let showObserver { NotificationCenter.default.removeObserver(showObserver) }
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
        localIndex.refreshIfNeeded(showHidden: AppSettings.shared.fileSearchShowHidden)

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
        let showHidden = AppSettings.shared.fileSearchShowHidden
        let includeSystemPaths = AppSettings.shared.fileSearchIncludeSystemPaths
        let term = activeTerm ?? ""

        // Spotlight can only sort by content-change date, so collect every
        // match (bounded) and rank by name here. Truncating the raw result set
        // is what hid folders: their modification dates are usually older than
        // the files that happen to share the substring and changed recently.
        var collected = Snapshot()
        for index in 0..<min(query.resultCount, Self.scanLimit) {
            guard let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            guard showHidden || includeSystemPaths || !Self.isNoise(path) else { continue }
            guard collected.paths.insert(path).inserted else { continue }
            let url = URL(fileURLWithPath: path)
            let isDirectory = Self.isDirectory(result) ?? Self.isDirectoryOnDisk(url)
            let candidate = FileCandidate(
                item: makeItem(url: url, isDirectory: isDirectory),
                isDirectory: isDirectory,
                pathDepth: LocalFileIndex.pathDepth(path),
                evidenceOrder: index
            )
            if isDirectory { collected.folders.append(candidate) } else { collected.files.append(candidate) }
        }

        query.enableUpdates()
        query.stop()
        isSearching = false

        snapshot = (term, collected)
        publish(term)
    }

    /// Merges the Spotlight hits for `term` with the rows built from direct
    /// listings, ranks them, and publishes the result.
    private func publish(_ term: String) {
        guard !term.isEmpty, let snapshot, snapshot.term == term else { return }
        let settings = AppSettings.shared
        let showHidden = settings.fileSearchShowHidden
        let limit = max(1, settings.fileSearchResultLimit)

        var folders = snapshot.value.folders
        var files = snapshot.value.files
        var seenPaths = snapshot.value.paths

        // Spotlight reported nothing inside the TCC-protected folders, so the
        // home folders themselves (and, below, their contents) are listed here.
        let homeMatches = Self.matchingSubfolders(
            of: AppPaths.home,
            term: term,
            showHidden: showHidden,
            excluding: seenPaths
        )
        folders.append(contentsOf: homeMatches.enumerated().map { offset, url in
            FileCandidate(
                item: makeItem(url: url, isDirectory: true),
                isDirectory: true,
                pathDepth: LocalFileIndex.pathDepth(url.path),
                // After every Spotlight hit, so an indexed folder still wins a
                // tie against a directly listed one.
                evidenceOrder: Self.scanLimit + offset
            )
        })
        for url in homeMatches { seenPaths.insert(url.path) }

        let scanned = localIndex.matches(term: term, excluding: seenPaths)
        for candidate in localCandidates(from: scanned, term: term, limit: Self.localCandidateLimit) {
            if candidate.isDirectory { folders.append(candidate) } else { files.append(candidate) }
        }

        resultsByTerm[term] = FileResultRanking.ordered(
            folders: folders,
            files: files,
            term: term,
            limit: limit
        )
        if term == activeTerm { onResultsUpdated?() }
    }

    /// Turns index entries into rows, keeping the best names first so a broad
    /// term cannot force thousands of `displayName`/icon lookups.
    private func localCandidates(from entries: [LocalFileIndex.Entry], term: String, limit: Int) -> [FileCandidate] {
        let best = entries
            .sorted { lhs, rhs in
                let lhsScore = FileResultRanking.nameScore(lhs.name, term: term)
                let rhsScore = FileResultRanking.nameScore(rhs.name, term: term)
                if abs(lhsScore - rhsScore) > 0.001 { return lhsScore > rhsScore }
                if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
                return lhs.modified > rhs.modified
            }
            .prefix(limit)

        return best.enumerated().map { offset, entry in
            let url = URL(fileURLWithPath: entry.path)
            return FileCandidate(
                item: makeItem(url: url, isDirectory: entry.isDirectory),
                isDirectory: entry.isDirectory,
                pathDepth: entry.depth,
                evidenceOrder: offset
            )
        }
    }

    /// Re-publishes the active term after the local index finished a scan.
    private func republishFromIndex() {
        guard let term = activeTerm, !term.isEmpty else { return }
        publish(term)
    }

    /// Immediate subfolders of `directory` whose name matches `term`, found
    /// with `contentsOfDirectory` instead of Spotlight. Spotlight filters out
    /// results inside the TCC-protected home folders for an app that has not
    /// been granted access to them, which is the norm for a locally built,
    /// ad-hoc signed bundle; the home directory itself is readable, so its
    /// immediate subfolders are listed directly.
    static func matchingSubfolders(
        of directory: URL,
        term: String,
        showHidden: Bool,
        excluding seen: Set<String>
    ) -> [URL] {
        let listing = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: showHidden ? [] : [.skipsHiddenFiles]
        )) ?? []

        return listing
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .filter { url in
                guard !seen.contains(url.path),
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { return false }
                return FileResultRanking.nameContains(url.lastPathComponent, term: term)
            }
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
    /// user opts into hidden results or into system/library results. iCloud
    /// Drive lives under `~/Library` but is ordinary user content, so it stays.
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
