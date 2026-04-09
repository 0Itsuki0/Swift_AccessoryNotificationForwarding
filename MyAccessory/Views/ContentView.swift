//
//  ContentView.swift
//  MyAccessory
//
//  Created by Itsuki on 2025/12/10.
//

import SwiftUI
import AccessoryNotifications

struct ContentView: View {
    @Environment(BluetoothPeripheralManager.self) private var peripheralManager
    
    var body: some View {
        
        @Bindable var peripheralManager = peripheralManager
        
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    Toggle("Advertise", isOn: $peripheralManager.isAdvertising)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Connected Centrals")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(self.peripheralManager.subscribedCentralCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    if let error = peripheralManager.error {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    } 
                }
                .padding(.horizontal, 16)
                
                Divider()

                CounterView(count: $peripheralManager.count)

                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Forwarded Notifications")
                        .font(.headline)
                        
                    ScrollView {
                        if self.peripheralManager.forwardedNotification.isEmpty {
                            Text("No notifications forwarded.")
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(spacing: 16) {
                            ForEach(0..<self.peripheralManager.forwardedNotification.count, id: \.self) { index in
                                let notification: AccessoryNotification = self.peripheralManager.forwardedNotification[index]
                                self.notificationView(notification)
                                Divider()
                            }
                            
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.yellow.opacity(0.1))
            .navigationTitle("BLE Accessory")
        }
    }
    
    @ViewBuilder
    private func notificationView(_ notification: AccessoryNotification) -> some View {
        VStack(alignment: .leading) {
            Text(notification.title ?? "No title")
                .font(.headline)
            
            Text("Delivered at: \(notification.deliveryDate.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
            Text("From App: \(notification.sourceName)")
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}



#Preview {
    ContentView()
        .environment(BluetoothPeripheralManager())
}
