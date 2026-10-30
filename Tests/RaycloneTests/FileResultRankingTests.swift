import XCTest
@testable import Rayclone

final class FileResultRankingTests: XCTestCase {
    private func candidate(_ path: String, isDirectory: Bool, order: Int = 0) -> FileCandidate {
        let url = URL(fileURLWithPath: path)
        return FileCandidate(
            item: SearchItem(
                id: "file:\(path)",
                title: url.lastPathComponent,
                subtitle: url.deletingLastPathComponent().path,
                section: isDirectory ? "Folders" : "Files"
            ),
            isDirectory: isDirectory,
            pathDepth: path.reduce(0) { $1 == "/" ? $0 + 1 : $0 },
            evidenceOrder: order
        )
    }

    func testExactNameBeatsPrefixWhichBeatsInteriorMatch() {
        let exact = FileResultRanking.nameScore("dock", term: "dock")
        let prefix = FileResultRanking.nameScore("docker", term: "dock")
        let interior = FileResultRanking.nameScore("x-dock", term: "dock")
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, interior)
    }

    func testShallowestMatchWinsWhenNamesAreIdentical() {
        let shallow = candidate("/Users/me/dock", isDirectory: true, order: 5)
        let deep = candidate("/Users/me/src/node_modules/pkg/dock", isDirectory: true, order: 0)
        let ordered = FileResultRanking.pool([deep, shallow], term: "dock", limit: 2)
        XCTAssertEqual(ordered.map(\.item.id), [shallow.item.id, deep.item.id])
    }

    func testFoldersAreListedBeforeFilesWithTheSameName() {
        let folder = candidate("/Users/me/dock", isDirectory: true)
        let file = candidate("/Users/me/Projects/dock", isDirectory: false)
        let items = FileResultRanking.ordered(folders: [folder], files: [file], term: "dock", limit: 10)
        XCTAssertEqual(items.map(\.section), ["Folders", "Files"])
        XCTAssertLessThan(
            ResultSectionOrder.rank("Folders"),
            ResultSectionOrder.rank("Files"),
            "The Folders section must render above Files"
        )
    }

    func testDirectlyListedFolderStillBeatsADeeperSpotlightHit() {
        // `~/Downloads` comes from a direct listing (high evidence order) when
        // Spotlight hides it; the shallower path must still win the tie.
        let homeFolder = candidate("/Users/me/Downloads", isDirectory: true, order: 1200)
        let nested = candidate("/Users/me/dock/downloads", isDirectory: true, order: 0)
        let ordered = FileResultRanking.pool([nested, homeFolder], term: "downloads", limit: 2)
        XCTAssertEqual(ordered.map(\.item.id), [homeFolder.item.id, nested.item.id])
    }

    func testLimitAppliesToEachKind() {
        let folders = (0..<10).map { candidate("/Users/me/f\($0)dock", isDirectory: true, order: $0) }
        let files = (0..<10).map { candidate("/Users/me/f\($0)dock.txt", isDirectory: false, order: $0) }
        let items = FileResultRanking.ordered(folders: folders, files: files, term: "dock", limit: 3)
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items.filter { $0.section == "Folders" }.count, 3)
        XCTAssertEqual(items.filter { $0.section == "Files" }.count, 3)
    }

    func testFolderSurvivesWhenManyFilesMatch() {
        let folder = candidate("/Users/me/dock", isDirectory: true, order: 61)
        let files = (0..<50).map { candidate("/Users/me/Downloads/dock-file-\($0).txt", isDirectory: false, order: $0) }
        let items = FileResultRanking.ordered(folders: [folder], files: files, term: "dock", limit: 12)
        XCTAssertEqual(items.first?.id, folder.item.id)
    }
}
