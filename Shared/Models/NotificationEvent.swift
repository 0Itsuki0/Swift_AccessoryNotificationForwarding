//
//  NotificationEvent.swift
//  AccessoryNotificationForwarding
//
//  Created by Itsuki on 2026/04/08.
//

import Foundation
import AccessoryNotifications

// codable to be sent from AccessoryTransportAppExtension to the BLE accessory
struct NotificationEvent: Codable {
    // encrypted data of NotificationPayLoad
    var encryptedData: Data
    var sessionId: UUID
}
