import Foundation

/// Display order of result sections in the launcher list.
///
/// Sections are rendered in `rank` order, and rows are ranked by relevance
/// inside a section, so a header never repeats. Extracted from
/// `CommandCenter` so the ordering is covered by tests.
enum ResultSectionOrder {
    static func rank(_ section: String) -> Int {
        switch section {
        case "Calculator": return 0
        case "Web Searches": return 1
        case "Applications": return 2
        case "Rayclone": return 3
        case "Script Commands": return 4
        case "Snippets": return 5
        case "Quicklinks": return 6
        case "Window Management": return 7
        case "System Actions": return 8
        case "Emoji & Symbols": return 9
        // Folders and files sit above clipboard history: a filename match is
        // usually what the user is after, and clipboard text matches are
        // noisier. Folders come first so a folder name that also matches a file
        // name is always listed above that file.
        case "Folders": return 10
        case "Files": return 11
        case "Clipboard History": return 12
        case "Running": return 13
        default: return 15
        }
    }
}
