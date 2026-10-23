import Foundation

/// Recursive-descent expression evaluator for the calculator command.
/// Supports arithmetic, exponentiation, common functions, constants, percentage
/// suffixes, and base prefixes (0x / 0b).
enum ExpressionError: Error, LocalizedError {
    case unexpectedCharacter(Character)
    case unexpectedEnd
    case divisionByZero
    case unknownIdentifier(String)
    case badFunction(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedCharacter(let c): return "Unexpected character '\(c)'"
        case .unexpectedEnd: return "Unexpected end of expression"
        case .divisionByZero: return "Division by zero"
        case .unknownIdentifier(let name): return "Unknown identifier '\(name)'"
        case .badFunction(let name): return "Unknown function '\(name)'"
        }
    }
}

struct ExpressionEvaluator {
    private var tokens: [Token] = []
    private var index = 0
    private var source: [Character] = []
    private var position = 0

    enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case op(Character)
        case leftParen
        case rightParen
        case comma
    }

    func evaluate(_ expression: String) throws -> Double {
        var evaluator = self
        evaluator.tokens = try evaluator.tokenize(expression)
        evaluator.index = 0
        guard !evaluator.tokens.isEmpty else { throw ExpressionError.unexpectedEnd }
        let value = try evaluator.parseExpression()
        guard evaluator.index == evaluator.tokens.count else {
            throw ExpressionError.unexpectedEnd
        }
        return value
    }

    // MARK: Lexer

    private mutating func tokenize(_ input: String) throws -> [Token] {
        source = Array(input.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/"))
        position = 0
        var result: [Token] = []

        while position < source.count {
            let c = source[position]
            if c.isWhitespace { position += 1; continue }

            if c.isNumber || (c == "." && position + 1 < source.count && source[position + 1].isNumber) {
                result.append(.number(try lexNumber()))
                continue
            }

            if c.isLetter || c == "_" {
                var name = ""
                while position < source.count, source[position].isLetter || source[position].isNumber || source[position] == "_" {
                    name.append(source[position])
                    position += 1
                }
                result.append(.identifier(name.lowercased()))
                continue
            }

            switch c {
            case "+", "-", "*", "/", "^", "%", "!":
                result.append(.op(c))
                position += 1
            case "(":
                result.append(.leftParen)
                position += 1
            case ")":
                result.append(.rightParen)
                position += 1
            case ",":
                result.append(.comma)
                position += 1
            default:
                throw ExpressionError.unexpectedCharacter(c)
            }
        }
        return result
    }

    private mutating func lexNumber() throws -> Double {
        var text = ""
        // Base prefixes.
        if source[position] == "0", position + 1 < source.count,
           source[position + 1] == "x" || source[position + 1] == "X" {
            position += 2
            var hex = ""
            while position < source.count, source[position].isHexDigit {
                hex.append(source[position])
                position += 1
            }
            return Double(Int(hex, radix: 16) ?? 0)
        }
        if source[position] == "0", position + 1 < source.count,
           source[position + 1] == "b" || source[position + 1] == "B" {
            position += 2
            var binary = ""
            while position < source.count, source[position] == "0" || source[position] == "1" {
                binary.append(source[position])
                position += 1
            }
            return Double(Int(binary, radix: 2) ?? 0)
        }

        while position < source.count, source[position].isNumber || source[position] == "." {
            text.append(source[position])
            position += 1
        }
        // Scientific notation: 1e-3
        if position < source.count, source[position] == "e" || source[position] == "E" {
            var exponent = String(source[position])
            var lookahead = position + 1
            if lookahead < source.count, source[lookahead] == "+" || source[lookahead] == "-" {
                exponent.append(source[lookahead])
                lookahead += 1
            }
            var digits = ""
            while lookahead < source.count, source[lookahead].isNumber {
                digits.append(source[lookahead])
                lookahead += 1
            }
            if !digits.isEmpty {
                text += exponent + digits
                position = lookahead
            }
        }
        guard let value = Double(text) else { throw ExpressionError.unexpectedEnd }
        return value
    }

    // MARK: Parser

    private mutating func parseExpression() throws -> Double {
        try parseAdditive()
    }

    private mutating func parseAdditive() throws -> Double {
        var value = try parseMultiplicative()
        while let token = peek(), case .op(let c) = token, c == "+" || c == "-" {
            index += 1
            let rhs = try parseMultiplicative()
            value = c == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func parseMultiplicative() throws -> Double {
        var value = try parseUnary()
        while let token = peek(), case .op(let c) = token, c == "*" || c == "/" || c == "%" {
            index += 1
            let rhs = try parseUnary()
            if c == "*" {
                value *= rhs
            } else if c == "/" {
                if rhs == 0 { throw ExpressionError.divisionByZero }
                value /= rhs
            } else {
                if rhs == 0 { throw ExpressionError.divisionByZero }
                value = value.truncatingRemainder(dividingBy: rhs)
            }
        }
        return value
    }

    private mutating func parseUnary() throws -> Double {
        if let token = peek(), case .op(let c) = token, c == "-" || c == "+" {
            index += 1
            let value = try parseUnary()
            return c == "-" ? -value : value
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Double {
        let base = try parsePostfix()
        if let token = peek(), case .op(let c) = token, c == "^" {
            index += 1
            let exponent = try parseUnary()
            return pow(base, exponent)
        }
        return base
    }

    private mutating func parsePostfix() throws -> Double {
        var value = try parsePrimary()
        // Trailing "!" for factorial and "%" for percent-of-previous-value.
        while let token = peek(), case .op(let c) = token {
            if c == "!" {
                index += 1
                value = try factorial(value)
            } else if c == "%" {
                index += 1
                value = value / 100
            } else {
                break
            }
        }
        return value
    }

    private func factorial(_ value: Double) throws -> Double {
        guard value >= 0, value <= 170, value == value.rounded() else { return value }
        return (1...max(Int(value), 1)).reduce(1.0) { $0 * Double($1) }
    }

    private mutating func parsePrimary() throws -> Double {
        guard let token = peek() else { throw ExpressionError.unexpectedEnd }

        switch token {
        case .number(let value):
            index += 1
            return value

        case .leftParen:
            index += 1
            let value = try parseExpression()
            guard let next = peek(), next == .rightParen else { throw ExpressionError.unexpectedEnd }
            index += 1
            return value

        case .identifier(let name):
            index += 1
            if let next = peek(), next == .leftParen {
                index += 1
                var arguments: [Double] = []
                if let afterParen = peek(), afterParen != .rightParen {
                    while true {
                        arguments.append(try parseExpression())
                        if let comma = peek(), comma == .comma {
                            index += 1
                            continue
                        }
                        break
                    }
                }
                guard let closing = peek(), closing == .rightParen else { throw ExpressionError.unexpectedEnd }
                index += 1
                return try applyFunction(name, arguments)
            }
            switch name {
            case "pi", "π": return Double.pi
            case "e": return M_E
            case "tau": return Double.pi * 2
            case "true": return 1
            case "false": return 0
            default: throw ExpressionError.unknownIdentifier(name)
            }

        case .op(let c) where c == "-":
            index += 1
            return -(try parsePrimary())

        default:
            throw ExpressionError.unexpectedEnd
        }
    }

    private func applyFunction(_ name: String, _ args: [Double]) throws -> Double {
        func unary(_ transform: (Double) -> Double) throws -> Double {
            guard args.count == 1 else { throw ExpressionError.badFunction(name) }
            return transform(args[0])
        }
        switch name {
        case "sqrt": return try unary { $0.squareRoot() }
        case "cbrt": return try unary { cbrt($0) }
        case "abs": return try unary { abs($0) }
        case "sin": return try unary { sin($0) }
        case "cos": return try unary { cos($0) }
        case "tan": return try unary { tan($0) }
        case "asin": return try unary { asin($0) }
        case "acos": return try unary { acos($0) }
        case "atan": return try unary { atan($0) }
        case "log": return try unary { log10($0) }
        case "ln": return try unary { Foundation.log($0) }
        case "log2": return try unary { Foundation.log2($0) }
        case "round": return try unary { $0.rounded() }
        case "floor": return try unary { $0.rounded(.down) }
        case "ceil": return try unary { $0.rounded(.up) }
        case "sign": return try unary { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) }
        case "exp": return try unary { Foundation.exp($0) }
        case "min": return args.min() ?? 0
        case "max": return args.max() ?? 0
        case "pow":
            guard args.count == 2 else { throw ExpressionError.badFunction(name) }
            return pow(args[0], args[1])
        case "hypot":
            guard args.count == 2 else { throw ExpressionError.badFunction(name) }
            return hypot(args[0], args[1])
        default:
            throw ExpressionError.badFunction(name)
        }
    }

    private func peek() -> Token? {
        index < tokens.count ? tokens[index] : nil
    }
}

/// Formats calculator output the way the launcher shows it: grouped thousands,
/// no trailing `.0`, and a compact scientific fallback for extremes.
enum NumberFormatterEngine {
    static func format(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value > 0 ? "∞" : "-∞" }
        if value == value.rounded(), abs(value) < 1e15 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        if abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) {
            return String(format: "%.6g", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func alternateRepresentations(_ value: Double) -> [(String, String)] {
        var rows: [(String, String)] = []
        if value == value.rounded(), abs(value) < 9e15 {
            let intValue = Int(value)
            rows.append(("Hex", "0x" + String(intValue, radix: 16, uppercase: true)))
            rows.append(("Binary", "0b" + String(intValue, radix: 2)))
            rows.append(("Octal", "0o" + String(intValue, radix: 8)))
        }
        if abs(value) < 9e15 {
            let days = value / 86_400
            if abs(days) >= 1 {
                rows.append(("Days", String(format: "%.4f", days)))
            }
            let hours = value / 3600
            if abs(hours) >= 1 {
                rows.append(("Hours", String(format: "%.3f", hours)))
            }
        }
        return rows
    }
}
