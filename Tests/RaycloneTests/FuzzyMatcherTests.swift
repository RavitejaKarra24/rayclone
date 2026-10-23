import XCTest
@testable import Rayclone

final class FuzzyMatcherTests: XCTestCase {
    func testPrefixBeatsInteriorSubstring() throws {
        let prefix = try XCTUnwrap(FuzzyMatcher.score("saf", in: "Safari"))
        let interior = try XCTUnwrap(FuzzyMatcher.score("fari", in: "Safari"))
        XCTAssertGreaterThan(prefix, interior)
    }

    func testSubsequenceMatch() throws {
        XCTAssertNotNil(FuzzyMatcher.score("clp", in: "Clipboard History"))
        XCTAssertNil(FuzzyMatcher.score("zzz", in: "Clipboard History"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.score("SAFARI", in: "safari"))
    }

    func testShorterCandidatesWinOnTies() throws {
        let short = try XCTUnwrap(FuzzyMatcher.score("note", in: "Notes"))
        let long = try XCTUnwrap(FuzzyMatcher.score("note", in: "Notes Preferences Panel"))
        XCTAssertGreaterThan(short, long)
    }

    func testMatchedIndicesAreReported() throws {
        let result = try XCTUnwrap(FuzzyMatcher.match("saf", in: "Safari"))
        XCTAssertEqual(result.matchedIndices, [0, 1, 2])
    }

    func testQueryParsingSplitsArgument() {
        let parsed = ParsedQuery.parse("google swift concurrency")
        XCTAssertEqual(parsed.term, "google")
        XCTAssertEqual(parsed.argument, "swift concurrency")
        XCTAssertNil(ParsedQuery.parse("google").argument)
    }
}
