import SwiftUI

@main
struct TH80BarApp: App {
    @State private var model = KeyboardModel()
    @State private var editor = EditorModel()
    @State private var keymap = KeymapModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
                .environment(\.locale, Locale(identifier: "pt_BR"))
        } label: {
            Image(systemName: model.connected ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Window("Desenhar para o TH80", id: "editor") {
            EditorView(editor: editor, keyboard: model)
                .environment(\.locale, Locale(identifier: "pt_BR"))
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 720)

        Window("Teclas do TH80", id: "keymap") {
            KeymapView(model: keymap)
                .environment(\.locale, Locale(identifier: "pt_BR"))
        }
        .windowResizability(.contentMinSize)
    }
}
