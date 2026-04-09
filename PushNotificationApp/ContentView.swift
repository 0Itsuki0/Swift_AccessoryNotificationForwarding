//
//  ContentView.swift
//  PushNotification
//
//  Created by Itsuki on 2026/04/07.
//

import SwiftUI

struct ContentView: View {
    private let notificationCenter = UNUserNotificationCenter.current()

    var body: some View {
        VStack(spacing: 36) {
            Text("Some other app \nsending notifications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Make sure BLE Accessory is connected!")
                .font(.caption)
            
            Button(action: {
                self.showTestNotification()
            }, label: {
                Text("Send Notification")
                    .font(.headline)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            })
            .buttonStyle(.bordered)

        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.yellow.opacity(0.1))
    }
    
    private func showTestNotification() {
        Task {
            // content
            let content = UNMutableNotificationContent()
            content.title = "Some Notification From Itsuki!"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 0.1,  // time interval must be greater than 0
                repeats: false
            )
            await registerNotificationRequest(content: content, trigger: trigger)
        }
    }

    private func registerNotificationRequest(
        content: UNMutableNotificationContent,
        trigger: UNNotificationTrigger
    ) async {
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        // Schedule the request with the system.
        do {
            try await notificationCenter.add(request)
            print(
                "registration succeed for request with identifier \(identifier)"
            )
        } catch (let error) {
            // Handle errors that may occur during add.
            print("error adding request: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
