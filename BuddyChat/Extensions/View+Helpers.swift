import SwiftUI

extension View {
    func flip() -> some View {
        return self
               .rotationEffect(.radians(.pi))
               .scaleEffect(x: -1, y: 1, anchor: .center)
    }

    func endEditing(_ force: Bool) {
        UIApplication.shared.windows.forEach { $0.endEditing(force)}
    }
}
