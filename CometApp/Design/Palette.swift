//
//  Palette.swift
//  Comet
//
//  The palettes the desktop app paints itself with, carried over value for
//  value: the same canvas, panel, border, text and accent variables under the
//  same names. The mobile app is allowed to lay them out differently, but it
//  should not invent different colours — a workspace opened in both places
//  should look like the same workspace.
//

import SwiftUI

struct Palette: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let isDark: Bool
    let canvas: String
    let panel: String
    let panelSoft: String
    let panelRaised: String
    let border: String
    let borderStrong: String
    let text: String
    let textSecondary: String
    let textMuted: String
    let accent: String
    let accentInk: String
    let accentSoft: String

    // MARK: Colours

    var canvasColor: Color { Color(hex: canvas) }
    var surfaceColor: Color { Color(hex: panel) }
    var softColor: Color { Color(hex: panelSoft) }
    var raisedColor: Color { Color(hex: panelRaised) }
    var borderColor: Color { Color(hex: border) }
    var borderStrongColor: Color { Color(hex: borderStrong) }
    var inkColor: Color { Color(hex: text) }
    var secondaryColor: Color { Color(hex: textSecondary) }
    var tertiaryColor: Color { Color(hex: textMuted) }
    var accentColor: Color { Color(hex: accent) }
    var accentInkColor: Color { Color(hex: accentInk) }
    var accentSoftColor: Color { Color(hex: accentSoft) }

    /// Older call sites talk about a second accent and a glow. The desktop
    /// palette has neither, so both resolve to the accent's own family.
    var accentTwoColor: Color { Color(hex: accentInk) }
    var glowColor: Color { Color(hex: accentSoft) }

    /// White reads on a dark accent; the canvas colour reads on a pale one.
    var onAccentColor: Color {
        let (r, g, b) = Palette.rgb(accent)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.62 ? canvasColor : .white
    }

    static func rgb(_ hex: String) -> (Double, Double, Double) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 8 { value.removeFirst(2) }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return (0, 0, 0) }
        return (Double((number >> 16) & 0xFF) / 255,
                Double((number >> 8) & 0xFF) / 255,
                Double(number & 0xFF) / 255)
    }

    // MARK: The palettes

    static let all: [Palette] = [
        Palette(id: "auto", name: "System", note: "Comet by day, Comet Dark by night", isDark: false,
                canvas: "#f3f6f7", panel: "#ffffff", panelSoft: "#f6f9fa", panelRaised: "#ffffff",
                border: "#e3eaed", borderStrong: "#cfdee4", text: "#304653", textSecondary: "#5f7782",
                textMuted: "#627985", accent: "#567f97", accentInk: "#466e84", accentSoft: "#e9f2f6"),
        Palette(id: "comet", name: "Comet", note: "The desktop default", isDark: false,
                canvas: "#f3f6f7", panel: "#ffffff", panelSoft: "#f6f9fa", panelRaised: "#ffffff",
                border: "#e3eaed", borderStrong: "#cfdee4", text: "#304653", textSecondary: "#5f7782",
                textMuted: "#627985", accent: "#567f97", accentInk: "#466e84", accentSoft: "#e9f2f6"),
        Palette(id: "comet-dark", name: "Comet Dark", note: "The same room at night", isDark: true,
                canvas: "#10161c", panel: "#182129", panelSoft: "#1c2730", panelRaised: "#202c35",
                border: "#2a3842", borderStrong: "#405461", text: "#e2ebee", textSecondary: "#a1b2bc",
                textMuted: "#8a9ea9", accent: "#9cbfcc", accentInk: "#b5d4df", accentSoft: "#253b46"),
        Palette(id: "emerald", name: "Emerald", note: "Green glass", isDark: true,
                canvas: "#0e1b19", panel: "#152723", panelSoft: "#203832", panelRaised: "#1b302b",
                border: "#29483c", borderStrong: "#406a56", text: "#e0f0e8", textSecondary: "#a8c9b8",
                textMuted: "#83a998", accent: "#7acaa0", accentInk: "#b4ebcb", accentSoft: "#294a3a"),
        Palette(id: "rubellite", name: "Rubellite", note: "Rose stone", isDark: true,
                canvas: "#20171c", panel: "#2c1c25", panelSoft: "#402a36", panelRaised: "#35242e",
                border: "#523341", borderStrong: "#795364", text: "#f3e4eb", textSecondary: "#d5b7c5",
                textMuted: "#b796a6", accent: "#e49ab9", accentInk: "#f4c2d5", accentSoft: "#543241"),
        Palette(id: "navy", name: "Navy", note: "Midnight blue", isDark: true,
                canvas: "#101725", panel: "#19263a", panelSoft: "#263955", panelRaised: "#20304a",
                border: "#334a68", borderStrong: "#536c91", text: "#e2ebf9", textSecondary: "#b3c6dd",
                textMuted: "#8da6c6", accent: "#8bb7ec", accentInk: "#c1dcff", accentSoft: "#2a4363"),
        Palette(id: "0807-light", name: "0807 Light", note: "Lavender daylight", isDark: false,
                canvas: "#f6f8fc", panel: "#ffffff", panelSoft: "#f6f8fc", panelRaised: "#ffffff",
                border: "#dee4ef", borderStrong: "#c4cddd", text: "#333f5c", textSecondary: "#5b6882",
                textMuted: "#737e94", accent: "#e25c5c", accentInk: "#b73e42", accentSoft: "#fbe9e9"),
        Palette(id: "0807-dark", name: "0807 Dark", note: "Lavender midnight", isDark: true,
                canvas: "#1d2331", panel: "#262e42", panelSoft: "#303a51", panelRaised: "#262e42",
                border: "#3a4460", borderStrong: "#586580", text: "#e9edf6", textSecondary: "#c0cadc",
                textMuted: "#a7b1c8", accent: "#f0837c", accentInk: "#ffc0b8", accentSoft: "#513b49"),
        Palette(id: "sakura", name: "Sakura", note: "Blossom on paper", isDark: false,
                canvas: "#f4d3e0", panel: "#fdeef4", panelSoft: "#f7c3d6", panelRaised: "#fdeef4",
                border: "#dfa5bf", borderStrong: "#bf829e", text: "#38222e", textSecondary: "#6b4358",
                textMuted: "#89546e", accent: "#cc2f6b", accentInk: "#9d2250", accentSoft: "#f7c3d6"),
        Palette(id: "matcha", name: "Matcha", note: "Tea and paper", isDark: false,
                canvas: "#dce8c2", panel: "#f2f7e2", panelSoft: "#e4efd0", panelRaised: "#f2f7e2",
                border: "#b5cc8e", borderStrong: "#91ae72", text: "#22301b", textSecondary: "#435639",
                textMuted: "#5c754b", accent: "#47701f", accentInk: "#345817", accentSoft: "#cfe0ac"),
        Palette(id: "ember", name: "Ember", note: "Firelight", isDark: true,
                canvas: "#201a17", panel: "#2b231e", panelSoft: "#362a20", panelRaised: "#2b231e",
                border: "#453930", borderStrong: "#70594a", text: "#f2e7dd", textSecondary: "#d8c8bb",
                textMuted: "#bfae9f", accent: "#f08c4a", accentInk: "#ffb37d", accentSoft: "#4d3022"),
        Palette(id: "gothic", name: "Gothic", note: "Ink and plum", isDark: true,
                canvas: "#14101c", panel: "#1d1729", panelSoft: "#2a1f33", panelRaised: "#1d1729",
                border: "#362c47", borderStrong: "#685674", text: "#e6dff2", textSecondary: "#c9bed8",
                textMuted: "#ada0be", accent: "#b34a75", accentInk: "#e896b8", accentSoft: "#46273d"),
        Palette(id: "frog", name: "Frog", note: "Moss and lime", isDark: true,
                canvas: "#111a10", panel: "#1a2618", panelSoft: "#22301c", panelRaised: "#1a2618",
                border: "#2f4229", borderStrong: "#526d49", text: "#eaf3e2", textSecondary: "#c9ddc1",
                textMuted: "#a9c19e", accent: "#72c14e", accentInk: "#a2e582", accentSoft: "#30452b"),
        Palette(id: "nightjar", name: "Nightjar", note: "Blue night", isDark: true,
                canvas: "#07080d", panel: "#10131c", panelSoft: "#0f1a2b", panelRaised: "#10131c",
                border: "#1e2a44", borderStrong: "#3e577a", text: "#e6efff", textSecondary: "#becde5",
                textMuted: "#a0b0cc", accent: "#00a3e8", accentInk: "#6cd8ff", accentSoft: "#123149"),
        Palette(id: "onyx", name: "Onyx", note: "Black and bone", isDark: true,
                canvas: "#050505", panel: "#0e0e0e", panelSoft: "#141414", panelRaised: "#0e0e0e",
                border: "#232323", borderStrong: "#55534c", text: "#e9e6df", textSecondary: "#c9c6bf",
                textMuted: "#aaa79f", accent: "#d8cfbc", accentInk: "#eee6d5", accentSoft: "#38352e"),
    ]

    static func named(_ id: String) -> Palette {
        all.first { $0.id == id } ?? named("comet")
    }

    static let comet = named("comet")
    static let cometDark = named("comet-dark")

    /// Palettes offered in Settings, in the desktop app's order.
    static var selectable: [Palette] { all }
}
