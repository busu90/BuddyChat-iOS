import Foundation

protocol ComunicationServiceDelegate: class {
    func didRecieveMessage(_ message: Message)
    func activeUsersChanged(_ connectedDevices: [String])
}

protocol ComunicationService {
    func start(with delegate: ComunicationServiceDelegate)
    func sendMessage(_ message: String) -> Result<Bool, Error>
}
