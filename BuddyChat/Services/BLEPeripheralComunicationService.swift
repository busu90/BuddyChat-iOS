import Foundation
import CoreBluetooth
import UIKit

final class BLEPeripheralComunicationService: NSObject, ComunicationService {
    static let serviceUUID = CBUUID(string: "01675e60-68b6-421b-8928-eabe5aab121a")
    static let characteristicUUID = CBUUID(string: "c5bb8525-086b-4637-b4cb-b92f9d992d82")
    static let eomId = "EOM"
    
    private var manager: CBPeripheralManager!

    private let serialQueue = DispatchQueue(label: "peripheral.serial.queue")

    private var transferCharacteristic: CBMutableCharacteristic?
    private var connectedCentrals: [CBCentral] = []
    private var incommingMsgs: [CBCentral: Data] = [:]
    private var outgoingMsgs: [Data] = []
    private var sendDataIndex: Int = 0

    private weak var delegate : ComunicationServiceDelegate?
    private var readyToStart = false

    override init() {
        super.init()
        self.manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    deinit {
        stop()
    }

    func stop(){
        self.manager.stopAdvertising()
    }

    func start(with delegate: ComunicationServiceDelegate) {
        self.delegate = delegate
        if readyToStart {
            startAdvertising()
        }
        readyToStart = true
    }

    func sendMessage(_ message: String) -> Result<Bool, Error> {
        guard !message.isEmpty else { return .failure(CustomError(description: NSLocalizedString("Cannot send empty message!", comment: ""))) }
        guard !connectedCentrals.isEmpty, transferCharacteristic != nil else { return .failure(CustomError(description: NSLocalizedString("No users connected yet!", comment: "")))}
        var toSend = "Anonimous,\(message)"
        if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            toSend = "\(uuid),\(message)"
        }
        addMessageToQueue(toSend.data(using: .utf8)!)
        return .success(true)
    }

    private func addMessageToQueue(_ message: Data) {
        serialQueue.async { [weak self] in
            self?.outgoingMsgs.append(message)
            self?.sendData()
        }
    }

    private func startAdvertising() {
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLEPeripheralComunicationService.serviceUUID]])
    }

    private func sendData() {
        serialQueue.async { [weak self] in
            guard let transferCharacteristic = self?.transferCharacteristic, let connectedCentrals = self?.connectedCentrals, !connectedCentrals.isEmpty else { return }

            while true {
                guard let messages = self?.outgoingMsgs, !messages.isEmpty else { return }
                //if message is empty send end of message flag
                if messages[0].isEmpty {
                    let didSend = self?.manager.updateValue(BLEPeripheralComunicationService.eomId.data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil) ?? false
                    if didSend {
                        self?.outgoingMsgs.removeFirst()
                        continue
                    } else {
                        return
                    }
                }

                // Work out how big it should be
                let amountToSend = min(messages[0].count, connectedCentrals[0].maximumUpdateValueLength)

                // Copy out the data we want
                let chunk = messages[0].subdata(in: 0..<amountToSend)

                // Send it
                let didSend = self?.manager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil) ?? false
                // update the reminder
                if didSend {
                    self?.outgoingMsgs[0] = messages[0].subdata(in: amountToSend..<messages[0].count)
                } else {
                    return
                }
            }
        }
    }
}

extension BLEPeripheralComunicationService : CBPeripheralManagerDelegate {
    private func setupPeripheral() {
        let transferCharacteristic = CBMutableCharacteristic(type: BLEPeripheralComunicationService.characteristicUUID,
                                                         properties: [.notify, .writeWithoutResponse],
                                                         value: nil,
                                                         permissions: [.readable, .writeable])

        // Create a service from the characteristic.
        let transferService = CBMutableService(type: BLEPeripheralComunicationService.serviceUUID, primary: true)

        // Add the characteristic to the service.
        transferService.characteristics = [transferCharacteristic]

        // And add it to the peripheral manager.
        manager.add(transferService)

        // Save the characteristic for later.
        self.transferCharacteristic = transferCharacteristic

    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            setupPeripheral()
            if readyToStart {
                startAdvertising()
            }
            readyToStart = true
        default:
            NSLog("State is: \(peripheral.state)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard !connectedCentrals.contains(central) else { return }
        connectedCentrals.append(central)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if let index = connectedCentrals.firstIndex(of: central) {
            connectedCentrals.remove(at: index)
        }
    }

    /*
    *  This callback comes in when the PeripheralManager is ready to send the next chunk of data.
    *  This is to ensure that packets will arrive in the order they are sent
    */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            guard let requestValue = aRequest.value,
                let stringFromData = String(data: requestValue, encoding: .utf8) else { continue }
            var data = incommingMsgs[aRequest.central] ?? Data()
            if stringFromData == BLEPeripheralComunicationService.eomId {
                let message = Message(data, userId: UIDevice.current.identifierForVendor?.uuidString)
                DispatchQueue.main.async() {
                    self.delegate?.didRecieveMessage(message)
                }
                incommingMsgs.removeValue(forKey: aRequest.central)
                addMessageToQueue(data)
            } else {
                data.append(requestValue)
                incommingMsgs[aRequest.central] = data
            }
        }
        peripheral.respond(to: requests[0], withResult: .success)
    }
}

