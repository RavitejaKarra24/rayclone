import AppKit
import Carbon.HIToolbox

/// A key + modifier pair registered system-wide through Carbon's
/// `RegisterEventHotKey`, which needs no accessibility permission and fires
/// while another app is frontmost.
struct HotKeyCombo: Equatable, Codable {
    var keyCode: Int
    var modifiers: Int

    static let launcherDefault = HotKeyCombo(keyCode: kVK_Space, modifiers: optionKey)
    static let clipboardDefault = HotKeyCombo(keyCode: kVK_ANSI_V, modifiers: optionKey | shiftKey)

    /// Carbon wants `cmdKey`-style flags; NSEvent gives `.command` etc.
    var carbonModifiers: Int {
        var flags = 0
        if modifiers & cmdKey != 0 { flags |= cmdKey }
        if modifiers & shiftKey != 0 { flags |= shiftKey }
        if modifiers & optionKey != 0 { flags |= optionKey }
        if modifiers & controlKey != 0 { flags |= controlKey }
        return flags
    }

    var display: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        text += Self.keyName(for: keyCode)
        return text
    }

    static func from(event: NSEvent) -> HotKeyCombo? {
        var mods = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        guard mods != 0 else { return nil }
        return HotKeyCombo(keyCode: Int(event.keyCode), modifiers: mods)
    }

    static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
            guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "Key \(keyCode)"
            }
            let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var length = 0
            var text = [UniChar](repeating: 0, count: 4)
            let status = data.withUnsafeBytes { raw -> OSStatus in
                guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
                return UCKeyTranslate(
                    layout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDisplay),
                    0,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    4,
                    &length,
                    &text
                )
            }
            guard status == noErr, length > 0 else { return "Key \(keyCode)" }
            return String(utf16CodeUnits: text, count: length).uppercased()
        }
    }
}

/// Owns every registered global hotkey and dispatches Carbon events to closures.
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var registered: [UInt32: GlobalHotKey] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    func register(_ combo: HotKeyCombo, handler: @escaping () -> Void) -> GlobalHotKey? {
        installHandlerIfNeeded()
        let hotKey = GlobalHotKey(combo: combo, handler: handler)
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5243_4C4E), id: id) // 'RCLN'
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            UInt32(combo.carbonModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }
        hotKey.hotKeyRef = ref
        hotKey.hotKeyID = hotKeyID
        registered[id] = hotKey
        return hotKey
    }

    func unregister(_ hotKey: GlobalHotKey) {
        if let ref = hotKey.hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        registered.removeValue(forKey: hotKey.hotKeyID.id)
    }

    fileprivate func dispatch(id: UInt32) {
        registered[id]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                GlobalHotKeyCenter.shared.dispatch(id: hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
        handlerInstalled = true
    }
}

final class GlobalHotKey {
    var hotKeyRef: EventHotKeyRef?
    var hotKeyID = EventHotKeyID()
    let handler: () -> Void

    init(combo: HotKeyCombo, handler: @escaping () -> Void) {
        self.handler = handler
    }
}
