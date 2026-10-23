import XCTest
@testable import Rayclone

@MainActor
final class QuicklinkTests: XCTestCase {
    func testPlaceholderExpansion() throws {
        let url = try XCTUnwrap(QuicklinkStore.expand("https://example.com?q={query}", term: "swift ui", argument: nil))
        XCTAssertEqual(url.absoluteString, "https://example.com?q=swift%20ui")
    }

    func testArgumentWinsOverTerm() throws {
        let url = try XCTUnwrap(QuicklinkStore.expand("https://x.com/{argument}", term: "x", argument: "hello"))
        XCTAssertEqual(url.absoluteString, "https://x.com/hello")
    }

    func testSnippetPlaceholders() {
        let expanded = SnippetStore.expand("date={date} uuid={uuid}")
        XCTAssertFalse(expanded.contains("{date}"))
        XCTAssertFalse(expanded.contains("{uuid}"))
    }
}
