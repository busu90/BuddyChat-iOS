import SwiftUI

struct ChatTypeView: View {
    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(destination: ChatView(ChatViewModel(service: MultipeerComunicationService()))) {
                    Text("Join iOS Only Chat")
                    }.padding()
                NavigationLink(destination: ChatView(ChatViewModel(service: BLEPeripheralComunicationService()))) {
                    Text("Start Cross Platform Chat")
                }.padding()
                NavigationLink(destination: ChatView(ChatViewModel(service: BLECentralComunicationService()))) {
                    Text("Join Cross Platform Chat")
                }.padding()
            }.navigationBarTitle(Text("BuddyChat"), displayMode: .inline)
        }
    }
}

struct ChatTypeView_Previews: PreviewProvider {
    static var previews: some View {
        ChatTypeView()
    }
}
