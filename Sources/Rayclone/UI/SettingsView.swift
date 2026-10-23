import AppKit
import SwiftUI

/// Hotkey capture field for the settings window.
struct HotKeyRecorderField: View {
    @Binding var combo: HotKeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    private var theme: Theme { AppSettings.shared.activeTheme }

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                Text(isRecording ? "Press a shortcut…" : combo.display)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isRecording ? theme.accent : Color.primary)
                if isRecording {
                    Text("⎋ to cancel")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? theme.accent : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            if let captured = HotKeyCombo.from(event: event) {
                combo = captured
                stop()
                return nil
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launcherCombo: HotKeyCombo
    @State private var clipboardCombo: HotKeyCombo
    @State private var permissionGranted = AXIsProcessTrusted()

    init() {
        let settings = AppSettings.shared
        _launcherCombo = State(initialValue: HotKeyCombo(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers))
        _clipboardCombo = State(initialValue: HotKeyCombo(keyCode: settings.clipboardHotkeyKeyCode, modifiers: settings.clipboardHotkeyModifiers))
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            featuresTab
                .tabItem { Label("Features", systemImage: "switch.2") }
            dataTab
                .tabItem { Label("Data", systemImage: "externaldrive") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 460)
        .onChange(of: launcherCombo) { _, newValue in
            settings.hotkeyKeyCode = newValue.keyCode
            settings.hotkeyModifiers = newValue.modifiers
            NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
        }
        .onChange(of: clipboardCombo) { _, newValue in
            settings.clipboardHotkeyKeyCode = newValue.keyCode
            settings.clipboardHotkeyModifiers = newValue.modifiers
            NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
        }
    }

    private var generalTab: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Open launcher") {
                    HotKeyRecorderField(combo: $launcherCombo)
                }
                LabeledContent("Clipboard history") {
                    HotKeyRecorderField(combo: $clipboardCombo)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Toggle("Follow system appearance", isOn: $settings.followSystemAppearance)
            }

            Section("Behaviour") {
                Toggle("Paste after choosing an item", isOn: $settings.pasteOnPrimaryAction)
                Toggle("Show recent items in root search", isOn: $settings.showRecentSection)
                Stepper("Maximum results: \(settings.maxResults)", value: $settings.maxResults, in: 10...200, step: 10)
            }
        }
        .formStyle(.grouped)
    }

    private var featuresTab: some View {
        Form {
            Section("Search sources") {
                Toggle("Applications", isOn: $settings.applicationsEnabled)
                Toggle("Files (Spotlight)", isOn: $settings.filesEnabled)
                Toggle("Calculator", isOn: $settings.calculatorEnabled)
                Toggle("Web searches", isOn: $settings.webSearchEnabled)
                Toggle("Quicklinks", isOn: $settings.quicklinksEnabled)
                Toggle("Script commands", isOn: $settings.scriptCommandsEnabled)
            }
            Section("Tools") {
                Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
                Toggle("Snippets", isOn: $settings.snippetsEnabled)
                Toggle("Emoji & symbols", isOn: $settings.emojiEnabled)
                Toggle("Window management", isOn: $settings.windowManagementEnabled)
                Toggle("System actions", isOn: $settings.systemActionsEnabled)
            }
            Section("Clipboard") {
                Stepper("History size: \(settings.clipboardHistoryLimit)", value: $settings.clipboardHistoryLimit, in: 50...5000, step: 50)
                Toggle("Ignore confidential pasteboard content", isOn: $settings.clipboardIgnoreConfidential)
                Button("Clear clipboard history") { ClipboardStore.shared.clear() }
            }
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Text(permissionGranted ? "Granted" : "Not granted")
                            .foregroundStyle(permissionGranted ? .green : .orange)
                        if !permissionGranted {
                            Button("Request") {
                                WindowManager.requestAccess()
                            }
                        }
                    }
                }
            }
            Section("Storage") {
                LabeledContent("Data folder") {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
                    }
                }
                LabeledContent("Script commands") {
                    Button("Open folder") {
                        NSWorkspace.shared.open(AppPaths.scriptCommandsDirectory)
                    }
                }
            }
            Section("Reset") {
                Button("Reset frecency and ranking") {
                    FrecencyStore.shared.reset()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppSettings.shared.activeTheme.accent)
            Text("Rayclone")
                .font(.system(size: 22, weight: .semibold))
            Text("Version 1.0.0")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("A native, open reimplementation of the Raycast launcher: root search, applications, files, calculator, clipboard history, snippets, emoji, quicklinks, script commands, window management and system actions.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer()
        }
        .padding(32)
        .onAppear { permissionGranted = AXIsProcessTrusted() }
    }
}

extension Theme: Identifiable {}

extension Notification.Name {
    static let hotkeysChanged = Notification.Name("hotkeysChanged")
}
