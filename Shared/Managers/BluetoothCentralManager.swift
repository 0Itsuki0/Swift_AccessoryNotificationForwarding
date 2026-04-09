//
//  BluetoothCentralManager.swift
//  AccessorySetupKit+WiFiInfrastructure
//
//  Created by Itsuki on 2025/12/12.
//


import CoreBluetooth
import SwiftUI
import AccessorySetupKit
import CryptoKit
import AccessoryTransportExtension
import AccessoryNotifications
import OSLog

private let subsystem = "itsuki.accessory"
private let logger = Logger(subsystem: subsystem, category: "BluetoothPeripheralManager")

// MARK: Errors
extension BluetoothCentralManager {
    enum BluetoothCentralError: Error, LocalizedError {
        case managerNotInitialized
        case bluetoothNotAvailable
        
        case counterPeripheralNotDiscovered
        case peripheralCharacteristicNotDiscovered

        case failToConnect(Error)
        case failToDisconnect(Error)
        
        case failToDiscoverService(Error)
        case failToDiscoverCharacteristic(Error)
        case failToUpdateValue(Error)
        case failToUpdateNotify(Error)
        
        public var errorDescription: String? {
            switch self {
            case .managerNotInitialized:
                "managerNotInitialized"
            case .bluetoothNotAvailable:
                "bluetoothNotAvailable"
            case .counterPeripheralNotDiscovered:
                "counterPeripheralNotDiscovered"
            case .peripheralCharacteristicNotDiscovered:
                "peripheralCharacteristicNotDiscovered"
            case .failToConnect(let error):
                "failToConnect: \(error.localizedDescription)"
            case .failToDisconnect(let error):
                "failToDisconnect: \(error.localizedDescription)"
            case .failToDiscoverService(let error):
                "failToDiscoverService: \(error.localizedDescription)"
            case .failToDiscoverCharacteristic(let error):
                "failToDiscoverCharacteristic: \(error.localizedDescription)"
            case .failToUpdateValue(let error):
                "failToUpdateValue: \(error.localizedDescription)"
            case .failToUpdateNotify(let error):
                "failToUpdateNotify: \(error.localizedDescription)"
            }
        }

    }

}

// When migrating with AccessorySetupKit
// Don’t initialize a CBCentralManager before migration is complete.
// Otherwise, the accessory picker fails to appear and we will receive an error
@Observable
class BluetoothCentralManager: NSObject {
    private var counterAccessoryBluetoothId: UUID? = nil
    
    // since CBPeripheral cannot trigger any view updates,
    // we cannot use a calculated variable here, ie:
    // return self.counterPeripheral?.state
    private(set) var counterPeripheralState: CBPeripheralState = .disconnected
    
    // start with true to avoid showing error message in view
    // only set to false if we have indeed finish discovering the characteristic and the target one is not found.
    private(set) var counterCharacteristicFound: Bool = true
        
    private(set) var count: Int = 0

    // CBPeripheral will not trigger any view updates
    private var counterPeripheral: CBPeripheral? = nil {
        didSet {
            self.counterPeripheralState = self.counterPeripheral?.state ?? .disconnected
            if self.finishDiscoveringService && self.finishDiscoveringCharacteristic {
                self.counterCharacteristicFound = self.counterCharacteristic != nil
            }

            guard let data = self.counterCharacteristic?.value else {
                self.count = 0
                return
            }
            self.count = Int.fromData(data) ?? 0
        }
    }
    
    private var finishDiscoveringService: Bool {
        return self.counterPeripheral?.services != nil
    }
    
    var finishDiscoveringCharacteristic: Bool {
        return self.counterService?.characteristics != nil
    }
    
    private var counterService: CBService? {
        return self.counterPeripheral?.services?.first(where: {$0.uuid == BLEAccessory.serviceUUID})
    }
    
    private var counterCharacteristic: CBCharacteristic? {
        return self.counterService?.characteristics?.first(where: {$0.uuid == BLEAccessory.counterCharacteristicUUID})
    }
    
    private var notificationCharacteristic: CBCharacteristic? {
        return self.counterService?.characteristics?.first(where: {$0.uuid == BLEAccessory.notificationCharacteristicUUID})
    }
    
    private var keySharingCharacteristic: CBCharacteristic? {
        return self.counterService?.characteristics?.first(where: {$0.uuid == BLEAccessory.keySharingCharacteristicUUID})
    }

    
    private(set) var bluetoothState: CBManagerState = .poweredOff {
        didSet {
            if self.bluetoothState == .poweredOff, oldValue == .poweredOn {
                self.counterPeripheral = nil
                self.counterAccessoryBluetoothId = nil
            }
        }
    }
    
    private var centralManager: CBCentralManager?

    // for errors in the delegation functions
    let errorsStream: AsyncStream<Error>
    private let errorsContinuation: AsyncStream<Error>.Continuation

    // for chunked writes with .withoutResponse
    private var pendingWriteData: Data?
    private var pendingWriteOffset: Int = 0
    private var pendingWriteCharacteristic: CBCharacteristic?
    
    override init() {
        (self.errorsStream, self.errorsContinuation) = AsyncStream.makeStream(of: Error.self)
        super.init()
    }
    
    // In the case of migrating an accessory,
    // Don’t initialize a CBCentralManager before migration is complete.
    // If you do, your callback handler receives an error and the picker fails to appear.
    func initCBCentralManager(for accessory: ASAccessory) {
        guard self.centralManager == nil else { return }
        self.counterAccessoryBluetoothId = accessory.bluetoothIdentifier
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                // restoring state requires background mode
                // CBCentralManagerOptionRestoreIdentifierKey: NSString("AccessoryCentralManager")
            ]
        )
    }
    
    func deinitCBCentralManager() {
        self.centralManager = nil
        self.counterPeripheral = nil
        self.counterAccessoryBluetoothId = nil
    }
    
    func retrieveCounterPeripheral() throws {
        guard self.bluetoothState == .poweredOn else {
            throw BluetoothCentralError.bluetoothNotAvailable
        }
        guard let peripheralUUID = self.counterAccessoryBluetoothId else { return }
        guard self.counterPeripheral == nil || self.counterPeripheral?.identifier != peripheralUUID else { return }
        
        self.counterPeripheral = self.centralManager?.retrievePeripherals(withIdentifiers: [peripheralUUID]).first
    }
    
    func connectCounterPeripheral() throws {
        guard let counterPeripheral = self.counterPeripheral else {
            throw BluetoothCentralError.counterPeripheralNotDiscovered
        }
        try self.connectPeripheral(counterPeripheral)
        // set it manually here to avoid UI interactions
        self.counterPeripheralState = .connecting
    }

    func discoverCounterCharacteristic() throws {
        guard let counterService = self.counterService, let counterPeripheral = self.counterPeripheral else {
            throw BluetoothCentralError.counterPeripheralNotDiscovered
        }
        counterPeripheral.discoverCharacteristics([
            BLEAccessory.counterCharacteristicUUID,
            BLEAccessory.notificationCharacteristicUUID,
            BLEAccessory.keySharingCharacteristicUUID
        ], for: counterService)
    }

    func setCount(_ count: Int) async throws {
        guard let counterPeripheral = self.counterPeripheral else {
            throw BluetoothCentralError.counterPeripheralNotDiscovered
        }
        
        guard let counterCharacteristic = self.counterCharacteristic else {
            throw BluetoothCentralError.peripheralCharacteristicNotDiscovered
        }
        
        try await self.writeValue(counterPeripheral, data: count.data, for: counterCharacteristic, writeType: .withResponse)
    }
    
    
    func disconnectCounterPeripheral() {
        guard let counterPeripheral = self.counterPeripheral else { return }
        self.disconnectPeripheral(counterPeripheral)
    }
    
    
    func forwardNotification(notification: Data, sessionId: UUID) async throws {
        print(#function)
        guard let counterPeripheral = self.counterPeripheral else {
            throw BluetoothCentralError.counterPeripheralNotDiscovered
        }
        
        guard let notificationCharacteristic = self.notificationCharacteristic else {
            throw BluetoothCentralError.peripheralCharacteristicNotDiscovered
        }

        let encoder = JSONEncoder()
        let event = NotificationEvent(encryptedData: notification, sessionId: sessionId)
        let data = try encoder.encode(event)

        try await self.writeValue(counterPeripheral, data: data, for: notificationCharacteristic, writeType: .withoutResponse)
    }
    
    func sendKeys(keyMaterial: SecurityMessage.KeyMaterial, privateKey: Data, publicKey: Data) async throws {
        print(#function)
        guard let counterPeripheral = self.counterPeripheral else {
            throw BluetoothCentralError.counterPeripheralNotDiscovered
        }
        
        guard let keySharingCharacteristic = self.keySharingCharacteristic else {
            throw BluetoothCentralError.peripheralCharacteristicNotDiscovered
        }
        
        let encoder = JSONEncoder()
        let shareKeyEvent = ShareKeyEvent(keyMaterial: keyMaterial, publicKeyData: publicKey, privateKeyData: privateKey)
        let data = try encoder.encode(shareKeyEvent)

        try await self.writeValue(counterPeripheral, data: data, for: keySharingCharacteristic, writeType: .withoutResponse)
    }
}

// MARK: Private helpers
extension BluetoothCentralManager {
    private func connectPeripheral(_ peripheral: CBPeripheral) throws {
        guard self.bluetoothState == .poweredOn else {
            throw BluetoothCentralError.bluetoothNotAvailable
        }
        
        guard let centralManager = self.centralManager else {
            throw BluetoothCentralError.managerNotInitialized
        }
        
        centralManager.connect(peripheral, options: [CBConnectPeripheralOptionEnableAutoReconnect: true])
    }
    
    private func writeValue(_ peripheral: CBPeripheral, data: Data, for characteristic: CBCharacteristic, writeType: CBCharacteristicWriteType) async throws {
        guard self.bluetoothState == .poweredOn else {
            throw BluetoothCentralError.bluetoothNotAvailable
        }

        if writeType == .withoutResponse && data.count > peripheral.maximumWriteValueLength(for: .withoutResponse) {
            // Start chunked write
            self.pendingWriteData = data
            self.pendingWriteOffset = 0
            self.pendingWriteCharacteristic = characteristic

            // Send chunks in loop while peripheral can accept writes
            await self.sendPendingChunks(peripheral: peripheral)
        } else {
            peripheral.writeValue(data, for: characteristic, type: writeType)
        }
    }

    // not using peripheralIsReady(toSendWriteWithoutResponse) because it is only fired when a write fails
    // chunked handing required because both the notification data and the key data are way larger than the size limit.
    // if we don't chunk it, we will get silent errors (ie: not delivered to the peripheral, but also no actual error thrown).
    private func sendPendingChunks(peripheral: CBPeripheral) async {
        guard let data = self.pendingWriteData,
              let characteristic = self.pendingWriteCharacteristic else {
            return
        }
        
        let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        
        while self.pendingWriteOffset < data.count {
            logger.info("sending data chunk: \(self.pendingWriteOffset)")
            // Wait until peripheral can send
            while !peripheral.canSendWriteWithoutResponse {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            // send start
            if self.pendingWriteOffset == 0 {
                peripheral.writeValue(chunkDataStater, for: characteristic, type: .withoutResponse)
            }
            
            let remaining = data.count - self.pendingWriteOffset
            let chunkSize = min(maxLength, remaining)
            let chunk = data.subdata(in: self.pendingWriteOffset..<(self.pendingWriteOffset + chunkSize))
            
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            self.pendingWriteOffset += chunkSize
            
            // Small delay between chunks
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        
        // send start
        while !peripheral.canSendWriteWithoutResponse {
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            if peripheral.canSendWriteWithoutResponse{
                break
            }
        }
        
        peripheral.writeValue(chunkDataTerminator, for: characteristic, type: .withoutResponse)

        // Clear state when done
        self.pendingWriteData = nil
        self.pendingWriteOffset = 0
        self.pendingWriteCharacteristic = nil
    }
    
    private func disconnectPeripheral(_ peripheral: CBPeripheral) {
        guard let centralManager = self.centralManager else { return }
        if peripheral.state == .connected {
            for service in (peripheral.services ?? [] as [CBService]) {
                for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                    peripheral.setNotifyValue(false, for: characteristic)
                }
            }
        }
        if peripheral.state != .disconnected || peripheral.state != .disconnecting  {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        // not calling updatePeripheral here but wait for the cancelPeripheralConnection result in the delegation function.
    }
    
    private func updatePeripheral(_ peripheral: CBPeripheral) {
        if peripheral.identifier == self.counterAccessoryBluetoothId {
            self.counterPeripheral = peripheral
        }
    }
}


// MARK: CBCentralManagerDelegate
extension BluetoothCentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print(#function)
        self.bluetoothState = central.state
    }
    
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print(#function)
        self.updatePeripheral(peripheral)
        
        guard peripheral.identifier == self.counterAccessoryBluetoothId else {
            return
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([BLEAccessory.serviceUUID])
        
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        print(#function)
        self.updatePeripheral(peripheral)
        
        // Disconnect not due to the cancelPeripheralConnection operation
        if let error {
            self.errorsContinuation.yield(BluetoothCentralError.failToDisconnect(error))
            // not automatically reconnecting
            if !isReconnecting {
                try? self.connectPeripheral(peripheral)
            }
        }
        
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        print(#function)
        if let error {
            self.errorsContinuation.yield(BluetoothCentralError.failToConnect(error))
        }
        
        // to perform any clean up
        self.disconnectPeripheral(peripheral)
        self.updatePeripheral(peripheral)
    }
    
}


// MARK: CBPeripheralDelegate
extension BluetoothCentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print(#function)
        self.updatePeripheral(peripheral)
    }
    
    // NOTE:
    // If we are not discovering any services without an error, ie: peripheral.services is an empty array
    // make sure that on the peripheral side, those services are indeed added to the CBPeripheralManager.
    // PS: the peripheral does NOT have to be advertising though.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        print(#function)
        self.updatePeripheral(peripheral)

        if let error {
            self.errorsContinuation.yield(BluetoothCentralError.failToDiscoverService(error))
            return
        }
        
        do {
            try self.discoverCounterCharacteristic()
        } catch(let error) {
            self.errorsContinuation.yield(error)
        }

    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        print(#function)
        self.updatePeripheral(peripheral)

        if let error {
            self.errorsContinuation.yield(BluetoothCentralError.failToDiscoverCharacteristic(error))
            return
        }
        guard let counterCharacteristic = self.counterCharacteristic else { return }
        peripheral.setNotifyValue(true, for: counterCharacteristic)
        peripheral.readValue(for: counterCharacteristic)

    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        print(#function)
        self.updatePeripheral(peripheral)

        if let error {
            self.errorsContinuation.yield(BluetoothCentralError.failToDiscoverCharacteristic(error))
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        print(#function)
        
        self.updatePeripheral(peripheral)

        if let error {
            self.errorsContinuation.yield(BluetoothCentralError.failToDiscoverCharacteristic(error))
        }

    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        self.updatePeripheral(peripheral)
        if let counterCharacteristic = self.counterCharacteristic, !counterCharacteristic.isNotifying {
            // read value
            peripheral.readValue(for: counterCharacteristic)
        }
    }
}

