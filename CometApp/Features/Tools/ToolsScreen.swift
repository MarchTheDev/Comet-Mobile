//
//  ToolsScreen.swift
//  Comet
//
//  The five things a workspace should not need the internet for: a calculator,
//  a converter, dates, percentages, and a password generator.
//

import SwiftUI
import UIKit

struct ToolsScreen: View {
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    private enum Tool: String, CaseIterable, Identifiable {
        case calculator, convert, dates, percent, password
        var id: String { rawValue }
        var title: String {
            switch self {
            case .calculator: return "Calculator"
            case .convert: return "Convert"
            case .dates: return "Dates"
            case .percent: return "Percent"
            case .password: return "Passwords"
            }
        }
        var symbol: String {
            switch self {
            case .calculator: return "plus.forwardslash.minus"
            case .convert: return "arrow.left.arrow.right"
            case .dates: return "calendar.badge.clock"
            case .percent: return "percent"
            case .password: return "key"
            }
        }
    }

    @State private var tool: Tool = .calculator

    @ViewBuilder
    private var toolContent: some View {
        switch tool {
        case .calculator: CalculatorTool()
        case .convert: ConvertTool()
        case .dates: DatesTool()
        case .percent: PercentToolView()
        case .password: PasswordTool()
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ModuleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(eyebrow: "Offline", title: "Tools", subtitle: "Arithmetic on this device", close: close)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Tool.allCases) { option in
                                Chip(title: option.title, icon: option.symbol, selected: tool == option) {
                                    withAnimation(Motion.snappy) { tool = option }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)

                    toolContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Calculator

struct CalculatorTool: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var expression = ""
    @State private var history: [(String, String)] = []
    @State private var error: String?

    private let keys: [[String]] = [
        ["C", "(", ")", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "-"],
        ["1", "2", "3", "+"],
        ["0", ".", "%", "="],
    ]

    private var result: String {
        if let error { return error }
        guard !expression.isEmpty else { return "0" }
        switch Calculator.evaluate(expression) {
        case .success(let value): return Calculator.format(value)
        case .failure: return "—"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .trailing, spacing: 6) {
                Text(expression.isEmpty ? " " : expression)
                    .font(type.mono(16))
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(result)
                    .font(type.display(40))
                    .foregroundStyle(error == nil ? theme.ink : Color.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .frame(minHeight: 120, alignment: .bottom)
            .cometCard(radius: 24, lift: 0.5)

            VStack(spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
            }

            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel(text: "History")
                        Spacer()
                        Button {
                            history.removeAll()
                        } label: {
                            Text("Clear")
                                .font(type.label(11.5, weight: .semibold))
                                .foregroundStyle(theme.tertiary)
                        }
                    }
                    ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                        Button {
                            expression = item.0
                        } label: {
                            HStack {
                                Text(item.0)
                                    .font(type.mono(12))
                                    .foregroundStyle(theme.tertiary)
                                Spacer()
                                Text(item.1)
                                    .font(type.mono(13, weight: .semibold))
                                    .foregroundStyle(theme.ink)
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                    }
                }
                .padding(14)
                .cometCard(radius: 20, lift: 0.35)
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        let isOperator = ["÷", "×", "-", "+", "="].contains(key)
        let isClear = key == "C"
        return Button {
            Haptics.tap()
            press(key)
        } label: {
            Text(key)
                .font(type.label(20, weight: .semibold))
                .foregroundStyle(isOperator ? theme.onAccent : (isClear ? Color.orange : theme.ink))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isOperator ? AnyShapeStyle(theme.accentGradient)
                              : AnyShapeStyle(isClear ? theme.raised : theme.surface))
                )
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: isOperator ? 0 : 1))
        }
        .buttonStyle(PressableStyle(scale: 0.94, haptic: nil))
    }

    private func press(_ key: String) {
        error = nil
        switch key {
        case "C":
            expression = ""
        case "=":
            switch Calculator.evaluate(expression) {
            case .success(let value):
                let formatted = Calculator.format(value)
                history.insert((expression, formatted), at: 0)
                if history.count > 8 { history.removeLast() }
                expression = formatted
                Haptics.success()
            case .failure(let failure):
                error = failure.errorDescription
                Haptics.error()
            }
        case "÷":
            expression += "/"
        case "×":
            expression += "*"
        default:
            expression += key
        }
    }
}

// MARK: - Convert

struct ConvertTool: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var category = UnitCategory.all[0]
    @State private var from = UnitCategory.all[0].units[0]
    @State private var to = UnitCategory.all[0].units[2]
    @State private var input = "1"

    private var output: String {
        guard let value = Double(input.replacingOccurrences(of: ",", with: ".")) else { return "—" }
        let converted = category.convert(value, from: from, to: to)
        return display(converted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(UnitCategory.all) { option in
                        Chip(title: option.name, icon: option.symbol, selected: category == option) {
                            category = option
                            from = option.units[0]
                            to = option.units[min(2, option.units.count - 1)]
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                unitRow(title: "From", unit: $from, value: $input, unitList: category.units)
                HStack {
                    Spacer()
                    Button {
                        Haptics.select()
                        let oldFrom = from
                        from = to
                        to = oldFrom
                        input = output == "—" ? input : output
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(theme.accent.opacity(0.13)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                    Spacer()
                }
                unitRow(title: "To", unit: $to, value: .constant(output), unitList: category.units, readOnly: true)
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)

            Text("Conversions use the SI and imperial factors Comet's desktop tools use.")
                .font(type.prose(11))
                .foregroundStyle(theme.tertiary)
        }
    }

    private func unitRow(title: String, unit: Binding<UnitOption>, value: Binding<String>,
                         unitList: [UnitOption], readOnly: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(type.label(9.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.tertiary)
            HStack(spacing: 10) {
                TextField("0", text: value)
                    .font(type.display(26))
                    .foregroundStyle(theme.ink)
                    .keyboardType(.decimalPad)
                    .disabled(readOnly)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Menu {
                    ForEach(unitList) { option in
                        Button {
                            unit.wrappedValue = option
                        } label: {
                            Text("\(option.name) (\(option.symbol))")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(unit.wrappedValue.symbol)
                            .font(type.label(13, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Capsule().fill(theme.accent.opacity(0.12)))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
        }
    }

    private func display(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e12 { return String(Int64(value)) }
        return String(format: "%.6g", value)
    }
}

// MARK: - Dates

struct DatesTool: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var start = Date()
    @State private var amount = 30.0
    @State private var useWeeks = false
    @State private var second = Date()

    private var shifted: Date {
        Calendar.current.date(byAdding: useWeeks ? .weekOfYear : .day,
                              value: Int(amount),
                              to: start) ?? start
    }

    private var difference: Int {
        Calendar.current.dateComponents([.day], from: start, to: second).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Add or subtract")
                DatePicker("Start", selection: $start, displayedComponents: .date)
                    .font(type.prose(13.5))
                    .tint(theme.accent)
                HStack(spacing: 10) {
                    Slider(value: $amount, in: -365...365, step: 1)
                        .tint(theme.accent)
                    Text("\(Int(amount)) \(useWeeks ? "weeks" : "days")")
                        .font(type.mono(11))
                        .foregroundStyle(theme.tertiary)
                        .frame(width: 74, alignment: .trailing)
                }
                Toggle("Count weeks", isOn: $useWeeks)
                    .font(type.prose(13))
                    .tint(theme.accent)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RESULT")
                            .font(type.label(9.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(theme.tertiary)
                        Text(CalendarMath.polite(shifted))
                            .font(type.title(20))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = CalendarMath.polite(shifted)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(theme.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Days between")
                DatePicker("From", selection: $start, displayedComponents: .date)
                    .font(type.prose(13.5))
                    .tint(theme.accent)
                DatePicker("To", selection: $second, displayedComponents: .date)
                    .font(type.prose(13.5))
                    .tint(theme.accent)
                HStack {
                    Text("\(abs(difference)) days")
                        .font(type.display(26))
                        .foregroundStyle(theme.ink)
                    Spacer()
                    Text(difference >= 0 ? "after" : "before")
                        .font(type.mono(11))
                        .foregroundStyle(theme.tertiary)
                }
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)
        }
    }
}

// MARK: - Percent

struct PercentToolView: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var percent = "20"
    @State private var value = "150"
    @State private var total = "600"
    @State private var part = "75"
    @State private var gross = "120"
    @State private var rate = "22"

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func formatted(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value == value.rounded() ? String(Int64(value)) : String(format: "%.2f", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            card("Percentage of a number") {
                HStack(spacing: 8) {
                    smallField("percent", text: $percent)
                    Text("of").font(type.prose(13)).foregroundStyle(theme.tertiary)
                    smallField("value", text: $value)
                    Text("=").font(type.prose(13)).foregroundStyle(theme.tertiary)
                    Text(formatted(number(percent).flatMap { p in number(value).map { PercentTool.percentOf(p, $0) } }))
                        .font(type.title(18))
                        .foregroundStyle(theme.accent)
                }
            }

            card("One number as a share of another") {
                HStack(spacing: 8) {
                    smallField("part", text: $part)
                    Text("of").font(type.prose(13)).foregroundStyle(theme.tertiary)
                    smallField("total", text: $total)
                    Text("=").font(type.prose(13)).foregroundStyle(theme.tertiary)
                    Text(formatted(number(part).flatMap { p in number(total).flatMap { PercentTool.whatPercent(p, of: $0) } }) + "%")
                        .font(type.title(18))
                        .foregroundStyle(theme.accent)
                }
            }

            card("Tax, VAT, sales tax") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        smallField("gross", text: $gross)
                        smallField("rate %", text: $rate)
                    }
                    let result = number(gross).flatMap { g in number(rate).map { PercentTool.taxFromGross(g, rate: $0) } }
                    HStack {
                        Text("net \(formatted(result?.net))")
                        Text("tax \(formatted(result?.tax))")
                        Spacer()
                        Text("gross \(formatted(result?.gross))")
                    }
                    .font(type.mono(11))
                    .foregroundStyle(theme.secondary)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(type.label(13, weight: .semibold))
                .foregroundStyle(theme.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cometCard(radius: 22, lift: 0.4)
    }

    private func smallField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(type.mono(14))
            .foregroundStyle(theme.ink)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .frame(maxWidth: 92)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.raised))
    }
}

// MARK: - Passwords

struct PasswordTool: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @EnvironmentObject private var model: CometModel

    @State private var length: Double = 24
    @State private var password = PasswordGenerator.generate(length: 24)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(password)
                    .font(type.mono(19, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.raised))

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.raised).frame(height: 6)
                        Capsule()
                            .fill(theme.accentGradient)
                            .frame(width: geometry.size.width * PasswordGenerator.strength(of: password), height: 6)
                    }
                }
                .frame(height: 6)

                HStack(spacing: 8) {
                    Slider(value: $length, in: 8...64, step: 1)
                        .tint(theme.accent)
                    Text("\(Int(length))")
                        .font(type.mono(11.5))
                        .foregroundStyle(theme.tertiary)
                        .frame(width: 22)
                }

                HStack(spacing: 10) {
                    Button {
                        password = PasswordGenerator.generate(length: Int(length))
                        Haptics.success()
                    } label: {
                        Label("Generate", systemImage: "dice")
                            .font(type.label(14, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Capsule().fill(theme.accentGradient))
                    }
                    .buttonStyle(PressableStyle())
                    Button {
                        UIPasteboard.general.string = password
                        model.toast.show("Copied", tone: .success)
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(theme.surface))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)

            Text("Letters and digits that cannot be mistaken for each other (no l, I, 1, O or 0), plus symbols. Generated with the system's secure random source.")
                .font(type.prose(11.5))
                .foregroundStyle(theme.tertiary)
        }
        .onAppear {
            if password.isEmpty { password = PasswordGenerator.generate(length: Int(length)) }
        }
    }
}
