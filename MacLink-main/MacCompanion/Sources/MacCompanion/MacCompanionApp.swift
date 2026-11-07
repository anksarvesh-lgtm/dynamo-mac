// SPDX-License-Identifier: MIT
import SwiftUI
import MacCompanionKit

@main
struct MacCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            MainContainerView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 960, height: 640)
    }
}

