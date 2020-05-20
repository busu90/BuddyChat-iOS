import Foundation
import CoreBluetooth

final class BLECentralComunicationService: NSObject, ComunicationService {
    private var manager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var transferCharacteristic: CBCharacteristic?

    private var data = Data()
    private var dataToSend = Data()
    private var sendDataIndex: Int = 0
    private var sendingEOM = false

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
        dataToSend = message.data(using: .utf8)!
        sendDataIndex = 0
        writeData()
        return .success(true)
    }

    private func writeData() {

        guard let discoveredPeripheral = discoveredPeripheral,
                let transferCharacteristic = transferCharacteristic
            else { return }

        if sendDataIndex >= dataToSend.count && !sendingEOM {
            // No data left.  Do nothing
            return
        }
        // There's data left, so send until we have to stop
        while discoveredPeripheral.canSendWriteWithoutResponse {
            if sendDataIndex >= dataToSend.count {
                discoveredPeripheral.writeValue("EOM".data(using: .utf8)!, for: transferCharacteristic, type: .withoutResponse)
                sendingEOM = false
                return
            }

            // Work out how big it should be
            var amountToSend = dataToSend.count - sendDataIndex
            amountToSend = min(amountToSend, discoveredPeripheral.maximumWriteValueLength (for: .withoutResponse))

            // Copy out the data we want
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))

            // Send it
            discoveredPeripheral.writeValue(chunk, for: transferCharacteristic, type: .withoutResponse)

            // It did send, so update our index
            sendDataIndex += amountToSend
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // No data left.  Do nothing
                sendingEOM = true
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

        data.removeAll(keepingCapacity: false)

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
        if stringFromData == "EOM" {
            let message = String(data: self.data, encoding: .utf8) ?? ""
            DispatchQueue.main.async() {
                self.delegate?.didRecieveMessage(Message(message: message, user: nil, isFromMe: false))
            }
            data.removeAll(keepingCapacity: false)
        } else {
            data.append(characteristicData)
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

