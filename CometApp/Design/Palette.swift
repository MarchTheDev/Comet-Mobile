//
//  Palette.swift
//  Comet
//
//  Comet's palettes, kept as named worlds rather than a light/dark switch: each
//  one carries its own canvas, surface, ink and two accent colours, and the
//  whole app is painted from these eight values. Adding a palette is adding a
//  row here.
//

import SwiftUI

struct Palette: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let isDark: Bool
    let canvas: String
    let surface: String
    let raised: String
    let ink: String
    let inkSecondary: String
    let inkTertiary: String
    let accent: String
    let accentTwo: String
    let border: String
    let glow: String

    var canvasColor: Color { Color(hex: canvas) }
    var surfaceColor: Color { Color(hex: surface) }
    var raisedColor: Color { Color(hex: raised) }
    var inkColor: Color { Color(hex: ink) }
    var secondaryColor: Color { Color(hex: inkSecondary) }
    var tertiaryColor: Color { Color(hex: inkTertiary) }
    var accentColor: Color { Color(hex: accent) }
    var accentTwoColor: Color { Color(hex: accentTwo) }
    var borderColor: Color { Color(hex: border) }
    var glowColor: Color { Color(hex: glow) }

    static let all: [Palette] = [
        Palette(id: "auto", name: "Auto", note: "Daylight by day, Midnight by night", isDark: true,
                canvas: "#070B14", surface: "#0F1626", raised: "#16203A", ink: "#EEF3FF",
                inkSecondary: "#A9B6D4", inkTertiary: "#6C7A99", accent: "#7FA9FF",
                accentTwo: "#B79CFF", border: "#26FFFFFF", glow: "#4B6BFF"),
        Palette(id: "midnight", name: "Midnight", note: "Deep space, cool light", isDark: true,
                canvas: "#070B14", surface: "#0E1524", raised: "#15203A", ink: "#EEF3FF",
                inkSecondary: "#A9B6D4", inkTertiary: "#6C7A99", accent: "#7FA9FF",
                accentTwo: "#B79CFF", border: "#26FFFFFF", glow: "#4B6BFF"),
        Palette(id: "daylight", name: "Daylight", note: "Paper white, steel blue", isDark: false,
                canvas: "#F2F4F9", surface: "#FFFFFF", raised: "#FFFFFF", ink: "#101827",
                inkSecondary: "#58657C", inkTertiary: "#8A94A6", accent: "#3D6FE0",
                accentTwo: "#7D5CF0", border: "#14101827", glow: "#8FB4FF"),
        Palette(id: "aurora", name: "Aurora", note: "Green sky over black ice", isDark: true,
                canvas: "#04120F", surface: "#0A201C", raised: "#0F2A25", ink: "#E9FFF8",
                inkSecondary: "#9BC9BB", inkTertiary: "#5E8478", accent: "#52E3B7",
                accentTwo: "#7C9CFF", border: "#26FFFFFF", glow: "#14C8A0"),
        Palette(id: "ember", name: "Ember", note: "Warm charcoal, firelight", isDark: true,
                canvas: "#140A07", surface: "#21120C", raised: "#2C1912", ink: "#FFF1E9",
                inkSecondary: "#D3A996", inkTertiary: "#8C6758", accent: "#FF8A5B",
                accentTwo: "#FFC46B", border: "#26FFFFFF", glow: "#FF6B35"),
        Palette(id: "sakura", name: "Sakura", note: "Blossom on cream", isDark: false,
                canvas: "#FBF3F6", surface: "#FFFFFF", raised: "#FFFFFF", ink: "#2B1720",
                inkSecondary: "#7C5B69", inkTertiary: "#A98D9A", accent: "#D9599B",
                accentTwo: "#9A6BE0", border: "#142B1720", glow: "#FFB3D2"),
        Palette(id: "matcha", name: "Matcha", note: "Soft green, quiet light", isDark: false,
                canvas: "#F3F7EE", surface: "#FFFFFF", raised: "#FFFFFF", ink: "#16210F",
                inkSecondary: "#566647", inkTertiary: "#85937A", accent: "#3F7D4C",
                accentTwo: "#7FA83C", border: "#1416210F", glow: "#A8D672"),
        Palette(id: "navy", name: "Navy", note: "Harbour at dusk", isDark: true,
                canvas: "#060E1C", surface: "#0C1930", raised: "#122343", ink: "#E8F0FF",
                inkSecondary: "#9DB2D6", inkTertiary: "#64789B", accent: "#6C9BD9",
                accentTwo: "#8FD1E8", border: "#26FFFFFF", glow: "#2E5FA3"),
        Palette(id: "emerald", name: "Emerald", note: "Glass and mineral", isDark: true,
                canvas: "#04120C", surface: "#0A2017", raised: "#0F2C20", ink: "#E7FFF2",
                inkSecondary: "#94C9AE", inkTertiary: "#5E8B74", accent: "#34D399",
                accentTwo: "#A3E635", border: "#26FFFFFF", glow: "#10B981"),
        Palette(id: "rubellite", name: "Rubellite", note: "Crimson and copper", isDark: true,
                canvas: "#150608", surface: "#220B0F", raised: "#2E1218", ink: "#FFECEF",
                inkSecondary: "#D49AA2", inkTertiary: "#8E5C64", accent: "#F87171",
                accentTwo: "#FB923C", border: "#26FFFFFF", glow: "#DC2626"),
        Palette(id: "gothic", name: "Gothic", note: "Ink, stone, silence", isDark: true,
                canvas: "#0A0A0B", surface: "#141416", raised: "#1C1C1F", ink: "#F2F2F4",
                inkSecondary: "#A8A8B0", inkTertiary: "#6E6E78", accent: "#C9C9D4",
                accentTwo: "#8E8EA0", border: "#26FFFFFF", glow: "#4B4B57"),
        Palette(id: "frog", name: "Frog", note: "Moss and lime", isDark: true,
                canvas: "#0A1206", surface: "#131F0C", raised: "#1A2911", ink: "#F0FFE3",
                inkSecondary: "#B4CE96", inkTertiary: "#7C9964", accent: "#A3E635",
                accentTwo: "#4ADE80", border: "#26FFFFFF", glow: "#65A30D"),
        Palette(id: "nightjar", name: "Nightjar", note: "Lamplight on paper", isDark: true,
                canvas: "#12100D", surface: "#1C1814", raised: "#26201A", ink: "#FAF3E9",
                inkSecondary: "#C7B7A0", inkTertiary: "#8E7E68", accent: "#D6B27A",
                accentTwo: "#C98BA2", border: "#26FFFFFF", glow: "#8A6A3C"),
        Palette(id: "onyx", name: "Onyx", note: "Black, for OLED", isDark: true,
                canvas: "#000000", surface: "#0B0B0C", raised: "#141416", ink: "#FFFFFF",
                inkSecondary: "#A1A1A6", inkTertiary: "#66666C", accent: "#E7E7EA",
                accentTwo: "#9CA3AF", border: "#24FFFFFF", glow: "#3F3F46"),
        Palette(id: "0807-light", name: "0807 Light", note: "Lavender daylight", isDark: false,
                canvas: "#F6F4FB", surface: "#FFFFFF", raised: "#FFFFFF", ink: "#1A1626",
                inkSecondary: "#5F5876", inkTertiary: "#948EAA", accent: "#7257D6",
                accentTwo: "#4FA9E8", border: "#141A1626", glow: "#B7A6FF"),
        Palette(id: "0807-dark", name: "0807 Dark", note: "Lavender midnight", isDark: true,
                canvas: "#0B0916", surface: "#141026", raised: "#1C1733", ink: "#F1EDFF",
                inkSecondary: "#B0A6D6", inkTertiary: "#7A7099", accent: "#A78BFA",
                accentTwo: "#67E8F9", border: "#26FFFFFF", glow: "#7C5CFF"),
    ]

    static func named(_ id: String) -> Palette {
        all.first { $0.id == id } ?? all[1]
    }

    static let daylight = named("daylight")
    static let midnight = named("midnight")
}
