import AppKit
import Foundation

/// Script Commands: user scripts in `Application Support/Rayclone/script-commands`
/// described by Raycast's `@raycast.*` metadata comment header.
@MainActor
final class ScriptCommandProvider: CommandProvider {
    let id = "script-commands"

    struct Metadata {
        var title: String
        var description: String?
        var mode: String
        var icon: String?
        var keyword: String?
        var packageName: String?
        var author: String?
        var argument1: String?
        var argument2: String?
        var needsConfirmation: Bool
    }

    struct ScriptCommand: Identifiable {
        var id: String { url.path }
        let url: URL
        let metadata: Metadata
    }

    private(set) var commands: [ScriptCommand] = []
    private var lastScan: Date = .distantPast

    func reload() {
        lastScan = Date()
        let root = AppPaths.scriptCommandsDirectory
        var found: [ScriptCommand] = []
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            commands = []
            return
        }
        for case let url as URL in enumerator {
            guard ["sh", "bash", "zsh", "py", "js", "ts", "applescript", "swift", "rb", "php"].contains(url.pathExtension) else { continue }
            guard let metadata = Self.parseMetadata(at: url) else { continue }
            found.append(ScriptCommand(url: url, metadata: metadata))
        }
        commands = found.sorted { $0.metadata.title < $1.metadata.title }
    }

    static func parseMetadata(at url: URL) -> Metadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: 4096)
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }

        var fields: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            // `Substring.range(of:)` misses some matches, so search a concrete String.
            let line = String(rawLine)
            // Metadata lives in comments, so the marker can be preceded by
            // `#`, `//`, `--`, `/*` or `*` depending on the script language.
            guard let marker = line.range(of: "@raycast.") else { continue }
            // Raycast's script metadata is whitespace separated:
            //   # @raycast.title My Script
            //   # @raycast.argument1 { "type": "text" }
            let body = line[line.index(marker.lowerBound, offsetBy: "@raycast.".count)...]
            let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let keyPart = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            fields[String(keyPart)] = value
        }
        guard let title = fields["title"] else { return nil }
        return Metadata(
            title: title,
            description: fields["description"],
            mode: fields["mode"] ?? "fullOutput",
            icon: fields["icon"],
            keyword: fields["keyword"],
            packageName: fields["packageName"],
            author: fields["author"],
            argument1: fields["argument1"],
            argument2: fields["argument2"],
            needsConfirmation: (fields["needsConfirmation"] ?? "false") == "true"
        )
    }

    func rootItems() -> [SearchItem] { [] }

    func items(for term: String, argument: String?) -> [SearchItem] {
        if Date().timeIntervalSince(lastScan) > 5 { reload() }
        return commands.compactMap { command in
            if !term.isEmpty,
               FuzzyMatcher.score(term, in: command.metadata.title) == nil,
               FuzzyMatcher.score(term, in: command.metadata.description ?? "") == nil,
               FuzzyMatcher.score(term, in: command.metadata.keyword ?? "") == nil {
                return nil
            }
            let iconSymbol: String
            if let rawIcon = command.metadata.icon, rawIcon.hasPrefix("sf-symbol:") {
                iconSymbol = String(rawIcon.dropFirst("sf-symbol:".count))
            } else {
                iconSymbol = "terminal"
            }
            return SearchItem(
                id: "script:\(command.id)",
                title: command.metadata.title,
                subtitle: command.metadata.description ?? command.url.lastPathComponent,
                accessory: command.metadata.mode,
                keywords: [command.metadata.keyword ?? "", command.url.lastPathComponent],
                icon: .symbol(iconSymbol),
                section: "Script Commands",
                staticBoost: 70,
                actions: [
                    ItemAction(id: "run", title: "Run Script", icon: "play", shortcut: "↩") {
                        ScriptRunner.run(command, argument: argument)
                    },
                    ItemAction(id: "reveal", title: "Show in Finder", icon: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([command.url])
                    },
                ]
            )
        }
    }
}

enum ScriptRunner {
    /// Runs the script and renders output through `OutputWindowController`,
    /// matching Raycast's `fullOutput` / `inline` / `silent` script modes.
    @MainActor
    static func run(_ command: ScriptCommandProvider.ScriptCommand, argument: String?) {
        let interpreter: String
        switch command.url.pathExtension {
        case "py": interpreter = "/usr/bin/python3"
        case "js": interpreter = "/usr/bin/env"
        case "ts": interpreter = "/usr/bin/env"
        case "rb": interpreter = "/usr/bin/ruby"
        case "php": interpreter = "/usr/bin/php"
        case "swift": interpreter = "/usr/bin/swift"
        case "applescript": interpreter = "/usr/bin/osascript"
        default: interpreter = "/bin/zsh"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: interpreter)
        if interpreter == "/usr/bin/env" {
            process.arguments = [command.url.pathExtension == "ts" ? "ts-node" : "node", command.url.path, argument ?? ""]
        } else if command.url.pathExtension == "applescript" {
            process.arguments = [command.url.path]
        } else {
            process.arguments = [command.url.path] + (argument.map { [$0] } ?? [])
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        do {
            try process.run()
        } catch {
            OutputWindowController.present(title: command.metadata.title, text: "Failed to launch: \(error.localizedDescription)")
            return
        }

        if command.metadata.mode.lowercased() == "silent" {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                OutputWindowController.present(title: command.metadata.title, text: output)
            }
        }
    }
}
