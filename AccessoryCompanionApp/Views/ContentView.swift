//
//  ContentView.swift
//  AccessorySetupKit+WiFiInfrastructure
//
//  Created by Itsuki on 2025/12/12.
//

import AccessoryNotifications
import AccessorySetupKit
import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @Environment(AccessoryManager.self) private var accessoryManager
    @Environment(\.openURL) private var openURL

    @State private var count: Int = 0

    private let notificationCenter = UNUserNotificationCenter.current()

    var body: some View {

        NavigationStack {
            VStack(spacing: 16) {
                if self.accessoryManager.counterPaired {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Paired Accessory")
                            .font(.headline)

                        CounterView(count: $count)
                            .disabled(
                                !(self.accessoryManager
                                    .counterCharacteristicFound
                                    && self.accessoryManager
                                        .counterPeripheralConnected)
                            )

                        VStack(alignment: .leading) {
                            HStack(alignment: .center, spacing: 16) {
                                Text("Notification Forwarding: ")
                                Spacer()
                                Group {
                                    switch self.accessoryManager
                                        .forwardingDecision
                                    {
                                    case .allow:
                                        Text("Allowed")
                                    case .limited:
                                        Text(
                                            "Limited to specific apps."
                                        )
                                    case .deny:
                                        Text("Denied")
                                    case .undetermined:
                                        EmptyView()
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }

                            if self.accessoryManager.forwardingDecision
                                == .undetermined
                            {
                                Button(
                                    action: {
                                        self.accessoryManager
                                            .requestNotificationForwardingPermission()
                                    },
                                    label: {
                                        Text("Request For Permission")
                                    }
                                )
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.link)
                            }

                            if self.accessoryManager.counterPeripheralState
                                == .connected,
                                self.accessoryManager.forwardingDecision
                                    == .allow
                                    || self.accessoryManager
                                        .forwardingDecision == .limited
                            {
                                Button(
                                    action: {
                                        self.showTestNotification()
                                    },
                                    label: {
                                        Text("Send Test Notification")
                                            .multilineTextAlignment(
                                                .trailing
                                            )
                                    }
                                )
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.link)
                            } else {
                                Text(
                                    "Connect BLE & Grant Permission to test it out."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.7)
                            }
                        }
                    }

                    Divider()

                    VStack(spacing: 16) {

                        self.connectionButton()

                        Button(
                            action: {
                                Task {
                                    await self.accessoryManager
                                        .removeCounter()
                                }
                            },
                            label: {
                                Text("Remove Accessory")
                                    .font(.headline)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(1)
                            }
                        )
                        .buttonStyle(.bordered)

                        Group {
                            if self.accessoryManager
                                .counterPeripheralConnected
                                && !self.accessoryManager
                                    .counterCharacteristicFound
                            {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(
                                            "Counter characteristic not found!"
                                        )
                                        Spacer()

                                        Button(
                                            action: {
                                                self.accessoryManager
                                                    .discoverCounterCharacteristic()
                                            },
                                            label: {
                                                Text("Retry")
                                            }
                                        )
                                    }

                                    Text(
                                        "Is the service added to the accessory?"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 48)
                    }
                    .padding(.horizontal, 16)

                } else {
                    ContentUnavailableView(
                        label: {
                            Label(
                                "No Paired Counter",
                                systemImage: "link.badge.plus"
                            )
                        },
                        description: {
                            Text("Please pair with the BLE Accessory first.")
                        },
                        actions: {
                            Button(
                                action: {
                                    Task {
                                        await self.accessoryManager
                                            .presentAccessoryPicker()
                                    }
                                },
                                label: {
                                    Text("Add Accessory")
                                }
                            )
                        }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let error = self.accessoryManager.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .frame(
                            maxWidth: .infinity,
                            alignment: self.accessoryManager
                                .counterCharacteristicFound ? .leading : .center
                        )
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)

                } else {
                    Text(" ")
                }

            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.yellow.opacity(0.1))
            .navigationTitle("Companion App")
            .onChange(
                of: self.accessoryManager.count,
                initial: true,
                {
                    self.count = self.accessoryManager.count
                }
            )
            .onChange(
                of: self.count,
                {
                    guard self.count != self.accessoryManager.count else {
                        return
                    }

                    self.accessoryManager.setCount(self.count)
                }
            )
        }
    }

    @ViewBuilder
    private func connectionButton() -> some View {

        let buttonParameters: (String, () -> Void) =
            switch self.accessoryManager.counterPeripheralState {
            case .connected:
                (
                    "Disconnect",
                    {
                        self.accessoryManager.disconnectCounter()
                    }
                )
            case .connecting:
                ("Connecting...", {})
            case .disconnected:
                (
                    "Connect",
                    {
                        self.accessoryManager.connectCounter()
                    }
                )
            case .disconnecting:
                ("Disconnecting...", {})
            @unknown default:
                ("Apple is bugging...", {})
            }

        Button(
            action: buttonParameters.1,
            label: {
                Text(buttonParameters.0)
                    .font(.headline)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
        )
        .buttonStyle(.glassProminent)
        .disabled(
            self.accessoryManager.counterPeripheralState == .connecting
                || self.accessoryManager.counterPeripheralState
                    == .disconnecting
        )
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
            await registerNotificationRequest(
                content: content,
                trigger: trigger
            )
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
