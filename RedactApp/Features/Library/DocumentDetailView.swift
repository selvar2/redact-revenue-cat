import SwiftUI

/// One saved document: the redacted result at full size, what it is, how to share it
/// again, the Pro audit log, and how to destroy it.
///
/// Everything shown here is *post*-redaction. There is no path from this screen back
/// to the original bytes, because there is no original — `RedactionEngine` destroyed
/// it at export and the source was never persisted (`CLAUDE.md` rule 2).
struct DocumentDetailView: View {

    let documentID: UUID

    init(documentID: UUID) {
        self.documentID = documentID
    }

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppEnvironment.self) private var appEnvironment
    /// The audit log is Pro. Read from the entitlement layer rather than from an environment flag
    /// somebody has to remember to inject — see ``ProAccess`` and
    /// `docs/memory/gotchas/library-pro-access-seam.md`, which this replaces.
    private var proAccess = ProAccess()
    private var isPro: Bool { proAccess.isPro }

    @State private var detail: DocumentDetail?
    @State private var pageIndex = 0
    @State private var isConfirmingDelete = false
    @State private var loadFailed = false
    @State private var deletionFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: Token.Space.md) {
                if let detail {
                    preview(for: detail)
                    facts(for: detail)
                    auditSection(for: detail)
                    destructiveActions(for: detail)
                } else if loadFailed {
                    missingDocument
                } else {
                    ProgressView()
                        .tint(Token.Accent.violetLight)
                        .padding(.top, Token.Space.xl)
                        .accessibilityLabel("Opening the document")
                }
            }
            .padding(.horizontal, Token.Space.md)
            .padding(.bottom, Token.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground(.subdued)
        .navigationTitle(detail?.title ?? AppRoute.documentDetail(id: documentID).accessibilityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail, !detail.shareURLs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(items: detail.shareURLs) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the redacted document")
                    .accessibilityHint("Sends the redacted pages. The original was destroyed and is not included.")
                }
            }
        }
        .task(id: documentID) {
            load()
        }
        .confirmationDialog(
            "Delete this document?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The redacted pages are erased from this device. This cannot be undone.")
        }
    }

    // MARK: - Loading

    private func load() {
        do {
            guard let document = try appEnvironment.store.document(id: documentID) else {
                loadFailed = true
                detail = nil
                return
            }
            detail = DocumentDetail(document, vault: .shared)
            pageIndex = min(pageIndex, max(0, (detail?.pagePaths.count ?? 1) - 1))
            loadFailed = false
        } catch {
            loadFailed = true
            detail = nil
        }
    }

    private func performDelete() {
        do {
            guard let document = try appEnvironment.store.document(id: documentID) else {
                // Already gone. Leaving is the correct outcome either way.
                coordinator.pop()
                return
            }
            try appEnvironment.store.delete(document)
            ThumbnailLoader.shared.evictAll()
            coordinator.pop()
        } catch {
            deletionFailed = true
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private func preview(for detail: DocumentDetail) -> some View {
        VStack(spacing: Token.Space.sm) {
            VaultImage(
                key: detail.previewCacheKey(page: pageIndex),
                relativePath: detail.pagePaths.indices.contains(pageIndex)
                    ? detail.pagePaths[pageIndex]
                    : detail.thumbnailPath,
                maxPixel: LibraryLayout.detailPreviewPixels,
                fallbackSymbol: detail.sourceKind.symbolName,
                accessibilityLabelText: detail.previewAccessibilityLabel(page: pageIndex)
            )
            .aspectRatio(LibraryLayout.pageAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))

            if detail.pagePaths.count > 1 {
                pageStepper(pageCount: detail.pagePaths.count)
            }
        }
        .glassCard(padding: Token.Space.sm)
    }

    /// A stepper rather than a swipeable pager: two 44pt buttons are operable by
    /// VoiceOver, Switch Control and Voice Control without a gesture, and a page
    /// count of two or three does not justify a carousel.
    private func pageStepper(pageCount: Int) -> some View {
        HStack(spacing: Token.Space.sm) {
            Button {
                pageIndex = max(0, pageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: Token.Size.minimumHitTarget, height: Token.Size.minimumHitTarget)
            }
            .disabled(pageIndex == 0)
            .accessibilityLabel("Previous page")

            Text("Page \(pageIndex + 1) of \(pageCount)")
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)

            Button {
                pageIndex = min(pageCount - 1, pageIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: Token.Size.minimumHitTarget, height: Token.Size.minimumHitTarget)
            }
            .disabled(pageIndex == pageCount - 1)
            .accessibilityLabel("Next page")
        }
        .foregroundStyle(Token.Text.primary)
        .accessibleAnimation(Motion.snappy, value: pageIndex)
    }

    // MARK: - Facts

    private func facts(for detail: DocumentDetail) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            SectionHeader(
                String(localized: "About this document"),
                overline: String(localized: "Saved")
            )

            factRow(label: String(localized: "Created"), value: detail.createdLabel)
            factRow(label: String(localized: "Source"), value: detail.sourceKind.displayName)
            factRow(label: String(localized: "Pages"), value: "\(detail.pageCount)")
            factRow(label: String(localized: "Items removed"), value: "\(detail.redactionCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func factRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
            Spacer(minLength: Token.Space.sm)
            Text(value)
                .typeStyle(Typography.bodyEmphasis)
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Audit log

    @ViewBuilder
    private func auditSection(for detail: DocumentDetail) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            SectionHeader(
                String(localized: "Redaction audit log"),
                overline: String(localized: "Pro"),
                subtitle: String(localized: "What was removed, and where. Never what it said.")
            ) {
                if !isPro {
                    Pill(String(localized: "Pro"), systemImage: "lock.fill", style: .accent)
                }
            }

            if isPro {
                if detail.auditEntries.isEmpty {
                    // Almost always a document redacted before subscribing: the records are written
                    // at export time and there is nothing to reconstruct them from afterwards,
                    // because the removed information no longer exists anywhere. Saying so beats an
                    // empty list that reads like the feature is broken.
                    Text("No log was kept for this document. Records are written while a document is being redacted, and this one was redacted before Pro was active.")
                        .typeStyle(Typography.callout)
                        .foregroundStyle(Token.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(detail.auditEntries) { entry in
                        auditRow(entry)
                    }
                }
            } else {
                lockedAuditLog(entryCount: detail.redactionCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func auditRow(_ entry: AuditEntry) -> some View {
        HStack(spacing: Token.Space.sm) {
            IconWell(entry.symbolName, tint: .gradient)

            VStack(alignment: .leading, spacing: Token.Space.xs / 2) {
                Text(entry.kindLabel)
                    .typeStyle(Typography.bodyEmphasis)
                    .foregroundStyle(Token.Text.primary)
                Text("\(entry.pageLabel) · \(entry.timeLabel)")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Token.Size.minimumHitTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    /// The free-tier state.
    ///
    /// Factual, not nagging: it says what the log is and what it costs nothing to
    /// know — the count, which the user can already see above — and offers one way
    /// forward. No countdown, no "upgrade now!", no repeated interruption. It is also
    /// not a dead button: `presentPaywall()` is wired from Phase 2 onward.
    private func lockedAuditLog(entryCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            // Two literals rather than a ternary inside `Text`: a ternary collapses to a
            // plain `String`, which `Text` does not localise. Each branch here stays a
            // `LocalizedStringKey`.
            Group {
                if entryCount == 1 {
                    Text("One item was removed from this document. Redact Pro keeps a per-item log of what kind it was and which page it came from.")
                } else {
                    Text("\(entryCount) items were removed from this document. Redact Pro keeps a per-item log of what kind each one was and which page it came from.")
                }
            }
            .typeStyle(Typography.callout)
            .foregroundStyle(Token.Text.muted)
            .fixedSize(horizontal: false, vertical: true)

            Text("The log never stores the information itself — only its category, page, and time.")
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .fixedSize(horizontal: false, vertical: true)

            // The honest limit, stated before the button rather than discovered after paying.
            Text("Records are written as a document is redacted, so the log starts with the next document you redact — it cannot be filled in for this one.")
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(String(localized: "See what Pro includes"), systemImage: "sparkles") {
                coordinator.presentPaywall(.auditLog)
            }
            .accessibilityHint("Opens the Redact Pro subscription screen")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Destructive

    private func destructiveActions(for detail: DocumentDetail) -> some View {
        VStack(spacing: Token.Space.sm) {
            if deletionFailed {
                Text("This document could not be deleted. Nothing was removed.")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Accent.amberLight)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            SecondaryButton(
                String(localized: "Delete document"),
                systemImage: "trash",
                role: .destructive
            ) {
                isConfirmingDelete = true
            }
            .accessibilityHint("Erases the redacted pages from this device")

            Text("Deleting erases the redacted pages from this device. Redact keeps no copy anywhere else.")
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Token.Layout.proseWidth)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Token.Space.sm)
    }

    /// Reached when the record is gone — most often because it was deleted on the
    /// library screen while this one was still on the stack.
    private var missingDocument: some View {
        VStack(spacing: Token.Space.md) {
            IconWell("tray", size: Token.Size.mark, tint: .muted)

            Text("This document is no longer here")
                .typeStyle(Typography.title)
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.center)

            Text("It was deleted, along with its files.")
                .typeStyle(Typography.body)
                .foregroundStyle(Token.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Token.Layout.proseWidth)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(String(localized: "Back to your documents")) {
                coordinator.pop()
            }
            .frame(maxWidth: Token.Layout.proseWidth)
        }
        .padding(.top, Token.Space.xl)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Snapshot

/// Value snapshot of a document plus its audit trail.
///
/// Same reasoning as ``DocumentSummary``: the view never holds a live `@Model`. Here
/// it matters twice over, because reading `auditTrail` faults the whole relationship
/// and the detail screen is the one place that legitimately wants it.
struct DocumentDetail {

    let id: UUID
    let title: String
    let createdAt: Date
    let sourceKind: DocumentSourceKind
    let pageCount: Int
    let redactionCount: Int
    let thumbnailPath: String?
    let pagePaths: [String]
    let auditEntries: [AuditEntry]
    /// Absolute vault URLs for `ShareLink`. Only files that resolve inside the vault
    /// and actually exist — sharing a dangling URL presents an empty share sheet.
    let shareURLs: [URL]

    var createdLabel: String {
        createdAt.formatted(date: .long, time: .shortened)
    }

    func previewCacheKey(page: Int) -> String { "detail.\(id.uuidString).\(page)" }

    func previewAccessibilityLabel(page: Int) -> String {
        pagePaths.count > 1
            ? String(localized: "Redacted page \(page + 1) of \(pagePaths.count) of \(title)",
                     comment: "VoiceOver: the page preview on the document detail screen")
            : String(localized: "The redacted \(title)",
                     comment: "VoiceOver: the single-page preview on the document detail screen")
    }

    @MainActor
    init(_ document: RedactedDocument, vault: FileVault) {
        self.id = document.id
        self.title = document.title
        self.createdAt = document.createdAt
        self.sourceKind = document.sourceKind
        self.pageCount = document.pageCount
        self.redactionCount = document.redactionCount
        self.thumbnailPath = document.thumbnailPath
        self.pagePaths = document.pagePaths
        self.auditEntries = document.auditTrail
            .sorted { ($0.pageIndex, $0.redactedAt) < ($1.pageIndex, $1.redactedAt) }
            .map(AuditEntry.init)
        self.shareURLs = document.pagePaths.compactMap { path in
            guard vault.fileExists(atRelativePath: path) else { return nil }
            return try? vault.url(forRelativePath: path)
        }
    }
}

// MARK: - Preview

@MainActor
private func documentDetailPreviewFixture() -> (AppEnvironment, UUID) {
    let appEnvironment = AppEnvironment()
    let document = RedactedDocument(
        title: "Salary slip",
        sourceKind: .scan,
        pageCount: 1,
        redactionCount: 3
    )
    try? appEnvironment.store.insert(document)
    return (appEnvironment, document.id)
}

#Preview("Document detail") {
    let (appEnvironment, documentID) = documentDetailPreviewFixture()

    NavigationStack {
        DocumentDetailView(documentID: documentID)
    }
    .environment(appEnvironment)
    .environment(AppCoordinator())
    .preferredColorScheme(.dark)
}
