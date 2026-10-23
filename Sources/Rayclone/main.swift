import AppKit

// A SwiftPM executable cannot use `@main` alongside `main.swift`, so the app is
// bootstrapped explicitly. `main.swift` runs on the main thread, which lets us
// assert main-actor isolation for the AppKit setup below.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
