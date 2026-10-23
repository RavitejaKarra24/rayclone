import Foundation

enum AppPaths {
    static let bundleID = "com.rayclone.macos"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var scriptCommandsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("script-commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var hotkeysFile: URL { supportDirectory.appendingPathComponent("hotkeys.json") }

    /// Root of the user's home, used by file search scopes.
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
}

/// Small JSON-backed store used by every feature that persists user data.
enum JSONStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadArray<T: Decodable>(_ type: T.Type, named name: String) -> [T] {
        load([T].self, from: AppPaths.supportDirectory.appendingPathComponent(name)) ?? []
    }

    static func saveArray<T: Encodable>(_ value: [T], named name: String) {
        save(value, to: AppPaths.supportDirectory.appendingPathComponent(name))
    }
}
