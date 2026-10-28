//
//  Presence.swift
//  Comet for iOS
//
//  The two things a web view cannot do for itself, both of them small and both
//  of them most of what makes a page feel like an app rather than a page:
//
//    - taps that answer through the Taptic Engine, and
//    - a status bar whose text stays legible as the theme changes.
//
//  The page asks for them through the same bridge as every other command, so
//  nothing here depends on the web view knowing it is inside one.
//

import UIKit

/// Which way round the status bar should draw, as last reported by the page.
///
/// Comet's default is the dark theme, so that is the starting point: a light
/// clock on the Matterhorn, which is what the app looked like before this
/// existed.
enum Appearance {
    private(set) static var prefersLightStatusBar = true

    static func setStatusBarLight(_ light: Bool) {
        guard light != prefersLightStatusBar else { return }
        prefersLightStatusBar = light
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .cometStatusBarStyleChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let cometStatusBarStyleChanged = Notification.Name("cometStatusBarStyleChanged")
}

enum Haptics {
    /// Named the way the page names them, so there is no mapping table to get
    /// out of step: "light", "medium", "heavy", "selection", "success",
    /// "warning", "error".
    static func play(_ style: String) {
        DispatchQueue.main.async {
            switch style {
            case "selection":
                let generator = UISelectionFeedbackGenerator()
                generator.prepare()
                generator.selectionChanged()

            case "success":
                UINotificationFeedbackGenerator().notificationOccurred(.success)

            case "warning":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)

            case "error":
                UINotificationFeedbackGenerator().notificationOccurred(.error)

            case "heavy", "medium", "light":
                let weight: UIImpactFeedbackGenerator.FeedbackStyle = style == "heavy" ? .heavy : (style == "medium" ? .medium : .light)
                let generator = UIImpactFeedbackGenerator(style: weight)
                // Preparing first is what makes the tap land with the press
                // rather than a beat after it.
                generator.prepare()
                generator.impactOccurred()

            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}
