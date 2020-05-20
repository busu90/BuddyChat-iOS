import Foundation
import CoreBluetooth

final class BLEPeripheralComunicationService: NSObject, ComunicationService {
    static let serviceUUID = CBUUID(string: "01675e60-68b6-421b-8928-eabe5aab121a")
    static let characteristicUUID = CBUUID(string: "c5bb8525-086b-4637-b4cb-b92f9d992d82")
    private var manager: CBPeripheralManager!

    var transferCharacteristic: CBMutableCharacteristic?
    var connectedCentrals: [CBCentral] = []
    var datas: [CBCentral: Data] = [:]
    var dataToSend = Data()
    var sendDataIndex: Int = 0

    private weak var delegate : ComunicationServiceDelegate?
    private var readyToStart = false
    private var sendingEOM = false

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
        guard !connectedCentrals.isEmpty else { return .failure(CustomError(description: NSLocalizedString("No users connected yet!", comment: "")))}
        dataToSend = message.data(using: .utf8)!
        sendDataIndex = 0
        sendData()
        //delegate?.didRecieveMessage(Message(message: message, user: "ME", isFromMe: true))
        return .success(true)
    }

    private func startAdvertising() {
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLEPeripheralComunicationService.serviceUUID]])
    }

    private func sendData() {
        guard !connectedCentrals.isEmpty else { return }
        guard let transferCharacteristic = transferCharacteristic else {
            return
        }

        // First up, check if we're meant to be sending an EOM
        if sendingEOM {
            // send it
            let didSend = manager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                sendingEOM = false
            }
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }

        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if sendDataIndex >= dataToSend.count {
            // No data left.  Do nothing
            return
        }

        // There's data left, so send until the callback fails, or we're done.
        var didSend = true
        while didSend {

            // Work out how big it should be
            var amountToSend = dataToSend.count - sendDataIndex
            amountToSend = min(amountToSend, connectedCentrals[0].maximumUpdateValueLength)

            // Copy out the data we want
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))

            // Send it
            didSend = manager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)

            // If it didn't work, drop out and wait for the callback
            if !didSend {
                return
            }

            // It did send, so update our index
            sendDataIndex += amountToSend
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // It was - send an EOM

                // Set this so if the send fails, we'll send it next time
                sendingEOM = true

                //Send it
                let eomSent = manager.updateValue("EOM".data(using: .utf8)!,
                                                             for: transferCharacteristic, onSubscribedCentrals: nil)

                if eomSent {
                    // It sent; we're all done
                    sendingEOM = false
                }
                return
            }
        }
    }
}

extension BLEPeripheralComunicationService : CBPeripheralManagerDelegate {
    private func setupPeripheral() {

        // Build our service.

        // Start with the CBMutableCharacteristic.
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
            var data = datas[aRequest.central] ?? Data()
            if stringFromData == "EOM" {
                let message = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async() {
                    self.delegate?.didRecieveMessage(Message(message: message, user: nil, isFromMe: false))
                }
                datas.removeValue(forKey: aRequest.central)
            } else {
                data.append(requestValue)
                datas[aRequest.central] = data
            }
        }
    }
}

