//
//  AuroraBackground.swift
//  Comet
//
//  The app's one piece of decoration: a slow aurora and a still field of stars,
//  drawn in a Canvas rather than stacked blurred layers so it costs one view.
//  It pauses when Reduce Motion is on, and again when the app is in the
//  background.
//

import SwiftUI

struct AuroraBackground: View {
    let theme: CometTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            theme.canvasGradient

            TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: reduceMotion || scenePhase != .active)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    drawAurora(in: &context, size: size, time: time)
                    drawStars(in: &context, size: size, time: time)
                }
            }
            .opacity(theme.isDark ? 1 : 0.5)
            .allowsHitTesting(false)

            // A soft vignette keeps the corners quiet so content reads first.
            RadialGradient(
                colors: [Color.clear, theme.canvas.opacity(theme.isDark ? 0.55 : 0.35)],
                center: .center,
                startRadius: 140,
                endRadius: 620
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func drawAurora(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let blobs: [(color: Color, radius: CGFloat, x: Double, y: Double, speed: Double, phase: Double)] = [
            (theme.accent.opacity(theme.isDark ? 0.32 : 0.20), 320, 0.18, 0.12, 0.07, 0.0),
            (theme.accentTwo.opacity(theme.isDark ? 0.26 : 0.16), 380, 0.86, 0.26, 0.05, 2.1),
            (theme.glow.opacity(theme.isDark ? 0.22 : 0.12), 300, 0.64, 0.86, 0.06, 4.2),
        ]
        for blob in blobs {
            let cx = size.width * (blob.x + sin(time * blob.speed + blob.phase) * 0.05)
            let cy = size.height * (blob.y + cos(time * blob.speed * 0.8 + blob.phase) * 0.04)
            let rect = CGRect(x: cx - blob.radius, y: cy - blob.radius,
                              width: blob.radius * 2, height: blob.radius * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [blob.color, blob.color.opacity(0)]),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0,
                    endRadius: blob.radius
                )
            )
        }
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard theme.isDark else { return }
        for index in 0..<64 {
            let fx = Double((index * 41 + 17) % 101) / 101.0
            let fy = Double((index * 67 + 29) % 97) / 97.0
            let twinkle = 0.22 + 0.20 * (0.5 + 0.5 * sin(time * 0.55 + Double(index) * 1.7))
            let radius = index % 9 == 0 ? 1.4 : 0.8
            let point = CGPoint(x: size.width * fx, y: size.height * fy)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(Color.white.opacity(twinkle))
            )
        }
    }
}
