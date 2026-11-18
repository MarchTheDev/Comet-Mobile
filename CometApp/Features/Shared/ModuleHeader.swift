//
//  ModuleHeader.swift
//  Comet
//
//  A module is a full surface with its own heading: a close button, an eyebrow,
//  a title, and one action on the right. The same flat panels as the desktop.
//

import SwiftUI

struct ModuleHeader<Trailing: View>: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    /// Nil when the module is a tab rather than a sheet: a screen you can
    /// reach from the bar does not need a button to close it.
    var close: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let close {
                    Button {
                        Haptics.tap()
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.secondary)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(theme.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Close")
                } else {
                    CometMark(size: 34)
                }

                Spacer()

                trailing()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(type.label(10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(theme.tertiary)
                Text(title)
                    .font(type.display(32))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle)
                        .font(type.prose(12.5))
                        .foregroundStyle(theme.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, close: (() -> Void)? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, close: close) { EmptyView() }
    }
}

/// The flat canvas every module sits on.
struct ModuleBackground: View {
    @Environment(\.comet) private var theme

    var body: some View {
        theme.canvas.ignoresSafeArea()
    }
}
