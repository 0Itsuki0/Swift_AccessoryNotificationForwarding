//
//  ShareKeyEvent.swift
//  AccessoryNotificationForwarding
//
//  Created by Itsuki on 2026/04/08.
//

import Foundation
import AccessoryTransportExtension

struct ShareKeyEvent: Codable {
    var keyMaterial: SecurityMessage.KeyMaterial
    var publicKeyData: Data
    var privateKeyData: Data
}
