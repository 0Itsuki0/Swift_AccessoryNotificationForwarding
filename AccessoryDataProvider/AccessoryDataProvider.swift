//
//  AccessoryDataProvider.swift
//  AccessoryDataProvider
//
//  Created by Itsuki on 2026/04/07.
//

import AccessoryNotifications
import AccessoryTransportExtension
import ExtensionFoundation
import OSLog

private let subsystem = "itsuki.accessory"
private let logger = Logger(
    subsystem: subsystem,
    category: "accessory-data-provider"
)

@main
struct DataProvider: AccessoryDataProvider {
    var extensionPoint: AppExtensionPoint {
        Identifier("com.apple.accessory-data-provider")
        Implementing {
            NotificationsForwarding {
                NotificationHandler()
            }
        }
    }
}

// Responds to system-related notification requests.
final class NotificationHandler: NotificationsForwarding
        .AccessoryNotificationsHandler
{
    @MainActor
    private var session: NotificationsForwarding.Session?

    // called When a notification occurs on the iPhone
    func activate(for session: NotificationsForwarding.Session) {
        logger.info("\(#function)")
        Task { @MainActor in
            self.session = session
        }
    }

    func removeAllNotifications() {
        logger.info("\(#function)")
        Task { @MainActor in
            guard let session else {
                logger.info("session undefined")
                return
            }

            let message = try buildAccessoryMessage(.removeAll)
            do {
                try await session.send(message: message)
                logger.info("message send successfully")
            } catch (let error) {
                logger.error(
                    "error sending message: \(error.localizedDescription)"
                )
            }
        }
    }

    @MainActor
    func addNotification(
        _ notification: AccessoryNotification,
        alertingContext: AlertingContext
    ) async throws -> Bool {
        logger.info("\(#function)")

        guard let session else {
            logger.info("session undefined")
            return false
        }

        let message = try buildAccessoryMessage(
            .add(notification, alertingContext)
        )
        try await session.send(message: message)
        logger.info("message send successfully")
        return true
    }

    func updateNotification(_ notification: AccessoryNotification) {
        logger.info("\(#function)")
        Task { @MainActor in
            guard let session else {
                logger.info("session undefined")
                return
            }

            let message = try buildAccessoryMessage(.update(notification))
            do {
                try await session.send(message: message)
                logger.info("message send successfully")
            } catch (let error) {
                logger.error(
                    "error sending message: \(error.localizedDescription)"
                )
            }
        }
    }

    func removeNotification(identifier: AccessoryNotification.Identifier) {
        logger.info("\(#function)")
        Task { @MainActor in
            guard let session else {
                logger.info("session undefined")
                return
            }

            let message = try buildAccessoryMessage(.remove(identifier))
            do {
                try await session.send(message: message)
                logger.info("message send successfully")
            } catch (let error) {
                logger.error(
                    "error sending message: \(error.localizedDescription)"
                )
            }
        }

    }

    // Called when a message from the paired accessory has been received and decrypted
    func messageHandler(_ message: TransportMessage) {
        logger.info("\(#function)")
    }

    private func buildAccessoryMessage(_ notification: NotificationPayLoad)
        throws -> AccessoryMessage
    {
        let encoder = JSONEncoder()
        let data = try encoder.encode(notification)

        let message = AccessoryMessage {
            AccessoryMessage.Payload(transport: .bluetooth, data: data)
        }

        return message
    }
}
