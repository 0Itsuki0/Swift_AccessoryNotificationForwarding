//
//  AccessorySetupKit_WiFiInfrastructureApp.swift
//  AccessorySetupKit+WiFiInfrastructure
//
//  Created by Itsuki on 2025/12/10.
//

import SwiftUI

@main
struct AccessoryCompanionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let accessoryManager = AccessoryManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(self.accessoryManager)
        }
    }
}
