import SwiftUI

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @State var currMessage: String = ""

    init() {
        UITableView.appearance().separatorStyle = .none
        UITableView.appearance().tableFooterView = UIView()
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(viewModel.messages, id: \.self) { message in
                        MessageView(message: message).flip()
                    }
                }.flip().onTapGesture {
                        self.endEditing(true)
                }
                HStack {
                    TextField("Message...", text: $currMessage, onCommit: {
                        self.sendMessage()
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(minHeight: CGFloat(30))
                    Button(action: sendMessage) {
                        Text("Send")
                    }
                }.frame(minHeight: CGFloat(50)).padding()
            }.navigationBarTitle(Text("\(viewModel.activeUsers.count) Participants"), displayMode: .inline)
            .padding(.bottom, viewModel.currentKeyboardHeight)
            .edgesIgnoringSafeArea(viewModel.currentKeyboardHeight == 0.0 ? .leading: .bottom)
                .alert(isPresented: $viewModel.hasError) {
                    Alert(title: Text("Error"), message: Text(viewModel.errorMessage ?? "There was a problem executing request, please try again!"), dismissButton: .default(Text("OK")))
            }
        }
    }

    func sendMessage() {
        guard !currMessage.isEmpty else { return }
        viewModel.sendMessage(currMessage)
        currMessage = ""
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView().environmentObject(ChatViewModel(service: MultipeerComunicationService()))
    }
}
