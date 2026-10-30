import XCTest
@testable import Rayclone

final class FileProviderHomeFolderTests: XCTestCase {
    func testNameContainsMirrorsSpotlightSubstringMatch() {
        XCTAssertTrue(FileResultRanking.nameContains("Downloads", term: "downloads"))
        XCTAssertTrue(FileResultRanking.nameContains("Downloads", term: "Load"))
        XCTAssertTrue(FileResultRanking.nameContains("Résumé", term: "resume"))
        XCTAssertFalse(FileResultRanking.nameContains("Documents", term: "downloads"))
    }

    /// Spotlight hides `~/Downloads` from an app without TCC access to it, so
    /// the folder has to come from a direct listing of the home directory.
    @MainActor
    func testHomeListingFindsProtectedFolders() throws {
        let home = AppPaths.home
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: home.appendingPathComponent("Downloads").path),
            "no ~/Downloads on this machine"
        )

        let matches = FileProvider.matchingSubfolders(
            of: home,
            term: "downloads",
            showHidden: false,
            excluding: []
        )

        XCTAssertTrue(
            matches.contains { $0.lastPathComponent == "Downloads" },
            "expected ~/Downloads in \(matches.map(\.lastPathComponent))"
        )
    }

    @MainActor
    func testHomeListingSkipsFoldersSpotlightAlreadyReported() {
        let home = AppPaths.home
        let downloads = home.appendingPathComponent("Downloads")
        guard FileManager.default.fileExists(atPath: downloads.path) else { return }

        let matches = FileProvider.matchingSubfolders(
            of: home,
            term: "downloads",
            showHidden: false,
            excluding: [downloads.path]
        )

        XCTAssertFalse(matches.contains { $0.path == downloads.path })
    }

    @MainActor
    func testHomeListingReturnsFoldersOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayclone-subfolders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("downloads-folder"),
            withIntermediateDirectories: true
        )
        try "x".write(
            to: directory.appendingPathComponent("downloads-file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let matches = FileProvider.matchingSubfolders(
            of: directory,
            term: "downloads",
            showHidden: false,
            excluding: []
        )

        XCTAssertEqual(matches.map(\.lastPathComponent), ["downloads-folder"])
    }
}
