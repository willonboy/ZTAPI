//
//  AppDelegate.swift
//  JsonDemo
//
//  Created by zt on 2025/3/29.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow.init(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.backgroundColor = .white
        window?.makeKeyAndVisible()
        return true
    }
}
