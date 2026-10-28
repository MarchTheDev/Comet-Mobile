//
//  AppDelegate.swift
//  Comet for iOS
//

import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirstRun.prepare()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = CometTheme.background
        window.rootViewController = CometViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppServices.shared.shutdown()
    }
}
