import SwiftUI

struct MessageView : View {
    var message: Message
    var body: some View {
        HStack(alignment: .bottom, spacing: 25) {
            if !message.isFromMe {
                Spacer()
            }
            VStack(alignment: message.isFromMe ? .leading : .trailing, spacing: 5) {
                Text(message.message)
                .padding(10)
                .foregroundColor(message.isFromMe ? Color.white : Color.black)
                .background(message.isFromMe ? Color.blue : Color(UIColor(red: 240/255, green: 240/255, blue: 240/255, alpha: 1.0)))
                .cornerRadius(10)
                Text((message.user ?? "Anonimous").capitalized)
                    .foregroundColor(message.isFromMe ? Color.blue : Color.black)
                .font(.footnote)
            }
            if message.isFromMe {
                Spacer()
            }
        }
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        MessageView(message: Message(message: "Just some long text so i can test the way this message will get displayed", user: "Andrei", isFromMe: true))
    }
}
