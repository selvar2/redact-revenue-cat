import SwiftUI

@main
struct RedactApp: App {

    init() {
        // RevenueCat configuration lands here in Phase 3 (F10). It is the only networking permitted
        // anywhere in this app — see CLAUDE.md rule 1 and docs/memory/decisions/DEC-004-no-network.md.
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
