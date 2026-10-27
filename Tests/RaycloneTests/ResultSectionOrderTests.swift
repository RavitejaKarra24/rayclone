import XCTest
@testable import Rayclone

final class ResultSectionOrderTests: XCTestCase {
    func testFilesRankAboveClipboardHistory() {
        XCTAssertLessThan(
            ResultSectionOrder.rank("Files"),
            ResultSectionOrder.rank("Clipboard History"),
            "Files must be listed before clipboard history"
        )
    }

    func testCommandsAndAppsComeFirst() {
        let files = ResultSectionOrder.rank("Files")
        XCTAssertLessThan(ResultSectionOrder.rank("Applications"), files)
        XCTAssertLessThan(ResultSectionOrder.rank("Rayclone"), files)
        XCTAssertLessThan(ResultSectionOrder.rank("Calculator"), files)
    }

    func testFoldersRankAboveFiles() {
        XCTAssertLessThan(
            ResultSectionOrder.rank("Folders"),
            ResultSectionOrder.rank("Files"),
            "Folders must be listed before files"
        )
    }

    func testUnknownSectionsSortAfterKnownOnes() {
        XCTAssertGreaterThan(
            ResultSectionOrder.rank("Something New"),
            ResultSectionOrder.rank("Running")
        )
    }

    func testRanksAreStableAndDistinct() {
        let sections = [
            "Calculator", "Web Searches", "Applications", "Rayclone", "Script Commands",
            "Snippets", "Quicklinks", "Window Management", "System Actions",
            "Emoji & Symbols", "Folders", "Files", "Clipboard History", "Running",
        ]
        let ranks = sections.map(ResultSectionOrder.rank)
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(Set(ranks).count, ranks.count)
    }
}
