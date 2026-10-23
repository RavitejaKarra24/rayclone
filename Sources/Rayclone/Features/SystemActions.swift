import AppKit
import Foundation
import Carbon.HIToolbox

/// Thin process helpers shared by the system actions.
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    @discardableResult
    static func zsh(_ command: String) -> (status: Int32, output: String) {
        run("/bin/zsh", ["-lc", command])
    }

    @discardableResult
    static func osascript(_ script: String) -> (status: Int32, output: String) {
        run("/usr/bin/osascript", ["-e", script])
    }

    /// Posts a `systemDefined` media key event (play/pause, next, previous).
    static func mediaKey(_ key: Int32) {
        for isDown in [true, false] {
            let flags = isDown ? 0xa00 : 0xb00
            let data1 = (key << 16) | Int32(flags)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int(data1),
                data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: .cghidEventTap)
        }
    }
}

/// The `System Actions` command group.
@MainActor
enum SystemActions {
    struct Action {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let keywords: [String]
        let destructive: Bool
        let perform: () -> Void
    }

    static func actions() -> [Action] {
        [
            Action(id: "system.sleep", title: "Sleep", subtitle: "Put the Mac to sleep", symbol: "moon.zzz", keywords: ["sleep", "standby"], destructive: false) {
                Shell.zsh("pmset sleepnow")
            },
            Action(id: "system.sleepDisplays", title: "Sleep Displays", subtitle: "Turn off the displays", symbol: "display", keywords: ["sleep", "display", "screen"], destructive: false) {
                Shell.zsh("pmset displaysleepnow")
            },
            Action(id: "system.lockScreen", title: "Lock Screen", subtitle: "Lock the current session", symbol: "lock", keywords: ["lock", "secure"], destructive: false) {
                Shell.run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
            },
            Action(id: "system.screenSaver", title: "Show Screen Saver", subtitle: "Start the screen saver", symbol: "sparkles.tv", keywords: ["screensaver"], destructive: false) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
            },
            Action(id: "system.emptyTrash", title: "Empty Trash", subtitle: "Permanently delete items in the Trash", symbol: "trash.slash", keywords: ["trash", "empty", "delete"], destructive: true) {
                Shell.osascript("tell application \"Finder\" to empty trash")
            },
            Action(id: "system.openTrash", title: "Open Trash", subtitle: "Show the Trash in Finder", symbol: "trash", keywords: ["trash"], destructive: false) {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
            },
            Action(id: "system.toggleHiddenFiles", title: "Toggle Hidden Files", subtitle: "Show or hide dotfiles in Finder", symbol: "eye.trianglebadge.exclamationmark", keywords: ["hidden", "dotfiles", "finder"], destructive: false) {
                toggleHiddenFiles()
            },
            Action(id: "system.toggleDarkMode", title: "Toggle System Appearance", subtitle: "Switch between Light and Dark", symbol: "circle.lefthalf.filled", keywords: ["dark", "light", "appearance", "theme"], destructive: false) {
                Shell.osascript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            },
            Action(id: "system.hideAllApps", title: "Hide All Apps", subtitle: "Hide every other application", symbol: "eye.slash", keywords: ["hide", "apps"], destructive: false) {
                for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                    if app.bundleIdentifier != Bundle.main.bundleIdentifier { app.hide() }
                }
            },
            Action(id: "system.quitAllApps", title: "Quit All Apps", subtitle: "Close every running application", symbol: "xmark.rectangle.stack", keywords: ["quit", "close", "apps"], destructive: true) {
                for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                    if app.bundleIdentifier != Bundle.main.bundleIdentifier { app.terminate() }
                }
            },
            Action(id: "system.quitAllExceptFrontmost", title: "Quit All Apps Except Frontmost", subtitle: "Keep only the active app running", symbol: "rectangle.on.rectangle.slash", keywords: ["quit", "apps"], destructive: true) {
                let frontmost = NSWorkspace.shared.frontmostApplication
                for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                    guard app.processIdentifier != frontmost?.processIdentifier,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
                    app.terminate()
                }
            },
            Action(id: "system.ejectDisks", title: "Eject All Disks", subtitle: "Unmount every ejectable volume", symbol: "eject", keywords: ["eject", "disk", "volume"], destructive: false) {
                Shell.zsh("osascript -e 'tell application \"Finder\" to eject (every disk whose ejectable is true)'")
            },
            Action(id: "system.volumeUp", title: "Turn Volume Up", subtitle: "Increase output volume", symbol: "speaker.plus", keywords: ["volume", "loud"], destructive: false) {
                adjustVolume(by: 10)
            },
            Action(id: "system.volumeDown", title: "Turn Volume Down", subtitle: "Decrease output volume", symbol: "speaker.minus", keywords: ["volume", "quiet"], destructive: false) {
                adjustVolume(by: -10)
            },
            Action(id: "system.toggleMute", title: "Toggle Mute", subtitle: "Mute or unmute audio output", symbol: "speaker.slash", keywords: ["mute", "silent"], destructive: false) {
                Shell.osascript("set volume output muted (not (output muted of (get volume settings)))")
            },
            Action(id: "system.setVolume25", title: "Set Volume to 25%", subtitle: "Output volume to 25 percent", symbol: "speaker.wave.1", keywords: ["volume"], destructive: false) { setVolume(25) },
            Action(id: "system.setVolume50", title: "Set Volume to 50%", subtitle: "Output volume to 50 percent", symbol: "speaker.wave.2", keywords: ["volume"], destructive: false) { setVolume(50) },
            Action(id: "system.setVolume75", title: "Set Volume to 75%", subtitle: "Output volume to 75 percent", symbol: "speaker.wave.2", keywords: ["volume"], destructive: false) { setVolume(75) },
            Action(id: "system.setVolume100", title: "Set Volume to 100%", subtitle: "Output volume to 100 percent", symbol: "speaker.wave.3", keywords: ["volume"], destructive: false) { setVolume(100) },
            Action(id: "system.playPause", title: "Play / Pause", subtitle: "Toggle media playback", symbol: "playpause", keywords: ["media", "music", "play"], destructive: false) {
                Shell.mediaKey(16)
            },
            Action(id: "system.nextTrack", title: "Next Track", subtitle: "Skip to the next track", symbol: "forward", keywords: ["media", "music"], destructive: false) {
                Shell.mediaKey(17)
            },
            Action(id: "system.previousTrack", title: "Previous Track", subtitle: "Go back a track", symbol: "backward", keywords: ["media", "music"], destructive: false) {
                Shell.mediaKey(18)
            },
            Action(id: "system.restart", title: "Restart", subtitle: "Restart the Mac", symbol: "arrow.clockwise", keywords: ["restart", "reboot"], destructive: true) {
                Shell.osascript("tell application \"System Events\" to restart")
            },
            Action(id: "system.shutDown", title: "Shut Down", subtitle: "Turn off the Mac", symbol: "power", keywords: ["shutdown", "power off"], destructive: true) {
                Shell.osascript("tell application \"System Events\" to shut down")
            },
            Action(id: "system.logOut", title: "Log Out", subtitle: "Log out of the current session", symbol: "person.crop.circle.badge.xmark", keywords: ["logout", "session"], destructive: true) {
                Shell.osascript("tell application \"System Events\" to log out")
            },
            Action(id: "system.showDesktop", title: "Show Desktop", subtitle: "Move all windows aside", symbol: "menubar.dock.rectangle", keywords: ["desktop", "expose"], destructive: false) {
                Shell.osascript("tell application \"System Events\" to key code 103")
            },
            Action(id: "system.toggleStageManager", title: "Toggle Stage Manager", subtitle: "Turn Stage Manager on or off", symbol: "rectangle.3.group", keywords: ["stage manager", "windows"], destructive: false) {
                Shell.zsh("defaults write com.apple.WindowManager GloballyEnabled -bool $(defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null | grep -q 1 && echo false || echo true) && killall WindowManager 2>/dev/null; true")
            },
        ]
    }

    static func items(for term: String) -> [SearchItem] {
        actions().compactMap { action in
            if !term.isEmpty,
               FuzzyMatcher.score(term, in: action.title) == nil,
               FuzzyMatcher.score(term, in: action.keywords.joined(separator: " ")) == nil {
                return nil
            }
            return SearchItem(
                id: action.id,
                title: action.title,
                subtitle: action.subtitle,
                keywords: action.keywords,
                icon: .symbol(action.symbol),
                section: "System Actions",
                actions: [
                    ItemAction(
                        id: "run",
                        title: action.title,
                        icon: action.symbol,
                        shortcut: "↩",
                        style: action.destructive ? .destructive : .normal
                    ) {
                        action.perform()
                    }
                ]
            )
        }
    }

    private static func adjustVolume(by delta: Int) {
        let current = Shell.osascript("output volume of (get volume settings)")
        let value = (Int(current.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50) + delta
        setVolume(min(max(value, 0), 100))
    }

    private static func setVolume(_ value: Int) {
        Shell.osascript("set volume output volume \(value)")
    }

    private static func toggleHiddenFiles() {
        let current = Shell.zsh("defaults read com.apple.finder AppleShowAllFiles 2>/dev/null").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let next = current == "1" || current.lowercased() == "true" ? "NO" : "YES"
        Shell.zsh("defaults write com.apple.finder AppleShowAllFiles -string \(next) && killall Finder")
    }
}
