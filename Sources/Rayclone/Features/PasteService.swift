import AppKit
import Carbon.HIToolbox

/// Clipboard and keystroke plumbing shared by every "paste" action.
enum PasteService {
    /// Accessibility trust is required for synthetic keystrokes. Without it we
    /// still copy — the user can press ⌘V themselves.
    static var canPaste: Bool { AXIsProcessTrusted() }

    static var changeCount: Int { NSPasteboard.general.changeCount }

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func copy(richText: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let attributed = NSAttributedString(string: richText)
        pasteboard.writeObjects([attributed])
    }

    static func copy(files: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files as [NSURL])
    }

    static func copy(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    static func copy(items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for item in items { pasteboard.writeObjects([item]) }
    }

    /// Posts ⌘V to whatever app is frontmost. Call after the launcher hides and
    /// after a small delay so the target app has regained focus.
    /// Honours the "paste after choosing an item" preference: when it is off,
    /// actions only copy and the user pastes themselves.
    static func paste(into targetPID: pid_t? = nil) {
        guard canPaste else { return }
        guard UserDefaults.standard.object(forKey: "pasteOnPrimaryAction") as? Bool ?? true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            postCommandV()
            _ = targetPID
        }
    }

    static func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        vKeyDown?.flags = .maskCommand
        vKeyUp?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
    }

    /// Sends a key with modifiers, used by window management and full screen.
    static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Captures the frontmost app so the launcher can restore focus after it hides.
    static func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    static func activate(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }
}
