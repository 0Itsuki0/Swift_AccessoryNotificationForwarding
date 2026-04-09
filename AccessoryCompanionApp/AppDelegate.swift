//
//  AppDelegate.swift
//  AccessoryNotificationForwarding
//
//  Created by Itsuki on 2026/04/07.
//

import SwiftUI

// for sending some local push notifications 
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setBadgeCount(0)
        requestNotificationPerfmission()
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    // Request user permissions
    func requestNotificationPerfmission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) {
                granted, error in
                print("Permission granted: \(granted)")
            }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [[.badge, .sound, .banner, .list]]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        print(response.notification.request.content)
        // title, body, userInfo(data)
    }
}
