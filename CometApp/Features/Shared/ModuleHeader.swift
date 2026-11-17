//
//  ModuleHeader.swift
//  Comet
//
//  Modules are full surfaces, so they carry their own heading: an eyebrow, a
//  title, and a close lens. No navigation bar, no back chevron in a bar — the
//  same floating language as everything else.
//

import SwiftUI

struct ModuleHeader<Trailing: View>: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    let close: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    Haptics.tap()
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 38, height: 38)
                        .glassPanel(radius: 19)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")

                Spacer()

                trailing()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(type.label(10.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(type.display(32))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle)
                        .font(type.prose(12.5))
                        .foregroundStyle(theme.tertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, close: @escaping () -> Void) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, close: close) { EmptyView() }
    }
}

/// The background every module sits on.
struct ModuleBackground: View {
    @Environment(\.comet) private var theme

    var body: some View {
        ZStack {
            theme.canvasGradient
            RadialGradient(colors: [theme.accent.opacity(theme.isDark ? 0.16 : 0.10), Color.clear],
                           center: .topTrailing, startRadius: 20, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}
