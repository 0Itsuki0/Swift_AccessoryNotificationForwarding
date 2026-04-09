//
//  AccessoryTransportSecurity.swift
//  AccessoryTransportSecurity
//
//  Created by Itsuki on 2026/04/07.
//

import AccessorySetupKit
import AccessoryTransportExtension
import CoreBluetooth
import CryptoKit
import ExtensionFoundation
import OSLog

private let subsystem = "itsuki.accessory"
private let logger = Logger(
    subsystem: subsystem,
    category: "accessory-transport-security"
)

@main
struct TransportSecurity: AccessoryTransportSecurity {
    @AppExtensionPoint.Bind
    static var boundExtensionPoint: AppExtensionPoint {
        Identifier("com.apple.accessory-transport-security")
    }

    func accept(sessionRequest: AccessorySecuritySession.Request)
        -> AccessorySecuritySession.Request.Decision
    {
        return sessionRequest.accept {
            SecurityEventHandler(session: sessionRequest.session)
        }
    }
}

// https://developer.apple.com/documentation/accessorytransportextension/accessorysecuritysession/eventhandler
// protocol to respond to key exchange events and session invalidation.
class SecurityEventHandler: AccessorySecuritySession.EventHandler {
    private var accessorySession = ASAccessorySession()
    private var session: AccessorySecuritySession
    private var keySharingManager: ExtensionMessagingManager?

    private var privateKeyData: Data?
    private var publicKeyData: Data?
    private var keyMaterial: SecurityMessage.KeyMaterial?

    init(session: AccessorySecuritySession) {
        self.session = session
        // retrieve the BLE accessory with AccessorySetupKit
        accessorySession.activate(
            on: DispatchQueue.main,
            eventHandler: handleASAccessoryEvent(event:)
        )
    }

    private func handleASAccessoryEvent(event: ASAccessoryEvent) {
        logger.info("\(#function): \(event.eventType == .activated)")
        switch event.eventType {
        case .activated:
            guard
                let accessory = accessorySession.accessories.first(where: {
                    $0.descriptor.bluetoothServiceUUID
                        == BLEAccessory.serviceUUID
                })
            else { return }
            self.keySharingManager = .init(for: accessory, logger: logger)
        case .invalidated:
            break
        default:
            break
        }
    }

    // Security message for key events received from the system
    func securityMessageReceived(_ message: SecurityMessage) {
        logger.info("\(#function)")
        do {
            switch message {
            // [Step 1] Received a key request from the system
            case .keyRequest:
                logger.info("keyRequest")
                try self.handleKeyRequest()

            // keyReply: to be used as a reply to the key request, we will never receive such a message in securityMessageReceived
            case .keyReply(_, _):
                logger.info("keyReply")

            // [Step 3] receiving key material from the extension
            case .keyExchange(let keyMaterial):
                logger.info("keyExchange")
                try self.handleKeyExchange(keyMaterial)

            // encapsulatedKey: to be used as a reply to the keyExchange, we will never receive such a message in securityMessageReceived
            case .encapsulatedKey(_):
                logger.info("encapsulatedKey")

            @unknown default:
                break
            }
        } catch (let error) {
            logger.error(
                "securityMessageReceived: \(error.localizedDescription)"
            )
            session.cancel(error: nil)
        }
    }

    func sessionInvalidated(error: AccessorySecuritySession.Error?) {
        keyMaterial = nil
        privateKeyData = nil
        publicKeyData = nil
        session.cancel(error: error)
    }

    private func handleKeyRequest() throws {
        // Generate an XWing key pair.
        let privateKey = try XWingMLKEM768X25519.PrivateKey()
        privateKeyData = privateKey.seedRepresentation
        let publicKeyData = privateKey.publicKey.rawRepresentation
        self.publicKeyData = publicKeyData
        // [Step 2]: Return the public key to the system.
        try session.sendSecurityMessage(
            .keyReply(ciphersuite: .xWing, publicKey: publicKeyData)
        )
    }

    private func handleKeyExchange(_ keyMaterial: SecurityMessage.KeyMaterial)
        throws
    {
        guard let privateKeyData = privateKeyData,
            let publicKeyData = publicKeyData
        else {
            logger.info("private and public keys undefined")
            session.cancel(error: nil)
            return
        }

        self.keyMaterial = keyMaterial
        Task {
            do {
                let maxWaitMillisecond: Double = 10 * 1000
                var currentWait: Double = 0
                let interval: Double = 5

                while self.keySharingManager == nil {
                    try? await Task.sleep(for: .milliseconds(interval))
                    if self.keySharingManager != nil {
                        break
                    }
                    if currentWait > maxWaitMillisecond {
                        logger.info("Max wait duration exceeded")
                        session.cancel(error: nil)
                        return
                    }
                    currentWait += interval
                }

                guard let keySharingManager else {
                    logger.info("key sharing manager undefined.")
                    return
                }
                // [Step 4]: send keyMaterial, public & private key data, to accessory
                try await keySharingManager.shareKeys(
                    keyMaterial: keyMaterial,
                    privateKey: privateKeyData,
                    publicKey: publicKeyData
                )
                logger.info("key sent successfully")
                // [Step 5]: reply to the system with encapsulatedKey
                try session.sendSecurityMessage(
                    .encapsulatedKey(keyMaterial.encapsulatedKey)
                )
            } catch (let error) {
                logger.error("handleKeyExchange: \(error.localizedDescription)")
                session.cancel(error: nil)
            }
        }

    }
}
