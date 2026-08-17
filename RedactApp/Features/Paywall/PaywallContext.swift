import Foundation

/// Why the paywall appeared.
///
/// A paywall that says "Upgrade to Pro" makes the user reconstruct what they were doing and why they
/// were stopped. Naming the wall they hit — the third document this month, PDF export, the audit log
/// — converts better and, more importantly, is honest: it tells them exactly which limit they met
/// and what buying removes.
///
/// It is also the seam for RevenueCat **Placements**: each case carries a stable identifier, so the
/// dashboard can serve a different offering at the export wall than at the quota wall without an app
/// update. Nothing here decides which offering to show; see ``PaywallExperiment``.
public enum PaywallContext: String, Sendable, CaseIterable, Identifiable {

    /// The free tier's three documents this month are spent.
    case monthlyLimit
    /// The user chose PDF export, which is a Pro format.
    case pdfExport
    /// The user opened the redaction audit log on a saved document.
    case auditLog
    /// Multi-page or batch redaction.
    case multiPage
    /// Custom detection rules.
    case customRules
    /// Opened deliberately — from About, or a "See what Pro includes" row.
    case general

    public var id: String { rawValue }

    /// The identifier a RevenueCat **Placement** is configured against in the dashboard.
    ///
    /// Stable and lower-cased: it is typed into the dashboard by a human, and renaming a Swift case
    /// must never silently detach a live placement from the screen it was configured for.
    var placementIdentifier: String { rawValue }

    /// Small line above the headline. Names the wall, not the product.
    var eyebrow: String {
        switch self {
        case .monthlyLimit:
            return String(localized: "Monthly limit reached", comment: "Paywall eyebrow: free quota spent")
        case .pdfExport:
            return String(localized: "PDF export", comment: "Paywall eyebrow: PDF export is a Pro format")
        case .auditLog:
            return String(localized: "Audit log", comment: "Paywall eyebrow: audit log is a Pro feature")
        case .multiPage:
            return String(localized: "Multi-page documents", comment: "Paywall eyebrow: multi-page is a Pro feature")
        case .customRules:
            return String(localized: "Custom rules", comment: "Paywall eyebrow: custom detection rules are Pro")
        case .general:
            return String(localized: "Redact Pro", comment: "Paywall eyebrow: opened deliberately")
        }
    }

    var headline: String {
        switch self {
        case .monthlyLimit:
            return String(localized: "You've used your three free documents", comment: "Paywall headline: quota spent")
        case .pdfExport:
            return String(localized: "Export as PDF with Pro", comment: "Paywall headline: PDF export")
        case .auditLog:
            return String(localized: "See exactly what was removed", comment: "Paywall headline: audit log")
        case .multiPage:
            return String(localized: "Redact every page at once", comment: "Paywall headline: multi-page")
        case .customRules:
            return String(localized: "Teach Redact what to look for", comment: "Paywall headline: custom rules")
        case .general:
            return String(localized: "Unlimited private redaction", comment: "Paywall headline: general")
        }
    }

    /// One sentence of context. Never a feature list — the plan card carries that.
    var message: String {
        switch self {
        case .monthlyLimit:
            return String(localized: "Free includes three documents a month. Pro removes the limit, and everything still happens on this device.", comment: "Paywall body: quota spent")
        case .pdfExport:
            return String(localized: "Free exports a single page as PNG. Pro writes multi-page PDFs with the original text destroyed, not covered.", comment: "Paywall body: PDF export")
        case .auditLog:
            return String(localized: "Pro keeps a per-document record of what was detected and what was destroyed, so you can prove a document was cleaned.", comment: "Paywall body: audit log")
        case .multiPage:
            return String(localized: "Free redacts the page you are looking at. Pro handles the whole document, and batches of them.", comment: "Paywall body: multi-page")
        case .customRules:
            return String(localized: "Pro lets you add your own patterns — client codes, case numbers, anything Redact should always remove.", comment: "Paywall body: custom rules")
        case .general:
            return String(localized: "Unlimited documents, multi-page PDF export, custom rules and the audit log. Still no account, still no network.", comment: "Paywall body: general")
        }
    }

    /// SF Symbol for the header mark. Decorative — the headline carries the meaning.
    var symbolName: String {
        switch self {
        case .monthlyLimit: return "calendar.badge.clock"
        case .pdfExport:    return "doc.richtext"
        case .auditLog:     return "list.bullet.rectangle"
        case .multiPage:    return "doc.on.doc"
        case .customRules:  return "slider.horizontal.3"
        case .general:      return "lock.shield"
        }
    }
}
