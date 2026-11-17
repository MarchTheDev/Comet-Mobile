//
//  CometApp.swift
//  Comet
//
//  A SwiftUI app with no storyboard, no navigation bar and no web view: every
//  surface is drawn here.
//

import SwiftUI

@main
struct CometApp: App {
    @StateObject private var model = CometModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reload()
                    }
                }
        }
    }
}
