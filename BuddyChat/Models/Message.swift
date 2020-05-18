import Foundation

struct Message: Hashable {
    let message: String
    let user: String?
    let isFromMe: Bool
}
