import AppKit
import Foundation

/// The launcher's own commands — the equivalent of Raycast's built-in
/// `Raycast`, `Raycast Settings`, `Clipboard History`, `Snippets`, `Window
/// Management` and `System` extension commands.
@MainActor
enum BuiltinCommands {
    static func items() -> [SearchItem] {
        var items: [SearchItem] = []

        func command(
            id: String,
            title: String,
            subtitle: String,
            symbol: String,
            keywords: [String],
            actionTitle: String,
            perform: @escaping () -> Void
        ) -> SearchItem {
            SearchItem(
                id: id,
                title: title,
                subtitle: subtitle,
                keywords: keywords,
                icon: .symbol(symbol),
                section: "Rayclone",
                // Built-in commands are what Raycast surfaces first; incidental
                // file-name matches must not outrank them.
                staticBoost: 70,
                actions: [
                    ItemAction(id: "run", title: actionTitle, icon: symbol, shortcut: "↩", perform: perform)
                ]
            )
        }

        items.append(contentsOf: [
            command(
                id: "command.searchApps",
                title: "Search Applications",
                subtitle: "Browse and launch every installed app",
                symbol: "app.dashed",
                keywords: ["apps", "applications", "launch", "open"],
                actionTitle: "Search Applications"
            ) {
                LauncherController.shared.setMode(.applications)
            },
            command(
                id: "command.searchFiles",
                title: "Search Files",
                subtitle: "Find files with Spotlight",
                symbol: "doc.text.magnifyingglass",
                keywords: ["files", "find", "spotlight", "documents"],
                actionTitle: "Search Files"
            ) {
                LauncherController.shared.setMode(.files)
            },
            command(
                id: "command.clipboardHistory",
                title: "Clipboard History",
                subtitle: "Browse everything you copied",
                symbol: "doc.on.clipboard",
                keywords: ["clipboard", "paste", "history", "copy"],
                actionTitle: "Open Clipboard History"
            ) {
                LauncherController.shared.setMode(.clipboard)
            },
            command(
                id: "command.searchSnippets",
                title: "Search Snippets",
                subtitle: "Paste saved text snippets",
                symbol: "text.badge.checkmark",
                keywords: ["snippets", "text", "expand"],
                actionTitle: "Search Snippets"
            ) {
                LauncherController.shared.setMode(.snippets)
            },
            command(
                id: "command.createSnippet",
                title: "Create Snippet",
                subtitle: "Save reusable text with a keyword",
                symbol: "plus.rectangle.on.rectangle",
                keywords: ["snippets", "new", "create"],
                actionTitle: "Create Snippet"
            ) {
                SnippetEditorWindowController.present(existing: nil) { snippet in
                    SnippetStore.shared.add(snippet)
                }
            },
            command(
                id: "command.emoji",
                title: "Search Emoji & Symbols",
                subtitle: "Find and paste an emoji",
                symbol: "face.smiling",
                keywords: ["emoji", "symbols", "smileys"],
                actionTitle: "Search Emoji"
            ) {
                LauncherController.shared.setMode(.emoji)
            },
            command(
                id: "command.quicklinks",
                title: "Search Quicklinks",
                subtitle: "Open saved links with placeholders",
                symbol: "link",
                keywords: ["quicklinks", "links", "url", "bookmarks"],
                actionTitle: "Search Quicklinks"
            ) {
                LauncherController.shared.setMode(.quicklinks)
            },
            command(
                id: "command.createQuicklink",
                title: "Create Quicklink",
                subtitle: "Save a URL with {query} placeholders",
                symbol: "link.badge.plus",
                keywords: ["quicklink", "new", "create", "url"],
                actionTitle: "Create Quicklink"
            ) {
                QuicklinkEditorWindowController.present(existing: nil) { link in
                    QuicklinkStore.shared.add(link)
                }
            },
            command(
                id: "command.scriptCommands",
                title: "Search Script Commands",
                subtitle: "Run your own scripts from the launcher",
                symbol: "terminal",
                keywords: ["scripts", "shell", "automation"],
                actionTitle: "Search Script Commands"
            ) {
                LauncherController.shared.setMode(.scripts)
            },
            command(
                id: "command.reloadScripts",
                title: "Reload Script Commands",
                subtitle: "Re-scan the script-commands folder",
                symbol: "arrow.triangle.2.circlepath",
                keywords: ["scripts", "reload", "refresh"],
                actionTitle: "Reload Scripts"
            ) {
                CommandCenter.shared.scriptCommands.reload()
                LauncherController.shared.refresh()
            },
            command(
                id: "command.createScriptCommand",
                title: "Create Script Command",
                subtitle: "Add a template script to your commands folder",
                symbol: "square.and.pencil",
                keywords: ["script", "create", "template"],
                actionTitle: "Create Script Command"
            ) {
                createScriptTemplate()
            },
            command(
                id: "command.windowManagement",
                title: "Window Management",
                subtitle: "Move and resize the focused window",
                symbol: "rectangle.split.2x2",
                keywords: ["windows", "resize", "move", "tile", "snap"],
                actionTitle: "Open Window Management"
            ) {
                LauncherController.shared.setMode(.windowManagement)
            },
            command(
                id: "command.systemActions",
                title: "System Actions",
                subtitle: "Sleep, lock, volume, media and more",
                symbol: "gearshape.2",
                keywords: ["system", "sleep", "lock", "volume", "mute", "restart"],
                actionTitle: "Open System Actions"
            ) {
                LauncherController.shared.setMode(.system)
            },
            command(
                id: "command.calculatorHistory",
                title: "Calculator History",
                subtitle: "Previously evaluated expressions",
                symbol: "clock.arrow.circlepath",
                keywords: ["calculator", "math", "history"],
                actionTitle: "Open Calculator History"
            ) {
                LauncherController.shared.setMode(.calculator)
            },
            command(
                id: "command.settings",
                title: "Rayclone Settings",
                subtitle: "Hotkeys, appearance and features",
                symbol: "switch.2",
                keywords: ["settings", "preferences", "config", "hotkey", "theme"],
                actionTitle: "Open Settings"
            ) {
                SettingsWindowController.present()
            },
            command(
                id: "command.clearClipboard",
                title: "Clear Clipboard History",
                subtitle: "Delete every stored clipboard entry",
                symbol: "trash",
                keywords: ["clipboard", "clear", "delete"],
                actionTitle: "Clear Clipboard History"
            ) {
                ClipboardStore.shared.clear()
            },
            command(
                id: "command.reindexApps",
                title: "Reindex Applications",
                subtitle: "Rescan installed applications",
                symbol: "arrow.clockwise",
                keywords: ["apps", "reindex", "refresh"],
                actionTitle: "Reindex Applications"
            ) {
                CommandCenter.shared.applications.rescanIfNeeded(force: true)
                LauncherController.shared.refresh()
            },
            command(
                id: "command.checkAccessibility",
                title: "Grant Accessibility Access",
                subtitle: "Needed for pasting, snippets and window control",
                symbol: "hand.raised",
                keywords: ["permissions", "accessibility", "paste"],
                actionTitle: "Request Access"
            ) {
                WindowManager.requestAccess()
            },
            command(
                id: "command.quit",
                title: "Quit Rayclone",
                subtitle: "Close the launcher",
                symbol: "power",
                keywords: ["quit", "exit", "close"],
                actionTitle: "Quit Rayclone"
            ) {
                NSApplication.shared.terminate(nil)
            },
        ])

        return items
    }

    private static func createScriptTemplate() {
        let url = AppPaths.scriptCommandsDirectory.appendingPathComponent("my-script.sh")
        let template = """
        #!/bin/bash

        # @raycast.schemaVersion 1
        # @raycast.title My Script
        # @raycast.mode fullOutput
        # @raycast.icon terminal
        # @raycast.description Describe what your script does

        echo "Hello from Rayclone script commands"
        """
        try? template.write(to: url, atomically: true, encoding: .utf8)
        Shell.zsh("chmod +x '\(url.path)'")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
