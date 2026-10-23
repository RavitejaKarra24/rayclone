import Foundation

/// Resolves bundled data files.
///
/// Order matters: the packaged app is the real target, so its resource bundle is
/// checked first. `Bundle.module` is only a development fallback — relying on it
/// alone can work on the machine that built the app (because SwiftPM bakes in a
/// build-directory path) and fail for the installed copy.
enum AppResources {
    private static let resourceBundleName = "Rayclone_Rayclone"

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        let fileName = "\(name).\(ext)"

        if let resourceURL = Bundle.main.resourceURL {
            // 1. Standard bundle inside the app: Resources/<name>.bundle/Contents/Resources/
            let bundleURL = resourceURL.appendingPathComponent("\(resourceBundleName).bundle")
            if let bundle = Bundle(url: bundleURL), let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
            // 2. Bundle copied flat into Resources/ (older packaging layout).
            let flatBundleFile = bundleURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: flatBundleFile.path) {
                return flatBundleFile
            }
            // 3. Directly in Resources/ (see `Scripts/build-app.sh`).
            let direct = resourceURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
        }

        // 4. Development: `swift run` / `swift test`.
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
