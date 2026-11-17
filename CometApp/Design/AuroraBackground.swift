//
//  AuroraBackground.swift
//  Comet
//
//  The desktop app's workspace is a flat canvas with a very quiet wash at the
//  top. This is that surface; the name is kept because the shell still asks for
//  a background, not because anything glows.
//

import SwiftUI

struct AuroraBackground: View {
    @Environment(\.comet) private var theme

    var body: some View {
        ZStack {
            theme.canvas
            LinearGradient(
                colors: [theme.soft.opacity(theme.isDark ? 0.55 : 0.9), theme.canvas],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
