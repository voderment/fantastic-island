import SwiftUI

@main
struct IslandApp: App {
    @StateObject private var model = IslandAppModel()

    var body: some Scene {
        Settings {
            IslandSettingsView(model: model)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    model.openSettings()
                } label: {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
