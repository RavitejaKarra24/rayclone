import SwiftUI
import AppKit

/// Design tokens recovered from the shipped Raycast frontend bundle
/// (`macos-app_RaycastDesktopApp.bundle/.../css-*.css` and the bundled theme
/// definitions in `contrast-improvement-*.js`).
///
/// Raycast models colour as `foreground`/`background` plus opacity ramps
/// (`--fg-5` … `--fg-80`). We keep that model instead of inventing a new one.
struct Theme: Equatable {
    var id: String
    var name: String
    var appearance: Appearance

    var background: Color
    var backgroundSecondary: Color
    var foreground: Color
    var accent: Color
    var selection: Color
    var loader: Color
    var red: Color
    var orange: Color
    var yellow: Color
    var green: Color
    var blue: Color
    var purple: Color
    var magenta: Color

    enum Appearance: String { case dark, light }

    var isDark: Bool { appearance == .dark }

    func fg(_ percent: Double) -> Color { foreground.opacity(percent / 100) }
    func bg(_ percent: Double) -> Color { foreground.opacity(percent / 100) }

    /// `--color-surface-list-selection`
    var rowSelection: Color { fg(10) }
    /// `--color-surface-list-hover`
    var rowHover: Color { fg(5) }
    /// `--color-border-secondary`
    var borderSecondary: Color { fg(20) }
    /// `--color-border-separator`
    var borderSeparator: Color { fg(10) }
    /// `--color-text-secondary`
    var textSecondary: Color { fg(60) }
    /// `--color-text-tertiary`
    var textTertiary: Color { fg(40) }
    /// `--color-surface-action-bar`
    var actionBarSurface: Color { fg(5) }
}

extension Theme {
    static let raycastDark = Theme(
        id: "raycast-dark",
        name: "Raycast Dark",
        appearance: .dark,
        background: Color(hex: 0x000000),
        backgroundSecondary: Color(hex: 0x000000),
        foreground: Color(hex: 0xFFFFFF),
        accent: Color(hex: 0x4FA3F8),
        selection: Color(hex: 0xFFFFFF),
        loader: Color(hex: 0xFFFFFF),
        red: Color(hex: 0xFF6363),
        orange: Color(hex: 0xFF9217),
        yellow: Color(hex: 0xFFC531),
        green: Color(hex: 0x59D499),
        blue: Color(hex: 0x56C2FF),
        purple: Color(hex: 0xA485FF),
        magenta: Color(hex: 0xCF2F98)
    )

    static let raycastLight = Theme(
        id: "raycast-light",
        name: "Raycast Light",
        appearance: .light,
        background: Color(hex: 0xFFFFFF),
        backgroundSecondary: Color(hex: 0xFFFFFF),
        foreground: Color(hex: 0x000000),
        accent: Color(hex: 0x138AF2),
        selection: Color(hex: 0x000000),
        loader: Color(hex: 0x000000),
        red: Color(hex: 0xB12424),
        orange: Color(hex: 0xC75D07),
        yellow: Color(hex: 0xF8A300),
        green: Color(hex: 0x006B4F),
        blue: Color(hex: 0x138AF2),
        purple: Color(hex: 0x6A3DEC),
        magenta: Color(hex: 0x9A1B6E)
    )

    static let sky = Theme(
        id: "sky",
        name: "Sky",
        appearance: .dark,
        background: Color(hex: 0x0E1C3F),
        backgroundSecondary: Color(hex: 0x173036),
        foreground: Color(hex: 0xD7F0F4),
        accent: Color(hex: 0x4FA3F8),
        selection: Color(hex: 0x6688FF),
        loader: Color(hex: 0x47FFFF),
        red: Color(hex: 0xED5959),
        orange: Color(hex: 0xED8659),
        yellow: Color(hex: 0xEDD559),
        green: Color(hex: 0x47FF91),
        blue: Color(hex: 0x1A9FFF),
        purple: Color(hex: 0x7759ED),
        magenta: Color(hex: 0xED59B2)
    )

    static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        appearance: .dark,
        background: Color(hex: 0x070034),
        backgroundSecondary: Color(hex: 0x11005B),
        foreground: Color(hex: 0xFAF0FF),
        accent: Color(hex: 0x4FA3F8),
        selection: Color(hex: 0xB1A7FF),
        loader: Color(hex: 0xF4C4FF),
        red: Color(hex: 0xF84141),
        orange: Color(hex: 0xFFC100),
        yellow: Color(hex: 0xFEFF7F),
        green: Color(hex: 0x63BA89),
        blue: Color(hex: 0x6AB7FF),
        purple: Color(hex: 0xA485FF),
        magenta: Color(hex: 0xCF2F98)
    )

    static let sunset = Theme(
        id: "sunset",
        name: "Sunset",
        appearance: .dark,
        background: Color(hex: 0x451A08),
        backgroundSecondary: Color(hex: 0x0A3943),
        foreground: Color(hex: 0xFADDD1),
        accent: Color(hex: 0x4FA3F8),
        selection: Color(hex: 0x7698EF),
        loader: Color(hex: 0x47E0FF),
        red: Color(hex: 0xED5959),
        orange: Color(hex: 0xED8659),
        yellow: Color(hex: 0xEDD559),
        green: Color(hex: 0x59ED7A),
        blue: Color(hex: 0x30BBE8),
        purple: Color(hex: 0x7759ED),
        magenta: Color(hex: 0xED59B2)
    )

    static let all: [Theme] = [.raycastDark, .raycastLight, .sky, .midnight, .sunset]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .raycastDark
    }
}

/// Spacing / radius / typography scale from `css-*.css`.
enum Metric {
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    static let radius4: CGFloat = 4
    static let radius6: CGFloat = 6
    static let radius8: CGFloat = 8
    static let radius10: CGFloat = 10
    static let radius12: CGFloat = 12
    static let radius16: CGFloat = 16
    static let radiusWindow: CGFloat = 26

    static let fontSize11: CGFloat = 11
    static let fontSize13: CGFloat = 13
    static let fontSize16: CGFloat = 16
    static let fontSize18: CGFloat = 18
    static let fontSize24: CGFloat = 24

    static let icon16: CGFloat = 16
    static let icon22: CGFloat = 22
    static let icon32: CGFloat = 32

    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 48
    static let footerHeight: CGFloat = 44
    static let windowWidth: CGFloat = 750
    static let windowMaxListHeight: CGFloat = 440
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
