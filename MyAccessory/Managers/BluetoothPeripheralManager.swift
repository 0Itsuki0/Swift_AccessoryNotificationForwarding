//
//  BluetoothPeripheralManager.swift
//  AccessorySetupKit+WiFiInfrastructure
//
//  Created by Itsuki on 2025/12/10.
//

//import AccessoryTransportExtension
import AccessoryNotifications
import AccessoryTransportExtension
import CoreBluetooth
import CryptoKit
import OSLog
import SwiftUI

private let subsystem = "itsuki.accessory"
private let logger = Logger(
    subsystem: subsystem,
    category: "BluetoothPeripheralManager"
)

extension BluetoothPeripheralManager {
    enum BluetoothPeripheralError: Error {
        case managerNotInitialized
        case bluetoothNotAvailable

        // Transmit queue is full
        case failToUpdateCharacteristic

        case failToStartAdvertising(Error)
    }
}

@Observable
class BluetoothPeripheralManager: NSObject {

    var count: Int = 0 {
        didSet {
            // we still want to be able to update the value even when the bluetooth is not one, and
            // written failure will be re-tried in peripheralManagerIsReadyToUpdateSubscribers so we will not do anything here
            try? self.updateCharacteristicValue(value: count.data)
        }
    }

    // since CBCentral will not trigger any view updates,
    // we cannot use a calculated variable here.
    private(set) var subscribedCentralCount: Int = 0

    // CBCentral will not trigger any view updates
    private var subscribedCentrals: [CBCentral] = [] {
        didSet {
            self.subscribedCentralCount = self.subscribedCentrals.count
        }
    }

    var isAdvertising: Bool = false {
        didSet {
            do {
                isAdvertising ? try startAdvertising() : stopAdvertising()
            } catch (let error) {
                self.error = error
                self.isAdvertising = oldValue
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private(set) var error: Error? {
        didSet {
            if let error {
                print(error)
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 2.0,
                    execute: {
                        self.error = nil
                    }
                )
            }
        }
    }

    private(set) var bluetoothState: CBManagerState = .poweredOff
    private var peripheralManager: CBPeripheralManager?

    private var serviceAdded: Bool = false

    private var advertisementData: [String: Any] {
        var advertisementData: [String: Any] = [:]
        advertisementData[CBAdvertisementDataLocalNameKey] =
            BLEAccessory.name
        advertisementData[CBAdvertisementDataServiceUUIDsKey] = [
            BLEAccessory.serviceUUID
        ]
        return advertisementData
    }

    // cryptographic keys for decrypting forwarded notification payload
    private var keyMaterial: SecurityMessage.KeyMaterial? = nil
    private var publicKeyData: Data? = nil
    private var privateKeyData: Data? = nil
    private var keySharingDataChunks: Data = Data()

    private(set) var forwardedNotification: [AccessoryNotification] = []
    private var notificationDataChunks: Data = Data()

    override init() {
        super.init()
        self.peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [
                CBPeripheralManagerOptionShowPowerAlertKey: true
                    // to enable state restore with delegate function peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any])
                    // this will requires background mode
                    // CBPeripheralManagerOptionRestoreIdentifierKey: NSString(string: BLEAccessory.name)
            ]
        )
    }

    private func startAdvertising() throws {
        print(#function)

        guard let peripheralManager = self.peripheralManager else {
            throw BluetoothPeripheralError.managerNotInitialized
        }

        guard self.bluetoothState == .poweredOn else {
            throw BluetoothPeripheralError.bluetoothNotAvailable
        }

        self.addService()
        peripheralManager.startAdvertising(advertisementData)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func stopAdvertising() {
        print(#function)

        guard self.bluetoothState == .poweredOn else {
            return
        }

        peripheralManager?.stopAdvertising()
        // if we want other device to not be able to discover our services without us advertising,
        // uncomment the following line.
        // peripheralManager?.removeAllServices()

        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func addService() {
        guard self.bluetoothState == .poweredOn else { return }
        if !self.serviceAdded {
            peripheralManager?.add(BLEAccessory.service)
            self.serviceAdded = true
        }
    }

    private func updateCharacteristicValue(value: Data) throws {
        print(#function)
        guard self.bluetoothState == .poweredOn else {
            throw BluetoothPeripheralError.bluetoothNotAvailable
        }

        guard let peripheralManager = self.peripheralManager else {
            throw BluetoothPeripheralError.managerNotInitialized
        }

        guard
            peripheralManager.updateValue(
                value,
                for: BLEAccessory.counterCharacteristic,
                onSubscribedCentrals: nil
            )
        else {
            // underlying transmit queue is full
            // will retry automatically in peripheralManagerIsReadyToUpdateSubscribers
            throw BluetoothPeripheralError.failToUpdateCharacteristic
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
// Additional delegation methods:
// - to monitor subscribed central: peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic)
// - to restore the previous state (such as subscribed added services and subscribed centrals): peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any])
extension BluetoothPeripheralManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print(#function)
        self.bluetoothState = peripheral.state
        self.addService()
    }

    func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager,
        error: (any Error)?
    ) {
        print(#function)
        if let error {
            self.error = BluetoothPeripheralError.failToStartAdvertising(error)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: (any Error)?
    ) {
        print(#function)
        if let error {
            self.isAdvertising = false
            self.error = BluetoothPeripheralError.failToStartAdvertising(error)
        }
    }

    // invoked after a failed call to updateValue:forCharacteristic:onSubscribedCentrals
    func peripheralManagerIsReady(
        toUpdateSubscribers peripheral: CBPeripheralManager
    ) {
        print(#function)
        do {
            try self.updateCharacteristicValue(value: self.count.data)
        } catch (let error) {
            self.error = error
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        willRestoreState dict: [String: Any]
    ) {
        let perviousServices =
            dict[CBPeripheralManagerRestoredStateServicesKey]
            as? [CBMutableService] ?? []

        let characteristics = perviousServices.map(\.characteristics).filter({
            $0 != nil
        }).flatMap({ $0! })
        let mutable = characteristics.map({ $0 as? CBMutableCharacteristic })
            .filter({ $0 != nil }).map({ $0! })
        self.subscribedCentrals = mutable.map(\.subscribedCentrals).filter({
            $0 != nil
        }).flatMap({ $0! })
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        if characteristic.uuid == BLEAccessory.counterCharacteristicUUID,
            !self.subscribedCentrals.contains(where: {
                $0.identifier == central.identifier
            })
        {
            self.subscribedCentrals.append(central)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        if characteristic.uuid == BLEAccessory.counterCharacteristicUUID {
            self.subscribedCentrals.removeAll(where: {
                $0.identifier == central.identifier
            })
        }
    }

    // invoked when Central made a read request
    // to have central receive the value of the characteristic, it need to be set using request.value
    // otherwise, central will not receive any update on the value of the characteristic in peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?)
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        switch request.characteristic.uuid {
        case BLEAccessory.counterCharacteristicUUID:
            request.value = self.count.data
        default:
            break
        }

        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        print(#function)
        guard !requests.isEmpty else { return }

        var data = Data()
        var isStart: Bool = false
        var isEnd: Bool = false

        for request in requests {
            guard var requestValue = request.value else { continue }
            requestValue = requestValue.dropFirst(request.offset)
            if requestValue == chunkDataStater {
                isStart = true
                continue
            }
            if requestValue == chunkDataTerminator {
                isEnd = true
                break
            }
            data.append(requestValue)
        }

        switch requests.first?.characteristic.uuid {

        case BLEAccessory.counterCharacteristicUUID:
            if let value = Int.fromData(data) {
                // setting the `count` will call `updateCharacteristicValue` automatically
                // so that other subscribed centrals (other than the one sends the request) will also receive the update
                self.count = value
            }
        case BLEAccessory.notificationCharacteristicUUID:
            logger.info("writing to the notification")
            handleWriteToNotificationCharacteristic(
                isStart: isStart,
                isEnd: isEnd,
                data: data
            )

        case BLEAccessory.keySharingCharacteristicUUID:
            logger.info("sharing key")
            handleWriteToKeySharingCharacteristic(
                isStart: isStart,
                isEnd: isEnd,
                data: data
            )

        default:
            break
        }

        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }
}

// MARK: - Notification Forwarding Handling helpers
extension BluetoothPeripheralManager {
    // receive keys from AccessoryTransportSecurity
    private func handleWriteToKeySharingCharacteristic(
        isStart: Bool,
        isEnd: Bool,
        data: Data
    ) {
        let result = String(data: data, encoding: .utf8)
        print(result as Any, "isStart: \(isStart), isEnd: \(isEnd)")

        if isStart {
            self.keySharingDataChunks = Data()
        }

        if !data.isEmpty {
            self.keySharingDataChunks.append(data)
        }

        if !isEnd {
            return
        }

        do {
            let result = String(
                data: self.keySharingDataChunks,
                encoding: .utf8
            )
            print(result as Any, "isStart: \(isStart), isEnd: \(isEnd)")

            let decoder = JSONDecoder()
            let shareKeyEvent = try decoder.decode(
                ShareKeyEvent.self,
                from: self.keySharingDataChunks
            )
            print(shareKeyEvent)
            self.keyMaterial = shareKeyEvent.keyMaterial
            self.privateKeyData = shareKeyEvent.privateKeyData
            self.publicKeyData = shareKeyEvent.publicKeyData

        } catch (let error) {
            logger.error("\(error.localizedDescription)")
        }
    }

    // receive encrypted notifications from AccessoryTransportAppExtension
    private func handleWriteToNotificationCharacteristic(
        isStart: Bool,
        isEnd: Bool,
        data: Data
    ) {
        let result = String(data: data, encoding: .utf8)
        print(result as Any, "isStart: \(isStart), isEnd: \(isEnd)")

        if isStart {
            self.notificationDataChunks = Data()
        }

        if !data.isEmpty {
            self.notificationDataChunks.append(data)
        }

        if !isEnd {
            return
        }

        do {
            let result = String(
                data: self.notificationDataChunks,
                encoding: .utf8
            )
            print(result as Any, "isStart: \(isStart), isEnd: \(isEnd)")

            let decoder = JSONDecoder()
            let notification = try decoder.decode(
                NotificationEvent.self,
                from: self.notificationDataChunks
            )
            try self.decryptNotificationData(
                notification.encryptedData,
                sessionId: notification.sessionId
            )
        } catch (let error) {
            logger.error("\(error.localizedDescription)")
        }
    }

    private func decryptNotificationData(_ encryptedData: Data, sessionId: UUID)
        throws
    {
        guard let keyMaterial, let publicKeyData, let privateKeyData else {
            return
        }
        let ciphersuite = keyMaterial.ciphersuite.description  // The value is "XWing" or "P256".
        let version = keyMaterial.version.description  // Always "v1".
        let identifier = keyMaterial.identifier  // The device's UUID.
        let protocolInfo = "\(ciphersuite)-\(version)-\(identifier)"

        // Create an HPKE receiver from the accessory’s private key and protocol information
        let publicKey = try XWingMLKEM768X25519.PublicKey(
            rawRepresentation: publicKeyData
        )
        let privateKey = try XWingMLKEM768X25519.PrivateKey(
            seedRepresentation: privateKeyData,
            publicKey: publicKey
        )

        let recipient = try HPKE.Recipient(
            privateKey: privateKey,
            ciphersuite: .XWingMLKEM768X25519_SHA256_AES_GCM_256,
            info: Data(protocolInfo.utf8),
            encapsulatedKey: keyMaterial.encapsulatedKey
        )

        let context = Data("\(protocolInfo)-HostToAccessory-\(sessionId)".utf8)
        let secret = try recipient.exportSecret(
            context: context,
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let plaintext = try AES.GCM.open(sealedBox, using: secret)

        let decoder = JSONDecoder()
        let notification = try decoder.decode(
            NotificationPayLoad.self,
            from: plaintext
        )
        logger.info("Notification received.")
        print(notification)
        self.updateNotifications(with: notification)
    }

    private func updateNotifications(with payload: NotificationPayLoad) {
        switch payload {
        case .add(let notification, _):
            self.forwardedNotification.append(notification)
        case .update(let notification):
            if let firstIndex = self.forwardedNotification.firstIndex(where: {
                $0.identifier == notification.identifier
            }) {
                self.forwardedNotification[firstIndex] = notification
            }
        case .remove(let identifier):
            self.forwardedNotification.removeAll(where: {
                $0.identifier == identifier
            })
        case .removeAll:
            self.forwardedNotification = []
        }
    }
}
