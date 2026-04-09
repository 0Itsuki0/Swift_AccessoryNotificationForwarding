//
//  ExtensionMessagingManager.swift
//  AccessoryCompanionApp
//
//  Created by Itsuki on 2026/04/09.
//

import CoreBluetooth
import AccessoryNotifications
import AccessorySetupKit
import OSLog
import AccessoryTransportExtension

final class ExtensionMessagingManager {
    private var bluetoothManager = BluetoothCentralManager()
    // The accessory associated with this extension session.
    private let accessory: ASAccessory
    private let logger: Logger

    init(for accessory: ASAccessory, logger: Logger) {
        self.accessory = accessory
        self.bluetoothManager.initCBCentralManager(for: accessory)
        self.logger = logger
        Task {
            do {
                try await self.retrievePeripheralAndConnect()
                logger.info("peripheral connected")
            } catch (let error) {
                logger.error("error connecting: \(error.localizedDescription)")
            }
        }
    }
    
    func forwardNotification(notification: Data, sessionId: UUID) async throws {
        logger.info("\(#function)")
        try await self.waitForFinishDiscoveringCharacteristic()
        logger.info("peripheral connected: sending data")
        try await self.bluetoothManager.forwardNotification(notification: notification, sessionId: sessionId)
    }


    func shareKeys(
        keyMaterial: SecurityMessage.KeyMaterial,
        privateKey: Data,
        publicKey: Data
    ) async throws {
        logger.info("\(#function)")
        try await self.waitForFinishDiscoveringCharacteristic()
        logger.info("peripheral connected: sending key")

        try await self.bluetoothManager.sendKeys(
            keyMaterial: keyMaterial,
            privateKey: privateKey,
            publicKey: publicKey
        )
    }

    func retrievePeripheralAndConnect() async throws {
        try await waitForBluetoothPowerOn()
        try self.bluetoothManager.retrieveCounterPeripheral()
        try self.bluetoothManager.connectCounterPeripheral()
        try await waitForFinishDiscoveringCharacteristic()
    }

    private func waitForBluetoothPowerOn() async throws {
        try await self.waitFor(
            {
                return self.bluetoothManager.bluetoothState == .poweredOn
            },
            throw: BluetoothCentralManager.BluetoothCentralError
                .bluetoothNotAvailable
        )
    }

    private func waitForFinishDiscoveringCharacteristic() async throws {
        try await self.waitFor(
            {
                return self.bluetoothManager.finishDiscoveringCharacteristic
            },
            throw: BluetoothCentralManager.BluetoothCentralError
                .peripheralCharacteristicNotDiscovered
        )
    }

    private func waitFor(_ condition: () -> Bool, throw error: Error)
        async throws
    {
        // 10 seconds
        let maxWaitMillisecond: Double = 10 * 1000
        var currentWait: Double = 0
        let interval: Double = 5

        while condition() == false {
            if currentWait > maxWaitMillisecond {
                throw error
            }
            try? await Task.sleep(for: .milliseconds(interval))
            currentWait += interval
            if condition() {
                break
            }
        }
    }

}
