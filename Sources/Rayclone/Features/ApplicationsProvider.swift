import AppKit

/// Indexes launchable applications from the standard application folders.
@MainActor
final class ApplicationsProvider: CommandProvider {
    let id = "applications"

    struct InstalledApp: Codable, Identifiable {
        var id: String { bundlePath }
        let bundlePath: String
        let name: String
        let bundleIdentifier: String?
    }

    private var installed: [InstalledApp] = []
    private var lastScan: Date = .distantPast
    private let cacheURL = AppPaths.supportDirectory.appendingPathComponent("apps-index.json")

    init() {
        if let cached: [InstalledApp] = JSONStore.load([InstalledApp].self, from: cacheURL) {
            installed = cached
        }
        rescanIfNeeded(force: true)
    }

    func rescanIfNeeded(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastScan) > 600 else { return }
        lastScan = Date()

        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            // Safari and friends live in the Cryptexes volume; /Applications only
            // holds a hidden symlink to them.
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            AppPaths.home.appendingPathComponent("Applications"),
        ]

        var found: [String: InstalledApp] = [:]
        for root in roots {
            collect(in: root, depth: 0, into: &found)
        }

        installed = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        JSONStore.save(installed, to: cacheURL)
    }

    private func collect(in directory: URL, depth: Int, into found: inout [String: InstalledApp]) {
        guard depth <= 3 else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        // `.skipsHiddenFiles` is deliberately not used: macOS marks the
        // /Applications/Safari.app symlink hidden, which would drop Safari from
        // the index.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return }

        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if entry.pathExtension == "app" {
                let name = entry.deletingPathExtension().lastPathComponent
                let bundle = Bundle(url: entry)
                let identifier = bundle?.bundleIdentifier
                // Dedupe on the resolved path: /Applications holds symlinks into
                // /System/Cryptexes, so the same bundle can appear twice.
                let key = entry.resolvingSymlinksInPath().path
                if found[key] == nil {
                    found[key] = InstalledApp(bundlePath: entry.path, name: name, bundleIdentifier: identifier)
                }
            } else if values?.isDirectory == true, values?.isPackage != true {
                collect(in: entry, depth: depth + 1, into: &found)
            }
        }
    }

    func rootItems() -> [SearchItem] {
        // Applications are surfaced through search rather than a static root row.
        []
    }

    func items(for term: String, argument: String?) -> [SearchItem] {
        rescanIfNeeded()
        guard !term.isEmpty else { return [] }

        var results: [SearchItem] = []
        for app in installed {
            guard let score = FuzzyMatcher.score(term, in: app.name) else {
                // Also match on bundle path segments ("/Applications/Xcode.app").
                if FuzzyMatcher.score(term, in: app.bundlePath) == nil { continue }
                results.append(makeItem(app, subtitle: "Application"))
                continue
            }
            _ = score
            results.append(makeItem(app, subtitle: "Application"))
        }
        return results
    }

    private func makeItem(_ app: InstalledApp, subtitle: String) -> SearchItem {
        let url = URL(fileURLWithPath: app.bundlePath)
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == app.bundlePath }
        return SearchItem(
            id: "app:\(app.bundlePath)",
            title: app.name,
            subtitle: subtitle,
            accessory: isRunning ? "Running" : nil,
            keywords: [app.bundleIdentifier ?? ""],
            icon: .app(url),
            section: "Applications",
            // Applications (like Raycast) outrank incidental file matches.
            staticBoost: 90,
            actions: [
                ItemAction(id: "open", title: "Open Application", icon: "arrow.up.forward.app", shortcut: "↩") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                },
                ItemAction(id: "reveal", title: "Show in Finder", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                },
                ItemAction(id: "copyPath", title: "Copy Path", icon: "doc.on.doc") {
                    PasteService.copy(text: app.bundlePath)
                },
                ItemAction(id: "quit", title: "Quit Application", icon: "xmark.circle", shortcut: "⌘Q", style: .destructive) {
                    NSWorkspace.shared.runningApplications
                        .filter { $0.bundleURL?.path == app.bundlePath }
                        .forEach { $0.terminate() }
                },
            ]
        )
    }

    var allApps: [InstalledApp] { installed }
}

/// Rows for the currently running applications, used by system actions.
@MainActor
enum RunningAppsProvider {
    static func items(for term: String) -> [SearchItem] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> SearchItem? in
                guard let url = app.bundleURL else { return nil }
                let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
                if !term.isEmpty, FuzzyMatcher.score(term, in: name) == nil { return nil }
                return SearchItem(
                    id: "running:\(app.processIdentifier)",
                    title: name,
                    subtitle: "Running Application",
                    icon: .app(url),
                    section: "Running",
                    actions: [
                        ItemAction(id: "activate", title: "Switch to Application", icon: "arrow.up.forward.app") {
                            app.activate()
                        },
                        ItemAction(id: "quit", title: "Quit Application", icon: "xmark.circle", style: .destructive) {
                            app.terminate()
                        },
                        ItemAction(id: "forceQuit", title: "Force Quit", icon: "bolt.slash", style: .destructive) {
                            app.forceTerminate()
                        },
                    ]
                )
            }
    }
}
