import XCTest
@testable import Rayclone

final class ExpressionTests: XCTestCase {
    func testArithmeticRespectsPrecedence() throws {
        XCTAssertEqual(try ExpressionEvaluator().evaluate("2+2*3"), 8)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("(2+2)*3"), 12)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("10/4"), 2.5)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("-3+1"), -2)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("2^10"), 1024)
    }

    func testFunctionsAndConstants() throws {
        XCTAssertEqual(try ExpressionEvaluator().evaluate("sqrt(81)"), 9)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("round(2.6)"), 3)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("max(1, 5, 3)"), 5)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("pi"), Double.pi, accuracy: 1e-12)
    }

    func testPercentAndFactorialPostfix() throws {
        XCTAssertEqual(try ExpressionEvaluator().evaluate("50%"), 0.5)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("5!"), 120)
    }

    func testBases() throws {
        XCTAssertEqual(try ExpressionEvaluator().evaluate("0xFF"), 255)
        XCTAssertEqual(try ExpressionEvaluator().evaluate("0b1011"), 11)
    }

    func testDivisionByZeroThrows() {
        XCTAssertThrowsError(try ExpressionEvaluator().evaluate("1/0"))
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try ExpressionEvaluator().evaluate("2+"))
        XCTAssertThrowsError(try ExpressionEvaluator().evaluate("hello"))
    }

    func testFormatting() {
        XCTAssertEqual(NumberFormatterEngine.format(1000), "1,000")
        XCTAssertEqual(NumberFormatterEngine.format(2.5), "2.5")
    }
}
