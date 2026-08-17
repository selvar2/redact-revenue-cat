import SwiftUI

/// Maps an ``AppRoute`` onto the view that shows it.
///
/// Every `navigationDestination` and every coordinator-driven sheet in the app resolves through
/// this one switch. Keeping it in a single small file is deliberate: it is the only place where
/// app-level wiring names a feature type, so when a feature renames its entry view there is exactly
/// one line to change, and a reviewer can see the app's entire destination surface at a glance.
///
/// Each case is a feature's *entry view* and nothing else — no layout, no state, no decisions. If
/// something here starts needing a condition, that condition belongs in ``AppCoordinator``.
struct RouteDestination: View {

    let route: AppRoute

    /// The app-wide entitlement store, handed to the paywall so that purchases and the app's
    /// `isPro` are one state machine rather than two. Optional for the same reason `ProAccess` is:
    /// a build that forgot the root injection must degrade, not trap.
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?

    /// Used only if the environment has no store — never in the shipping app, where `RootView`
    /// installs one. Held in `@State` so the paywall is not handed a new store on every rebuild.
    @State private var fallbackEntitlements = EntitlementStore()

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .scan:
            // Scan draws no title of its own; every other destination below does, and a second
            // title applied here is what put the Library's large title on top of its search field.
            ScanView()
                .navigationTitle(route.accessibilityTitle)
                .navigationBarTitleDisplayMode(.inline)
        case .editor(let session):
            EditorView(session: session)
        case .export(let session):
            ExportView(session: session)
        case .library:
            LibraryView()
        case .documentDetail(let id):
            DocumentDetailView(documentID: id)
        case .paywall(let context):
            RedactPaywallView(context: context, entitlements: entitlements ?? fallbackEntitlements)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
