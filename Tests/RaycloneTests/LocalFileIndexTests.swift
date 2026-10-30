import XCTest
@testable import Rayclone

final class LocalFileIndexTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayclone-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested/deeper", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "a".write(to: root.appendingPathComponent("Report.pdf"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("nested/report-draft.pages"), atomically: true, encoding: .utf8)
        try "c".write(to: root.appendingPathComponent("nested/deeper/report-final.txt"), atomically: true, encoding: .utf8)
        try "d".write(to: root.appendingPathComponent(".hidden-report"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sample.app/Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "e".write(to: root.appendingPathComponent("Sample.app/Contents/inner-report.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testScanWalksNestedFoldersAndRecordsDirectories() {
        let entries = LocalFileIndex.scan(roots: [root], showHidden: false).entries
        let names = Set(entries.map(\.name))

        XCTAssertTrue(names.contains("Report.pdf"))
        XCTAssertTrue(names.contains("report-draft.pages"))
        XCTAssertTrue(names.contains("report-final.txt"))
        XCTAssertTrue(names.contains("Sample.app"))
        XCTAssertTrue(entries.first { $0.name == "nested" }?.isDirectory == true)
    }

    func testScanTreatsPackagesAsOpenableFilesAndDoesNotDescend() {
        let entries = LocalFileIndex.scan(roots: [root], showHidden: false).entries

        XCTAssertEqual(entries.first { $0.name == "Sample.app" }?.isDirectory, false)
        XCTAssertFalse(entries.contains { $0.name == "inner-report.txt" })
    }

    func testScanSkipsHiddenEntriesUnlessAsked() {
        XCTAssertFalse(LocalFileIndex.scan(roots: [root], showHidden: false).entries.contains { $0.name == ".hidden-report" })
        XCTAssertTrue(LocalFileIndex.scan(roots: [root], showHidden: true).entries.contains { $0.name == ".hidden-report" })
    }

    func testScanRespectsTheEntryCeiling() {
        let result = LocalFileIndex.scan(roots: [root], showHidden: false, limit: 2)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertFalse(result.isComplete, "a capped scan must not be trusted as complete")
    }

    func testCompleteScanOfASmallFolderIsMarkedComplete() {
        XCTAssertTrue(LocalFileIndex.scan(roots: [root], showHidden: false).isComplete)
    }

    func testScanIgnoresMissingRoots() {
        XCTAssertTrue(
            LocalFileIndex.scan(roots: [root.appendingPathComponent("nope")], showHidden: false).entries.isEmpty
        )
    }

    func testFilteredIsCaseInsensitiveAndHonoursExclusions() throws {
        let entries = LocalFileIndex.scan(roots: [root], showHidden: false).entries
        // `TMPDIR` lives under the `/var` symlink, so the enumerated paths are
        // not spelled the way `root` is; take the exclusion from an entry.
        let excluded = try XCTUnwrap(entries.first { $0.name == "Report.pdf" }?.path)

        let matches = LocalFileIndex.filtered(entries, term: "REPORT", excluding: [excluded])

        XCTAssertEqual(Set(matches.map(\.name)), ["report-draft.pages", "report-final.txt"])
    }

    func testOneCharacterTermsAreIgnored() {
        let entries = LocalFileIndex.scan(roots: [root], showHidden: false).entries
        XCTAssertTrue(LocalFileIndex.filtered(entries, term: "r", excluding: []).isEmpty)
    }
}
