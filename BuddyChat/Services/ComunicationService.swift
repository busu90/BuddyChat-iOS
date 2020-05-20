import Foundation

protocol ComunicationServiceDelegate: class {
    func didRecieveMessage(_ message: Message)
    func activeUsersChanged(_ connectedDevices: [String])
}

protocol ComunicationService: NSObject {
    func start(with delegate: ComunicationServiceDelegate)
    func stop()
    func sendMessage(_ message: String) -> Result<Bool, Error>
}
