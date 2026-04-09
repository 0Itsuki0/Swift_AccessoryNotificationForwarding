//
//  AccessoryTransportAppExtension.swift
//  AccessoryTransportAppExtension
//
//  Created by Itsuki on 2026/04/07.
//

import AccessorySetupKit
import AccessoryTransportExtension
import ExtensionFoundation
import Foundation
import OSLog
import CoreBluetooth

private let subsystem = "itsuki.accessory"
private let logger = Logger(subsystem: subsystem, category: "accessory-transport-extension")

// Main entry point for the Accessory Transport Extension.
@main
struct TransportExtension: AccessoryTransportAppExtension {

    /// Bind to the extension point.
    @AppExtensionPoint.Bind
    static var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier("com.apple.accessory-transport-extension")
    }

    func accept(sessionRequest: AccessoryTransportSession.Request) -> AccessoryTransportSession.Request.Decision {
        logger.info("Receive session request")
        return sessionRequest.accept {
            return TransportEventHandler(session: sessionRequest.session)
        }
    }
}


class TransportEventHandler: AccessoryTransportSession.EventHandler {
    private var accessorySession = ASAccessorySession()
    private var transportSession: AccessoryTransportSession
    private var notificationManager: ExtensionMessagingManager?

    init(session: AccessoryTransportSession) {
        transportSession = session
        // retrieve the BLE accessory with AccessorySetupKit
        accessorySession.activate(on: DispatchQueue.main, eventHandler: handleASAccessoryEvent(event:))
    }
    
    private func handleASAccessoryEvent(event: ASAccessoryEvent) {
        logger.info("\(#function): \(event.eventType == .activated)")
        switch event.eventType {
        case .activated:
            guard let accessory = accessorySession.accessories.first(where: {$0.descriptor.bluetoothServiceUUID == BLEAccessory.serviceUUID}) else { return }
            notificationManager = ExtensionMessagingManager(for: accessory, logger: logger)
        case .invalidated:
            break
        default:
            break
        }
    }

    func sessionInvalidated(error: AccessoryTransportSession.Error?) {
        logger.info("\(#function)")
        self.transportSession.cancel(error: error)
    }
    
    func messageReceived(_ message: TransportMessage, completion: @escaping TransportMessage.Completion) {
        logger.info("\(#function)")
        // send message to accessory
        Task {
            let maxWaitMillisecond: Double = 10 * 1000
            var currentWait: Double = 0
            let interval: Double = 5

            while self.notificationManager == nil {
                try? await Task.sleep(for: .milliseconds(interval))
                if self.notificationManager != nil {
                    break
                }
                if currentWait > maxWaitMillisecond {
                    logger.info("Max wait duration exceeded")
                    completion(.failure)
                    return
                }
                currentWait += interval
            }

            guard let notificationManager else {
                logger.info("notificationManager not initialized")
                return
            }

            let transportMessageResult: TransportMessage.Result
            do {
                try await notificationManager.forwardNotification(notification: message.data, sessionId: message.sessionID)
                logger.info("send data with success")
                transportMessageResult = .success
            } catch(let error) {
                logger.error("messageReceived error: \(error.localizedDescription)")
                transportMessageResult = .failure
            }
            completion(transportMessageResult)
        }
    }
}
