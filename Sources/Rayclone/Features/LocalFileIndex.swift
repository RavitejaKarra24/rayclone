import Foundation

/// Name index of the files Spotlight will not report to this process.
///
/// Spotlight omits everything inside the TCC-protected home folders
/// (`~/Downloads`, `~/Desktop`, `~/Documents`) and iCloud Drive when the
/// querying app has not been granted access to them, which is the norm for a
/// locally built, ad-hoc signed bundle: `~/Downloads` itself and every file in
/// it were invisible to file search. Reading those folders directly works, so
/// they are enumerated here instead — on launch, when the launcher is shown,
/// and whenever the index has gone stale — and matched in memory so typing
/// stays cheap.
@MainActor
final class LocalFileIndex {
    struct Entry {
        let path: String
        let name: String
        /// `false` for packages (`.app`, `.photoslibrary`, …): they are opened,
        /// not browsed, so they are listed with the files.
        let isDirectory: Bool
        /// Number of path separators, used to prefer shallower files.
        let depth: Int
        let modified: Date
    }

    struct ScanResult {
        var entries: [Entry]
        /// `false` when a ceiling or the time budget cut the walk short; the
        /// next scan then runs sooner instead of trusting a partial index.
        var isComplete: Bool
    }

    /// Ceilings that keep one huge folder from stalling the background scan.
    nonisolated static let entryLimit = 30_000
    nonisolated static let timeBudget: TimeInterval = 3
    /// How long an index is trusted before a search rebuilds it.
    nonisolated static let maxAge: TimeInterval = 300
    /// Scans younger than this are reused even when asked to refresh, so
    /// showing the launcher repeatedly does not walk the disk every time.
    nonisolated static let refreshInterval: TimeInterval = 15

    private(set) var entries: [Entry] = []
    private(set) var isBuilding = false
    private var builtAt: Date?
    private var requestedAt: Date?
    /// The hidden-files setting the current entries were collected with.
    private var scannedHidden: Bool?

    /// Called on the main actor when a finished scan replaced the entries.
    var onUpdated: (() -> Void)?

    /// Folders whose contents Spotlight filters out for this app.
    nonisolated static var roots: [URL] {
        let home = AppPaths.home
        let candidates = [
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            // iCloud Drive is ordinary user content that lives under ~/Library.
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Rebuilds the index when it is missing, stale, or was collected with a
    /// different hidden-files setting. Cheap to call on every presentation.
    func refreshIfNeeded(showHidden: Bool, maxAge: TimeInterval = LocalFileIndex.maxAge) {
        guard !isBuilding else { return }
        let now = Date()
        let isStale = entries.isEmpty
            || scannedHidden != showHidden
            || now.timeIntervalSince(builtAt ?? .distantPast) > maxAge
        guard isStale else { return }
        guard now.timeIntervalSince(requestedAt ?? .distantPast) > Self.refreshInterval else { return }

        requestedAt = now
        isBuilding = true
        let roots = Self.roots
        Task.detached(priority: .utility) {
            let result = Self.scan(roots: roots, showHidden: showHidden)
            await MainActor.run {
                self.entries = result.entries
                self.builtAt = result.isComplete ? Date() : nil
                self.scannedHidden = showHidden
                self.isBuilding = false
                self.onUpdated?()
            }
        }
    }

    /// Entries whose name matches `term`, skipping paths Spotlight already
    /// reported.
    func matches(term: String, excluding paths: Set<String>) -> [Entry] {
        Self.filtered(entries, term: term, excluding: paths)
    }

    nonisolated static func filtered(_ entries: [Entry], term: String, excluding paths: Set<String>) -> [Entry] {
        guard term.count >= 2 else { return [] }
        return entries.filter { entry in
            !paths.contains(entry.path) && FileResultRanking.nameContains(entry.name, term: term)
        }
    }

    /// Walks `roots` and returns their contents, bounded by an entry ceiling and
    /// a wall-clock budget so a large folder cannot keep the scan running. A
    /// cold scan of a big folder can hit the budget, so `isComplete` reports
    /// whether the walk finished; the next scan (`refreshInterval` later, warm)
    /// fills in the rest.
    nonisolated static func scan(
        roots: [URL],
        showHidden: Bool,
        limit: Int = LocalFileIndex.entryLimit,
        budget: TimeInterval = LocalFileIndex.timeBudget
    ) -> ScanResult {
        let deadline = Date().addingTimeInterval(budget)
        let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = showHidden
            ? [.skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants]

        var entries: [Entry] = []
        for root in roots {
            guard entries.count < limit, Date() <= deadline else {
                return ScanResult(entries: entries, isComplete: false)
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: options,
                errorHandler: { _, _ in true }
            ) else { continue }

            var visited = 0
            for case let url as URL in enumerator {
                visited += 1
                // Checking the clock on every entry is not worth it.
                if visited % 256 == 0, Date() > deadline {
                    return ScanResult(entries: entries, isComplete: false)
                }
                guard entries.count < limit else {
                    return ScanResult(entries: entries, isComplete: false)
                }
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }
                let isPackage = values.isPackage ?? false
                entries.append(Entry(
                    path: url.path,
                    name: values.name ?? url.lastPathComponent,
                    isDirectory: (values.isDirectory ?? false) && !isPackage,
                    depth: pathDepth(url.path),
                    modified: values.contentModificationDate ?? .distantPast
                ))
            }
        }
        return ScanResult(entries: entries, isComplete: true)
    }

    nonisolated static func pathDepth(_ path: String) -> Int {
        path.reduce(0) { $1 == "/" ? $0 + 1 : $0 }
    }
}
