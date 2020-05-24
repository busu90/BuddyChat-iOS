import Foundation

struct Message: Hashable {
    let message: String
    let user: String?
    let isFromMe: Bool

    init(_ data: Data, userId: String?) {
        let text = String(data: data, encoding: .utf8) ?? ""
        let separatorIndex = text.firstIndex(of: ",")
        if let separatorIndex = separatorIndex {
            let username = String(text[..<separatorIndex])
            message = String(text[text.index(separatorIndex, offsetBy: 1)...])
            user = userId == username ? "Me" : username
            isFromMe = userId == username
        } else {
            message = text
            user = nil
            isFromMe = false
        }
    }

    init(message: String, user: String?, isFromMe: Bool) {
        self.message = message
        self.user = user
        self.isFromMe = isFromMe
    }
}
