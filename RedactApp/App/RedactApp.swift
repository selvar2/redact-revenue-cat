import SwiftUI

@main
struct RedactApp: App {

    init() {
        // The only networking permitted anywhere in this app — see CLAUDE.md rule 1 and
        // docs/memory/decisions/DEC-004-no-network.md. Configuration must happen before any
        // `Purchases.shared` access, and it is cheap: the SDK does its first fetch asynchronously,
        // so this does not add a network round trip to launch.
        RevenueCatConfig.configure()
        //
        // Storage bring-up is *not* here. `AppEnvironment` opens the SwiftData container, and
        // `RootView` prepares the file vault and purges orphaned files from its `.task`, after the
        // first frame. Doing disk work in this initialiser delays the launch image for work that
        // nothing on the home screen needs.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Dark-only for v1 (DEC-002). Declared here as well as in the build settings so
                // SwiftUI previews match the shipped app.
                .preferredColorScheme(.dark)
        }
    }
}
