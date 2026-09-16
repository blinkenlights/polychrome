import AppKit
import SwiftUI

@main
struct EarApp: App {
    @State private var model = AppModel()

    init() {
        // Started as a bare executable (`swift run`) the process is not an app
        // yet: no Dock icon, no key window.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        Window("Ear", id: "ear") {
            HStack(spacing: 0) {
                RingView(model: model)
                    .frame(minWidth: 480, minHeight: 480)
                Divider()
                ControlsView(model: model)
                    .frame(width: 320)
            }
            .task { await model.boot() }
        }
        .defaultSize(width: 1120, height: 780)
    }
}
