import Foundation

/// Evaluates the arithmetic the deterministic provider can help with.
///
/// Supports `+ - * / ^`, parentheses, unary signs, decimals and postfix `%`.
/// Anything else returns nil instead of guessing.
enum ArithmeticEvaluator {
    private enum Token: Equatable {
        case number(Double)
        case plus
        case minus
        case times
        case divide
        case power
        case percent
        case leftParen
        case rightParen
    }

    /// The value of `expression`, or nil when it is not plain arithmetic.
    static func evaluate(_ expression: String) -> Double? {
        var tokens: [Token] = []
        var index = expression.startIndex

        while index < expression.endIndex {
            let character = expression[index]
            if character.isWhitespace {
                index = expression.index(after: index)
                continue
            }
            if character.isNumber || character == "." {
                var literal = String(character)
                var next = expression.index(after: index)
                while next < expression.endIndex, expression[next].isNumber || expression[next] == "." {
                    literal.append(expression[next])
                    next = expression.index(after: next)
                }
                guard let value = Double(literal), value.isFinite else { return nil }
                tokens.append(.number(value))
                index = next
                continue
            }

            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*", "×", "·": tokens.append(.times)
            case "/", "÷": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "%": tokens.append(.percent)
            case "(": tokens.append(.leftParen)
            case ")": tokens.append(.rightParen)
            default: return nil
            }
            index = expression.index(after: index)
        }

        var parser = Parser(tokens: tokens)
        guard let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// A compact decimal string with trailing zeros removed.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.6f", value)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private struct Parser {
        let tokens: [Token]
        var position = 0

        var isAtEnd: Bool {
            position == tokens.count
        }

        private func peek() -> Token? {
            position < tokens.count ? tokens[position] : nil
        }

        private mutating func advance() {
            position += 1
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let token = peek() {
                guard token == .plus || token == .minus else { break }
                advance()
                guard let right = term() else { return nil }
                value = token == .plus ? value + right : value - right
            }
            return value
        }

        private mutating func term() -> Double? {
            guard var value = unary() else { return nil }
            while let token = peek() {
                guard token == .times || token == .divide else { break }
                advance()
                guard let right = unary() else { return nil }
                if token == .divide {
                    guard right != 0 else { return nil }
                    value /= right
                } else {
                    value *= right
                }
            }
            return value
        }

        private mutating func unary() -> Double? {
            switch peek() {
            case .plus:
                advance()
                return unary()
            case .minus:
                advance()
                guard let value = unary() else { return nil }
                return -value
            default:
                guard var value = power() else { return nil }
                while peek() == .percent {
                    advance()
                    value /= 100
                }
                return value
            }
        }

        private mutating func power() -> Double? {
            guard let base = primary() else { return nil }
            guard peek() == .power else { return base }
            advance()
            guard let exponent = unary() else { return nil }
            let value = pow(base, exponent)
            return value.isFinite ? value : nil
        }

        private mutating func primary() -> Double? {
            guard let token = peek() else { return nil }
            switch token {
            case .number(let value):
                advance()
                return value
            case .leftParen:
                advance()
                guard let value = expression(), peek() == .rightParen else { return nil }
                advance()
                return value
            default:
                return nil
            }
        }
    }
}
