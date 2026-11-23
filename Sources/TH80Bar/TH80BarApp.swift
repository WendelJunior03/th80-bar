import SwiftUI

@main
struct TH80BarApp: App {
    @State private var model = KeyboardModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
                .environment(\.locale, Locale(identifier: "pt_BR"))
        } label: {
            Image(systemName: model.connected ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}
