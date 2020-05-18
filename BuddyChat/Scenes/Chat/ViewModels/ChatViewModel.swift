import Foundation
import Combine
import SwiftUI

class ChatViewModel : ObservableObject {
    @Published private(set) var currentKeyboardHeight: CGFloat = 0
    @Published private(set) var messages: [Message] = []
    @Published private(set) var activeUsers: [String] = [] 
    private(set) var errorMessage: String? = nil {
        didSet {
            hasError = true
        }
    }
    @Published var hasError = false

    private var service: ComunicationService
    private var notificationCenter: NotificationCenter

    init(service: ComunicationService, center: NotificationCenter = .default) {
        self.service = service
        notificationCenter = center
        notificationCenter.addObserver(self, selector: #selector(keyBoardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(keyBoardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        service.start(with: self)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @objc func keyBoardWillShow(notification: Notification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            currentKeyboardHeight = keyboardSize.height
        }
    }

    @objc func keyBoardWillHide(notification: Notification) {
        currentKeyboardHeight = 0
    }

    func sendMessage(_ message: String) {
        switch service.sendMessage(message) {
        case .success:
            messages.insert(Message(message: message, user: "Me", isFromMe: true), at: 0)
        case .failure(let error):
            self.errorMessage = error.localizedDescription
        }
    }
}

extension ChatViewModel: ComunicationServiceDelegate {
    func didRecieveMessage(_ message: Message) {
        messages.insert(message, at: 0)
    }

    func activeUsersChanged(_ connectedDevices: [String]) {
        activeUsers.removeAll()
        activeUsers.append(contentsOf: connectedDevices)
    }
}
