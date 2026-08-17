import Foundation
import Observation
import SwiftUI

// MARK: - Route

/// Every destination the app can push.
///
/// The editor and export routes carry the live ``RedactionSession`` rather than an identifier: the
/// session is unsaved, in-memory work, and there is nowhere to look it up from. Because it is a
/// reference type, `Hashable` here is *identity*, not value — pushing the same session twice is the
/// same route, and a route never goes stale when the session's contents change (which they do, on
/// every toggle).
///
/// Deliberately not `Codable`: state restoration would have to resurrect unsaved document bytes,
/// and a half-restored redaction session is worse than starting again. Finished work lives in
/// `DocumentStore` and is reachable through ``documentDetail(id:)``.
public enum AppRoute: Hashable {
    case scan
    case editor(RedactionSession)
    case export(RedactionSession)
    case library
    case documentDetail(id: UUID)
    /// Phase 3 fills this in. It is declared now so the free-tier limit check in Scan and Export
    /// has somewhere to send the user from day one, and so adding purchases never has to reshape
    /// navigation. Nothing in this file knows what a subscription is.
    case paywall

    public static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        switch (lhs, rhs) {
        case (.scan, .scan), (.library, .library), (.paywall, .paywall):
            return true
        case (.editor(let a), .editor(let b)), (.export(let a), .export(let b)):
            return a === b
        case (.documentDetail(let a), .documentDetail(let b)):
            return a == b
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .scan:    hasher.combine(0)
        case .library: hasher.combine(1)
        case .paywall: hasher.combine(2)
        case .editor(let session):
            hasher.combine(3)
            hasher.combine(ObjectIdentifier(session))
        case .export(let session):
            hasher.combine(4)
            hasher.combine(ObjectIdentifier(session))
        case .documentDetail(let id):
            hasher.combine(5)
            hasher.combine(id)
        }
    }

    /// VoiceOver-facing name of the destination, used for navigation-title accessibility and for
    /// announcing programmatic moves. Localised here so no feature invents its own wording.
    public var accessibilityTitle: String {
        switch self {
        case .scan:           return String(localized: "Scan a document", comment: "Navigation destination: the scan screen")
        case .editor:         return String(localized: "Review redactions", comment: "Navigation destination: the editor screen")
        case .export:         return String(localized: "Export", comment: "Navigation destination: the export screen")
        case .library:        return String(localized: "Library", comment: "Navigation destination: saved documents")
        case .documentDetail: return String(localized: "Document", comment: "Navigation destination: one saved document")
        case .paywall:        return String(localized: "Redact Pro", comment: "Navigation destination: the subscription screen")
        }
    }
}

// MARK: - Coordinator

/// Owns the navigation stack.
///
/// Navigation is a single typed array rather than a `NavigationPath`, so a mis-typed push is a
/// compile error and the whole stack can be read and asserted in a test. One coordinator is
/// injected into the environment by the root view; features never construct their own.
///
/// Features must not mutate ``path`` directly. Use the intent methods — they are the record of what
/// transitions the app actually supports, and they keep the paywall seam in one place.
@Observable
@MainActor
public final class AppCoordinator {

    /// Bind this to `NavigationStack(path:)`. Public for that binding only.
    public var path: [AppRoute] = []

    /// Presented over the stack rather than pushed. Phase 3 owns what this shows; until then
    /// nothing sets it, so nothing presents — no dead UI ships (CLAUDE.md rule 10).
    public var presentedSheet: AppRoute?

    public init() {}

    // MARK: Intents

    public func push(_ route: AppRoute) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    /// Moves from the editor to export.
    ///
    /// Replaces the editor entry instead of stacking on top of it: after exporting, "back" should
    /// return to the home screen, not to an editor whose session has already been consumed.
    public func showExport(for session: RedactionSession) {
        if case .editor = path.last {
            path[path.count - 1] = .export(session)
        } else {
            path.append(.export(session))
        }
    }

    /// Finishes a document: clears the working stack and shows it in the library.
    ///
    /// The session is intentionally dropped here — its source bytes are the *unredacted* original,
    /// and holding them after the safe copy is saved is a liability with no benefit.
    public func finish(savedDocumentID: UUID) {
        path = [.library, .documentDetail(id: savedDocumentID)]
    }

    // MARK: Paywall seam

    /// The one entry point to the subscription screen.
    ///
    /// Every quota check (`UsageTracker` says the free tier is spent) calls this and nothing else,
    /// so Phase 3 changes presentation in one place and no feature has to learn about RevenueCat.
    /// No purchase, entitlement, or SDK type appears in this file by design.
    public func presentPaywall() {
        presentedSheet = .paywall
    }

    public func dismissPaywall() {
        guard presentedSheet == .paywall else { return }
        presentedSheet = nil
    }
}

// MARK: - Environment
//
// The coordinator travels through SwiftUI's `@Observable` environment, not a custom
// `EnvironmentKey`. An `EnvironmentKey` would need a `nonisolated static var defaultValue`, and a
// `@MainActor` class cannot supply one without an `assumeIsolated` that is a latent crash. The
// Observable form has no default, which is also the honest model: there is exactly one coordinator,
// installed by the root view.
//
//     // root
//     .environment(coordinator)
//
//     // any feature view
//     @Environment(AppCoordinator.self) private var coordinator
//
// A preview that needs one writes `.environment(AppCoordinator())`.
