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

    var body: some View {
        content
            .navigationTitle(route.accessibilityTitle)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .scan:
            ScanView()
        case .editor(let session):
            EditorView(session: session)
        case .export(let session):
            ExportView(session: session)
        case .library:
            LibraryView()
        case .documentDetail(let id):
            DocumentDetailView(documentID: id)
        case .paywall:
            // Phase 3 (`feature-paywall`) replaces this single line with the purchase screen.
            // Until then the seam leads somewhere real rather than to an empty sheet — see
            // ``FreeTierNoticeView``.
            FreeTierNoticeView()
        }
    }
}
