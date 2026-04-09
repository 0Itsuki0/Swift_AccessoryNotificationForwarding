//
//  NotificationPayLoad.swift
//  AccessoryCompanionApp
//
//  Created by Itsuki on 2026/04/09.
//


import Foundation
import AccessoryNotifications

// codable to be sent from AccessoryDataProvider to the system
enum NotificationPayLoad: Codable {
    case add(AccessoryNotification, AlertingContext)
    case update(AccessoryNotification)
    case remove(AccessoryNotification.Identifier)
    case removeAll
}
