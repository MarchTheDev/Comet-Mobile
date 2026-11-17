//
//  Haptics.swift
//  Comet
//
//  Every press, drop, tick and edge in the app answers through the Taptic
//  Engine. One switch turns them off.
//

import UIKit

enum Haptics {
    static var enabled = true

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    static func press() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }

    static func heavy() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
    }

    static func select() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.35)
}
