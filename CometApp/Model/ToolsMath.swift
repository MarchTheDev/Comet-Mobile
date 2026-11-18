//
//  ToolsMath.swift
//  Comet
//
//  Comet's offline tools: a calculator that parses what you type, unit and
//  temperature conversion, dates, percentages and a password generator. All of
//  it is arithmetic on this device.
//

import Foundation

// MARK: - Calculator

enum CalcError: Error, LocalizedError {
    case syntax
    case divisionByZero

    var errorDescription: String? {
        switch self {
        case .syntax: return "That expression doesn't parse."
        case .divisionByZero: return "Can't divide by zero."
        }
    }
}

struct Calculator {
    static func evaluate(_ expression: String) -> Result<Double, CalcError> {
        var parser = Parser(text: expression)
        do {
            let value = try parser.parseExpression()
            parser.skipSpaces()
            guard parser.isAtEnd else { throw CalcError.syntax }
            guard value.isFinite else { throw CalcError.divisionByZero }
            return .success(value)
        } catch let error as CalcError {
            return .failure(error)
        } catch {
            return .failure(.syntax)
        }
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        init(text: String) {
            characters = Array(text.replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: ",", with: "."))
        }

        var isAtEnd: Bool { index >= characters.count }

        mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " { index += 1 }
        }

        mutating func peek() -> Character? {
            skipSpaces()
            return index < characters.count ? characters[index] : nil
        }

        mutating func consume(_ character: Character) -> Bool {
            skipSpaces()
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                if consume("+") { value += try parseTerm() }
                else if consume("-") { value -= try parseTerm() }
                else { break }
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while true {
                if consume("*") { value *= try parseUnary() }
                else if consume("/") {
                    let divisor = try parseUnary()
                    guard divisor != 0 else { throw CalcError.divisionByZero }
                    value /= divisor
                }
                else if consume("%") {
                    let divisor = try parseUnary()
                    guard divisor != 0 else { throw CalcError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: divisor)
                }
                else { break }
            }
            return value
        }

        mutating func parseUnary() throws -> Double {
            if consume("-") { return -(try parseUnary()) }
            if consume("+") { return try parseUnary() }
            return try parsePower()
        }

        mutating func parsePower() throws -> Double {
            let base = try parseAtom()
            if consume("^") {
                let exponent = try parseUnary()
                return pow(base, exponent)
            }
            return base
        }

        mutating func parseAtom() throws -> Double {
            skipSpaces()
            guard index < characters.count else { throw CalcError.syntax }

            if consume("(") {
                let value = try parseExpression()
                guard consume(")") else { throw CalcError.syntax }
                return value
            }

            if characters[index].isLetter {
                var name = ""
                while index < characters.count, characters[index].isLetter {
                    name.append(characters[index])
                    index += 1
                }
                let lower = name.lowercased()
                if lower == "pi" { return Double.pi }
                if lower == "e" { return M_E }
                if let constant = namedConstant(lower) { return constant }
                guard consume("(") else { throw CalcError.syntax }
                let argument = try parseExpression()
                guard consume(")") else { throw CalcError.syntax }
                return try apply(function: lower, to: argument)
            }

            return try parseNumber()
        }

        mutating func parseNumber() throws -> Double {
            skipSpaces()
            var text = ""
            var seenDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    text.append(character)
                    index += 1
                } else if character == "." && !seenDot {
                    seenDot = true
                    text.append(character)
                    index += 1
                } else {
                    break
                }
            }
            guard let value = Double(text) else { throw CalcError.syntax }
            return value
        }

        func namedConstant(_ name: String) -> Double? { nil }

        func apply(function name: String, to value: Double) throws -> Double {
            switch name {
            case "sqrt": return sqrt(max(value, 0))
            case "sin": return sin(value)
            case "cos": return cos(value)
            case "tan": return tan(value)
            case "asin": return asin(value)
            case "acos": return acos(value)
            case "atan": return atan(value)
            case "log": return log10(value)
            case "ln": return log(value)
            case "abs": return abs(value)
            case "round": return value.rounded()
            case "floor": return value.rounded(.down)
            case "ceil": return value.rounded(.up)
            default: throw CalcError.syntax
            }
        }
    }
}

// MARK: - Units

struct UnitOption: Identifiable, Hashable {
    let name: String
    let symbol: String
    let factor: Double
    var id: String { name + symbol }
}

struct UnitCategory: Identifiable, Hashable {
    let name: String
    let symbol: String
    let units: [UnitOption]
    var isTemperature: Bool = false
    var id: String { name }

    static let all: [UnitCategory] = [
        UnitCategory(name: "Length", symbol: "ruler", units: [
            UnitOption(name: "Millimetre", symbol: "mm", factor: 0.001),
            UnitOption(name: "Centimetre", symbol: "cm", factor: 0.01),
            UnitOption(name: "Metre", symbol: "m", factor: 1),
            UnitOption(name: "Kilometre", symbol: "km", factor: 1000),
            UnitOption(name: "Inch", symbol: "in", factor: 0.0254),
            UnitOption(name: "Foot", symbol: "ft", factor: 0.3048),
            UnitOption(name: "Yard", symbol: "yd", factor: 0.9144),
            UnitOption(name: "Mile", symbol: "mi", factor: 1609.344),
            UnitOption(name: "Nautical mile", symbol: "nmi", factor: 1852),
        ]),
        UnitCategory(name: "Mass", symbol: "scalemass", units: [
            UnitOption(name: "Milligram", symbol: "mg", factor: 0.000001),
            UnitOption(name: "Gram", symbol: "g", factor: 0.001),
            UnitOption(name: "Kilogram", symbol: "kg", factor: 1),
            UnitOption(name: "Tonne", symbol: "t", factor: 1000),
            UnitOption(name: "Ounce", symbol: "oz", factor: 0.028349523125),
            UnitOption(name: "Pound", symbol: "lb", factor: 0.45359237),
            UnitOption(name: "Stone", symbol: "st", factor: 6.35029318),
        ]),
        UnitCategory(name: "Temperature", symbol: "thermometer.medium", units: [
            UnitOption(name: "Celsius", symbol: "°C", factor: 1),
            UnitOption(name: "Fahrenheit", symbol: "°F", factor: 1),
            UnitOption(name: "Kelvin", symbol: "K", factor: 1),
        ], isTemperature: true),
        UnitCategory(name: "Volume", symbol: "drop", units: [
            UnitOption(name: "Millilitre", symbol: "ml", factor: 0.001),
            UnitOption(name: "Litre", symbol: "l", factor: 1),
            UnitOption(name: "Teaspoon", symbol: "tsp", factor: 0.00492892),
            UnitOption(name: "Tablespoon", symbol: "tbsp", factor: 0.0147868),
            UnitOption(name: "Cup", symbol: "cup", factor: 0.236588),
            UnitOption(name: "Pint", symbol: "pt", factor: 0.473176),
            UnitOption(name: "Gallon (US)", symbol: "gal", factor: 3.78541),
        ]),
        UnitCategory(name: "Area", symbol: "square.dashed", units: [
            UnitOption(name: "Square metre", symbol: "m²", factor: 1),
            UnitOption(name: "Square foot", symbol: "ft²", factor: 0.092903),
            UnitOption(name: "Hectare", symbol: "ha", factor: 10000),
            UnitOption(name: "Acre", symbol: "ac", factor: 4046.86),
            UnitOption(name: "Square kilometre", symbol: "km²", factor: 1000000),
        ]),
        UnitCategory(name: "Speed", symbol: "speedometer", units: [
            UnitOption(name: "Metre/second", symbol: "m/s", factor: 1),
            UnitOption(name: "Kilometre/hour", symbol: "km/h", factor: 0.277778),
            UnitOption(name: "Mile/hour", symbol: "mph", factor: 0.44704),
            UnitOption(name: "Knot", symbol: "kn", factor: 0.514444),
        ]),
        UnitCategory(name: "Data", symbol: "externaldrive", units: [
            UnitOption(name: "Byte", symbol: "B", factor: 1),
            UnitOption(name: "Kilobyte", symbol: "KB", factor: 1000),
            UnitOption(name: "Kibibyte", symbol: "KiB", factor: 1024),
            UnitOption(name: "Megabyte", symbol: "MB", factor: 1_000_000),
            UnitOption(name: "Mebibyte", symbol: "MiB", factor: 1_048_576),
            UnitOption(name: "Gigabyte", symbol: "GB", factor: 1_000_000_000),
            UnitOption(name: "Gibibyte", symbol: "GiB", factor: 1_073_741_824),
            UnitOption(name: "Terabyte", symbol: "TB", factor: 1_000_000_000_000),
        ]),
        UnitCategory(name: "Time", symbol: "clock", units: [
            UnitOption(name: "Second", symbol: "s", factor: 1),
            UnitOption(name: "Minute", symbol: "min", factor: 60),
            UnitOption(name: "Hour", symbol: "h", factor: 3600),
            UnitOption(name: "Day", symbol: "d", factor: 86400),
            UnitOption(name: "Week", symbol: "wk", factor: 604800),
            UnitOption(name: "Month", symbol: "mo", factor: 2_629_746),
            UnitOption(name: "Year", symbol: "yr", factor: 31_556_952),
        ]),
    ]

    func convert(_ value: Double, from: UnitOption, to: UnitOption) -> Double {
        if isTemperature { return UnitCategory.convertTemperature(value, from: from.symbol, to: to.symbol) }
        return value * from.factor / to.factor
    }

    static func convertTemperature(_ value: Double, from: String, to: String) -> Double {
        var celsius = value
        switch from {
        case "°F": celsius = (value - 32) * 5 / 9
        case "K": celsius = value - 273.15
        default: break
        }
        switch to {
        case "°F": return celsius * 9 / 5 + 32
        case "K": return celsius + 273.15
        default: return celsius
        }
    }
}

// MARK: - Percentages

enum PercentTool {
    /// "What is p% of n?"
    static func percentOf(_ percent: Double, _ value: Double) -> Double { percent / 100 * value }

    /// "n is what percent of total?"
    static func whatPercent(_ value: Double, of total: Double) -> Double? {
        guard total != 0 else { return nil }
        return value / total * 100
    }

    /// Percentage change, with the direction made explicit.
    static func change(from old: Double, to new: Double) -> Double? {
        guard old != 0 else { return nil }
        return (new - old) / abs(old) * 100
    }

    /// Add or remove tax. `rate` is a percentage.
    static func withTax(_ amount: Double, rate: Double) -> (net: Double, tax: Double, gross: Double) {
        let net = amount
        let tax = amount * rate / 100
        return (net, tax, net + tax)
    }

    static func taxFromGross(_ gross: Double, rate: Double) -> (net: Double, tax: Double, gross: Double) {
        let net = gross / (1 + rate / 100)
        return (net, gross - net, gross)
    }
}

// MARK: - Passwords

enum PasswordGenerator {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%*-_+")

    /// Always contains at least one uppercase letter, one lowercase letter, one
    /// digit and one symbol, then is filled from the whole alphabet and
    /// shuffled. A generator that only *usually* includes a class makes a
    /// password that fails the site it is for.
    static func generate(length: Int = 20) -> String {
        let count = max(6, min(length, 128))
        let groups = [
            Array("ABCDEFGHJKLMNPQRSTUVWXYZ"),
            Array("abcdefghijkmnopqrstuvwxyz"),
            Array("23456789"),
            Array("!@#$%*-_+")
        ]
        var characters: [Character] = groups.map { randomCharacter(from: $0) }
        while characters.count < count {
            characters.append(randomCharacter(from: alphabet))
        }
        characters.shuffle()
        return String(characters.prefix(count))
    }

    private static func randomCharacter(from pool: [Character]) -> Character {
        // Rejection sampling avoids modulo bias.
        while true {
            let value = Int(UInt8.random(in: 0...255))
            if value < 256 - (256 % pool.count) {
                return pool[value % pool.count]
            }
        }
    }

    static func strength(of password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        var classes = 0.0
        if password.contains(where: { $0.isLowercase }) { classes += 1 }
        if password.contains(where: { $0.isUppercase }) { classes += 1 }
        if password.contains(where: { $0.isNumber }) { classes += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { classes += 1 }
        let pool = max(classes, 1) * 26
        let entropy = Double(password.count) * log2(pool)
        return min(1, entropy / 100)
    }
}
