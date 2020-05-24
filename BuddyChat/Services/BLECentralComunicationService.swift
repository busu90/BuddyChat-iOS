import Foundation
import CoreBluetooth
import UIKit

final class BLECentralComunicationService: NSObject, ComunicationService {
    private var manager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var transferCharacteristic: CBCharacteristic?

    private var incommingMsg = Data()
    private var outgoingMsgs: [Data] = []

    private let serialQueue = DispatchQueue(label: "central.serial.queue")

    private weak var delegate : ComunicationServiceDelegate?
    private var readyToStart = false

    override init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }

    deinit {
       stop()
    }

    func start(with delegate: ComunicationServiceDelegate) {
        self.delegate = delegate
        if readyToStart {
            startScan()
        }
        readyToStart = true
    }

    func stop() {
        self.manager.stopScan()
        cleanup()
    }

    func sendMessage(_ message: String) -> Result<Bool, Error> {
        guard !message.isEmpty else { return .failure(CustomError(description: NSLocalizedString("Cannot send empty message!", comment: ""))) }
        guard discoveredPeripheral != nil && transferCharacteristic != nil else { return .failure(CustomError(description: NSLocalizedString("Did not connect to a chat yet!", comment: ""))) }
        var toSend = "Anonimous,\(message)"
        if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            toSend = "\(uuid),\(message)"
        }
        serialQueue.async { [weak self] in
            self?.outgoingMsgs.append(toSend.data(using: .utf8)!)
            self?.writeData()
        }
        return .success(false)
    }

    private func writeData() {
        serialQueue.async { [weak self] in
            guard let discoveredPeripheral = self?.discoveredPeripheral, let transferCharacteristic = self?.transferCharacteristic else { return }
            while discoveredPeripheral.canSendWriteWithoutResponse {
                guard let messages = self?.outgoingMsgs, !messages.isEmpty else { return }
                //if message is empty send end of message flag
                if messages[0].isEmpty {
                    discoveredPeripheral.writeValue(BLEPeripheralComunicationService.eomId.data(using: .utf8)!, for: transferCharacteristic, type: .withoutResponse)
                    self?.outgoingMsgs.removeFirst()
                    continue
                }

                // Work out how big it should be
                let amountToSend = min(messages[0].count, discoveredPeripheral.maximumWriteValueLength (for: .withoutResponse))

                // Copy out the data we want
                let chunk = messages[0].subdata(in: 0..<amountToSend)

                // update the reminder
                self?.outgoingMsgs[0] = messages[0].subdata(in: amountToSend..<messages[0].count)

                // Send it
                discoveredPeripheral.writeValue(chunk, for: transferCharacteristic, type: .withoutResponse)
            }
        }
    }

    private func startScan() {
        let connectedPeripherals: [CBPeripheral] = (manager.retrieveConnectedPeripherals(withServices: [BLEPeripheralComunicationService.serviceUUID]))
        if let connectedPeripheral = connectedPeripherals.last {
            self.discoveredPeripheral = connectedPeripheral
            manager.connect(connectedPeripheral, options: nil)
        } else {
            manager.scanForPeripherals(withServices: [BLEPeripheralComunicationService.serviceUUID],
                                               options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
}

extension BLECentralComunicationService : CBCentralManagerDelegate {
    private func cleanup() {
        guard let discoveredPeripheral = discoveredPeripheral, case .connected = discoveredPeripheral.state else { return }

        for service in (discoveredPeripheral.services ?? [] as [CBService]) {
            for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                if characteristic.uuid == BLEPeripheralComunicationService.characteristicUUID && characteristic.isNotifying {
                    // It is notifying, so unsubscribe
                    self.discoveredPeripheral?.setNotifyValue(false, for: characteristic)
                }
            }
        }

        // If we've gotten this far, we're connected, but we're not subscribed, so we just disconnect
        manager.cancelPeripheralConnection(discoveredPeripheral)

    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if readyToStart {
                startScan()
            }
            readyToStart = true
        default:
            NSLog("State is: \(central.state)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
            manager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cleanup()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        manager.stopScan()

        peripheral.delegate = self

        peripheral.discoverServices([BLEPeripheralComunicationService.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        startScan()
    }
}

extension BLECentralComunicationService : CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices where service.uuid == BLEPeripheralComunicationService.serviceUUID {
            peripheral.discoverServices([BLEPeripheralComunicationService.serviceUUID])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            cleanup()
            return
        }

        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([BLEPeripheralComunicationService.characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            cleanup()
            return
        }

        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics where characteristic.uuid == BLEPeripheralComunicationService.characteristicUUID {
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if  error != nil {
            cleanup()
            return
        }

        guard let characteristicData = characteristic.value, let stringFromData = String(data: characteristicData, encoding: .utf8) else { return }

        // Have we received the end-of-message token?
        if stringFromData == BLEPeripheralComunicationService.eomId {
            let message = Message(incommingMsg, userId: UIDevice.current.identifierForVendor?.uuidString)
            DispatchQueue.main.async() {
                self.delegate?.didRecieveMessage(message)
            }
            self.incommingMsg.removeAll(keepingCapacity: false)
        } else {
            self.incommingMsg.append(characteristicData)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            return
        }

        guard characteristic.uuid == BLEPeripheralComunicationService.characteristicUUID else { return }

        if !characteristic.isNotifying {
            cleanup()
        }

    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        writeData()
    }
}

