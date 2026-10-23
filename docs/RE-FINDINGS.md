# Raycast 2.8.2 — reverse-engineering findings

Scope: the locally installed, signed `com.raycast.macos` bundle at
`/Applications/Raycast.app`. Everything below is derived from shipped bytes on
this machine. No network calls to Raycast services were made, no account data
was read, and no code from the app was executed.

Authority labels used throughout:

- **observed** — literally present in the artifact (string, symbol, plist key, file).
- **derived** — read out of a structured shipped artifact (JS module, CSS, theming data).
- **inferred** — a conclusion drawn from the above, not directly proven.

> The app auto-updated from `2.8.2.0` to `2.9.0.0` while this analysis was in
> progress (its own `Updater`/`UpdaterDaemon` launch agents). The structural
> findings below were re-checked against 2.9.0 and still hold: same 36 bundled
> extensions, same IPC handler families, same frontend layout.

## 1. Bundle anatomy (observed)

```
Raycast.app/Contents/
├── Info.plist                     com.raycast.macos, LSUIElement=1
├── MacOS/Raycast                  16.2 MB arm64, symbol table has 0 defined symbols
├── Frameworks/
│   ├── libraycast_host.dylib      5.5 MB — the bulk of the native logic
│   └── Sentry.framework
├── XPCServices/
│   ├── Raycast Accessibility.xpc  accessibility/automation worker
│   └── Raycast Pasteboard.xpc     clipboard worker (isolates pasteboard access)
├── Library/Helpers/Raycast Palette.app      145 KB helper (palette window host)
├── Library/LaunchAgents/Updater.plist
├── Library/LaunchDaemons/Updater-Daemon.plist
└── Resources/
    ├── Assets.car                 10.9 MB icon/asset catalog
    ├── ripgrep/rg                 bundled ripgrep binary (fast file content search)
    ├── Updater, UpdaterDaemon
    └── macos-app_RaycastDesktopApp.bundle/Contents/Resources/frontend/   (56 MB)
        └── 566 JS chunks + 160 CSS modules + images/videos
```

Key `Info.plist` facts:

| Key | Value | Meaning |
| --- | --- | --- |
| `CFBundleIdentifier` | `com.raycast.macos` | |
| `LSMinimumSystemVersion` | `26.0` | current build targets macOS 26+ |
| `LSUIElement` | `1` | agent app, no Dock icon |
| `NSPrincipalClass` | `RaycastDesktopApp.Application` | Swift/AppKit app object |
| `CFBundleURLSchemes` | `raycast`, `raycast-x`, `com.raycast`, `com.raycast-x` | deep links |
| `CFBundleDocumentTypes` | `rayconfig` | configuration import/export |
| `NSBluetoothAlwaysUsageDescription` | … | Bluetooth device commands |
| `NSCalendarsFullAccessUsageDescription` | … | My Schedule / Create Event |
| `NSRemindersFullAccessUsageDescription` | … | Reminders commands |
| `NSContactsUsageDescription` | … | Search Contacts |
| `NSScreenCaptureUsageDescription` | … | window capture / AI context / screenshots |
| `NSMicrophoneUsageDescription` | … | dictation |
| `NSAppleEventsUsageDescription` | … | "control your Mac and run Shortcuts" |

`InternetAccessPolicy.plist` declares the network surface: `*.raycast.com`
(account, AI, sync, store, OAuth proxy, MCP), `*.raycast-releases.com` (updates),
Sentry (crash reporting), DuckDuckGo (bang list, favicons).

## 2. Architecture (derived + inferred)

The app is a **native Swift/Objective-C host plus a WebKit-rendered React UI**,
not a pure SwiftUI app and not Electron.

Evidence for the web UI:

- `Resources/.../frontend/` contains a Vite production build: hashed chunks
  (`main-window-*.js`, `settings-window-*.js`, `internal-extensions-*.js`),
  Vue-free React component CSS modules (`search-input__root_09da8`), and
  per-window HTML entry points (`theme-studio-window.html`).
- The IPC surface includes `RaycastInspectWebView`, `RaycastToggleInspectWebView`,
  `RaycastPurgeWebContentMemory`, `RaycastWebViewStateChanged`,
  `SettingsGetWebContentProcessMode`, `SettingsWebKitRenderUpdatesNear60Fps`,
  `SettingsGetWebContentProcessMode` — i.e. a `WKWebView` lifecycle is managed
  explicitly, with a configurable web-content process mode.

Evidence for the native host:

- `libraycast_host.dylib` + two XPC services carry the privileged work
  (accessibility automation, pasteboard, window management, file system).
- The UI talks to it over a typed IPC layer whose Swift module is
  `RaycastIPC` (symbol names like `s10RaycastIPC041WindowManagementShowGridPlacementHandlerType`).

So the data flow is:

```
React UI (WKWebView)  ──IPC──►  native host (libraycast_host.dylib)
        │                             │
        │                             ├── XPC: Accessibility, Pasteboard
        └── Extension runtime (Node)  ├── Local stores (encrypted .db)
                                      └── Raycast cloud (account, AI, sync, store)
```

## 3. IPC surface (observed)

590 distinct `*HandlerType` symbols encode the callable operations. Namespaces
recovered from symbol strings:

`Applications`, `AppMenuBar`, `Auth`, `Calendars`, `Clipboard`, `Contacts`,
`ContextMenu`, `Debug`, `Dictionary`, `FileSystem`, `Hotkey`, `Location`,
`Media`, `MenuBar`, `Navigation`, `Palette`, `Permissions`, `Raycast`
(+`RaycastFocus*`, `RaycastDictation*`, `RaycastShow*Window`), `Releases`,
`Screenshots`, `Settings`, `SharingService`, `Snippets`, `System`,
`UserDefaults`, `VirtualDesktops`, `Weather`, `WindowManagement`, `Workspace`,
`UiTesting`.

Representative members that shaped the clone:

- **Applications**: `GetAllInstalled`, `GetFrontmost`, `GetRunning`, `Open`,
  `Reveal`, `QuitAll`, `HideAllExceptFrontmost`, `Uninstall`, `GetCategory`,
  `GetDefault`, `GetDeveloperClis`, `GetSelectedText`, `GetFocusedTextFieldContent`
- **Clipboard**: `PlaceInClipboard`, `ClearPasteboard`, `GetFilePaths`,
  `GetImagePaths`, `ConvertImageToPng`, `DecodeQrCode`, `ShouldCaptureUniversalClipboard`
- **WindowManagement**: `SetWindowBounds`, `OpenAndSetWindowBounds`,
  `GetActiveWindow`, `GetVisibleWindows`, `GetWindowsOnActiveDesktop`,
  `GetMinimizedWindows`, `GetDesktops`, `ShowGridPlacement`, `MinimizeWindow`,
  `CloseWindow`
- **Snippets**: `Register`, `Expand`, `Remove`
- **Hotkey**: `Register`, `UpdateGlobal`, `Update`, `Remove`,
  `ToggleRecording`, `TranslateKeyCodes`, `SymbolicHotkeyStatus`,
  `ReplaceCommandHotkeys`
- **System**: `Sleep`, `SleepDisplays`, `LockScreen`, `LogOut`, `Restart`,
  `ShutDown`, `Hibernate`, `ShowScreenSaver`, `ToggleBluetooth`,
  `ToggleSystemAppearance`, `EjectAllDisks`, `DismissNotifications`,
  `PerformHapticFeedback`, `GetDisplays`, `GetAvailableInputSources`
- **Media**: `PlayPause`, `NextTrack`, `PreviousTrack`, `SetVolume`,
  `TurnVolumeUp/Down`, `ToggleMute`, `GetInputDevices`, `SetInputDevice`,
  `PlaySystemSound`
- **Workspace**: `GetWorkspaceContext`, `GetFrontmostAppContext`,
  `GetFocusedElementContext`, `CaptureScreen`, `CaptureScreenArea`,
  `CaptureWindowById`, `CaptureAiContext`
- **Settings**: `HyperKey*` (a Hyper key subsystem with health snapshots),
  `WindowPresentationMode`, `WindowActivationBehavior`, `MenuBarItem`,
  `OpenAtLogin`, `TidyMenuBar`, `ThemeChanged`

## 4. Bundled command catalog (derived)

`Resources/.../frontend/internal-extensions-*.js` is the built-in catalog:
**36 extensions** and roughly **190 commands** in the currently shipped build.

| Extension | Example commands |
| --- | --- |
| Applications | Uninstall Applications, Manage Auto Quits |
| Calculator | Calculator, Calculator History, Color, Weather, Flight Tracker |
| Calendar | My Schedule, Create Event |
| Clipboard History | Paste Sequentially, Reset Paste Sequence |
| System Actions | 46 commands — Sleep, Lock Screen, Volume ×N, Media, Eject Disks, Toggle Hidden Files, Toggle Stage Manager, Show Desktop |
| Window Management | Switch Desktops (+ grid placements generated at runtime) |
| Snippets | Create/Search/Auto Snippet, Import, Export |
| Quicklinks | Create/Search/Import/Export Quicklink |
| Script Commands | Search/Create/Reload Script Commands |
| Raycast (core) | 38 commands — Settings, Store, Changelog, Confetti, Inspect WebView, Export/Import Settings, Reset Window Position |
| Raycast Settings | Account, General, Launcher, Shortcuts, Keyboard, Cloud Sync, Advanced, Organizations, About |
| Dictation | 13 commands — Dictate, Dictate to AI, History, Vocabulary, Styles |
| Raycast Focus | 9 commands — Start/Toggle/Pause/Resume/Complete session, categories |
| MCP | Install/Manage MCP Servers, Switch Windows, Search Menu Bar Items |
| Screen Awareness | Send Selected Text / Screen / Window / Element to AI |
| Raycast Notes, Games, Developer, Dictionary, Contacts, Translator, Web Searches, URL, Emoji & Symbols, File Search, Screenshots, Browser, Apple Shortcuts, Raycast Wrapped, Raycast for Teams, Typing Practice, Trial Nudges, Account, Debug | … |

Each command definition carries: `title`, `description`, `icon`, `availability`,
`settings`/`preferences` (with per-preference `storage: synced|local|platform`
and defaults), an action list, and an argument schema. This is the schema the
clone's `BuiltinCommands` mirrors in miniature.

## 5. Design system (derived)

Tokens extracted from `css-*.css`:

```
space   2 4 6 8 12 16 24 32 40 48 56      (all scaled by --spx)
radius  2 4 6 8 10 12 16 18 20 26        (--radius-window = 26 on macOS 26, 8 otherwise)
font    8 11 13 16 18 24
icon    12 16 22 32
```

Colour is modelled as a base hue plus an opacity ramp rather than as a palette
of named swatches:

```
--fg-5 … --fg-80            foreground at 5–80 % alpha
--bg-5 … --bg-80            background at 5–80 % alpha
--color-border-secondary    = --fg-20
--color-border-separator    = --fg-10
--color-surface-list-hover  = --fg-5
--color-surface-list-selection = --fg-10
--color-text-secondary      = --fg-60
--color-text-tertiary       = --fg-40
```

Bundled theme values (from `contrast-improvement-*.js`):

| Theme | bg | fg | accent | red | orange | yellow | green | blue | purple | magenta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Raycast Dark | `#000000` | `#FFFFFF` | `#4FA3F8` | `#FF6363` | `#FF9217` | `#FFC531` | `#59D499` | `#56C2FF` | `#A485FF` | `#CF2F98` |
| Raycast Light | `#FFFFFF` | `#000000` | `#138AF2` | `#B12424` | `#C75D07` | `#F8A300` | `#006B4F` | `#138AF2` | `#6A3DEC` | `#9A1B6E` |
| Sky | `#0E1C3F` | `#D7F0F4` | `#4FA3F8` | `#ED5959` | `#ED8659` | `#EDD559` | `#47FF91` | `#1A9FFF` | `#7759ED` | `#ED59B2` |
| Sunset | `#451A08` | `#FADDD1` | `#4FA3F8` | `#ED5959` | `#ED8659` | `#EDD559` | `#59ED7A` | `#30BBE8` | `#7759ED` | `#ED59B2` |
| Midnight | `#070034` | `#FAF0FF` | `#4FA3F8` | `#F84141` | `#FFC100` | `#FEFF7F` | `#63BA89` | `#6AB7FF` | `#A485FF` | `#CF2F98` |

The clone implements exactly this model (`Theme.fg(_:)`, `Metric.*`).

## 6. Local data model (observed, partially opaque)

`~/Library/Application Support/com.raycast.macos/`:

```
ai.db  app_index.db  clipboard.db  emoji.db  frecency.db  main.db
node_extensions.db  screenshots.db  settings.db  settings_v2.db  user_activity.db
index/
  db/<timestamp>.{dat,meta,post,seg}  journal.wal     ← segment-based search index
  recent-files.json  queue.json  semantic-queue.json  stats.json  last-full-index.json
node/runtime, NodeJS/runtime                          ← embedded Node for extensions
posthog.*                                             ← product analytics queue
```

`sqlite3` refuses every `.db` file ("file is not a database"), so they are
encrypted or use a custom page format. Their *names* still map the feature
domains (AI, app index, clipboard, emoji, frecency ranking, settings, user
activity, screenshots, node extensions) — which is what informed the clone's
store layout.

**Limitation:** the on-disk schemas are not recoverable without the app's key
material, so the clone's persistence format is an independent design informed by
these domains, not a reproduction of Raycast's.

## 7. What was *not* recovered

- `main.db` / `clipboard.db` / `frecency.db` schemas (encrypted).
- The Node extension runtime's internal module graph (only the IPC contract is
  visible from the host side).
- Server APIs for accounts, AI, sync and the Store (they are network contracts,
  out of scope for a shipped-artifact read).
- Pixel-accurate UI: window screenshots of Raycast were unavailable on this host
  (window capture denied), so layout was reconstructed from the shipped CSS and
  the JS command definitions rather than from measurements of the running app.

## 8. Method notes / reproducibility

- Binary inspected with `nm`, `strings`, `otool -l`, `lipo -info`; the executable
  is stripped of defined symbols, so feature discovery came from Objective-C
  selector strings, Swift reflection metadata, and the shipped web bundle.
- `symbol table`: 4,831 entries, all undefined imports — no local function names.
- Command catalog parsed from `internal-extensions-*.js` with a regex over the
  `{key:\`…\`,title:\`…\`,description:\`…\`}` extension records and the
  `p({title:\`…\`})` command factory.
- Running-app window enumeration via `CGWindowListCopyWindowInfo`
  (owner `Raycast`, layer 25/101, 1280×760 "Welcome" window observed).
