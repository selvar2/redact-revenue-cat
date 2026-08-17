import SwiftUI
import UIKit

/// The last screen before the document leaves the app.
///
/// Three things it must get right:
///
/// 1. **The preview is the output.** It shows bytes that came back from `RedactionEngine`, not the
///    source with rectangles drawn over it. If those two ever disagreed, the version the user
///    inspected would be the one that is not shipped.
/// 2. **The limits are stated, once, as facts.** What the free tier exports and what Pro adds are
///    written plainly next to the format choice. No countdown, no nagging, no interstitial.
/// 3. **Inherited marks are surfaced before export, not after.** See ``AnnotationAudit``.
@MainActor
struct ExportView: View {

    let session: RedactionSession

    /// Forces a tier instead of reading the entitlement. Previews and tests only — the app's own
    /// navigation constructs this view with the session alone, so the real answer always comes from
    /// ``ProAccess``.
    var tierOverride: ExportPipeline.Tier? = nil

    init(session: RedactionSession, tierOverride: ExportPipeline.Tier? = nil) {
        self.session = session
        self.tierOverride = tierOverride
    }

    /// The live entitlement. See ``ProAccess``: `nil` store resolves to the free tier.
    private var proAccess = ProAccess()

    /// What the user may actually export as.
    private var tier: ExportPipeline.Tier { tierOverride ?? proAccess.exportTier }

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibleAnimation) private var accessibleAnimation
    @Environment(\.modelContext) private var modelContext

    @State private var format: ExportPipeline.Format = .png
    @State private var previewImage: UIImage?
    @State private var previewFailure: String?

    @State private var markupReport: AnnotationAudit.Report = .clean
    @State private var showingMarkupSheet = false
    @State private var pagesToFlatten: Set<Int> = []
    @State private var markupDecisionMade = false

    @State private var progress: ExportPipeline.Progress?
    @State private var artifact: ExportPipeline.Artifact?
    @State private var failure: ExportFailure?

    private var usage: UsageTracker { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.md) {
                preview
                summary
                formatChoice
                planFacts
                if !exportedMarkupReport.isEmpty { markupNotice }
                actions
            }
            .padding(Token.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AmbientBackground(intensity: .subdued).ignoresSafeArea())
        .navigationTitle(Text("Export", comment: "Navigation title of the export screen"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        // The entitlement can change while this screen is open — the paywall is a sheet over it, so
        // a purchase lands here. Re-coerce the selection so the picker can never be left showing a
        // format the current tier would refuse at export time.
        .onChange(of: tier) { _, _ in
            let available = ExportPipeline.availableFormats(for: session.source, tier: tier)
            if !available.contains(format), let first = available.first {
                format = first
            }
        }
        .sheet(isPresented: $showingMarkupSheet) {
            InsecureMarkupSheet(report: exportedMarkupReport, pages: session.pages) { chosen in
                pagesToFlatten = chosen
                markupDecisionMade = true
                Task { await export() }
            }
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { failure in
            if failure.offersPro {
                Button(String(localized: "See Redact Pro", comment: "Alert button opening the subscription screen")) {
                    coordinator.presentPaywall(failure.paywallContext)
                }
                Button(String(localized: "Not now", comment: "Alert button dismissing the Pro suggestion"), role: .cancel) {}
            } else {
                Button(String(localized: "OK", comment: "Alert button dismissing an export error"), role: .cancel) {}
            }
        } message: { failure in
            Text(failure.message)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            SectionHeader(
                String(localized: "This is what you will send", comment: "Heading above the redacted export preview"),
                overline: String(localized: "Preview", comment: "Overline above the export preview"),
                subtitle: String(localized: "The bars below are burned into the picture. There is nothing underneath them to recover.",
                                 comment: "Subtitle explaining that the preview shows destroyed content")
            ) { EmptyView() }

            Group {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(Text("Redacted page \(session.currentPageIndex + 1)",
                                                 comment: "VoiceOver label for the redacted preview image"))
                } else if let previewFailure {
                    VStack(alignment: .leading, spacing: Token.Space.sm) {
                        Text(previewFailure)
                            .typeStyle(Typography.body)
                            .foregroundStyle(Token.Text.primary)
                        SecondaryButton(String(localized: "Try again", comment: "Button that rebuilds the export preview"),
                                        prominence: .plain) {
                            Task { await buildPreview() }
                        }
                    }
                    .padding(Token.Space.md)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: Token.Size.minimumHitTarget * 3)
                        .accessibilityLabel(Text("Preparing the preview", comment: "VoiceOver label while the preview renders"))
                }
            }
            .glassCard(padding: nil)
        }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: Token.Space.sm) {
            Pill(
                String(localized: "\(session.activeRedactionCount) removed", comment: "Pill: how many pieces of information are being destroyed"),
                systemImage: "eye.slash.fill",
                style: .success,
                accessibilityLabel: String(localized: "\(session.activeRedactionCount) pieces of information will be removed permanently",
                                           comment: "VoiceOver label for the redaction count pill")
            )
            Pill(
                pageCountLabel,
                systemImage: "doc.on.doc",
                style: .neutral
            )
            Spacer()
        }
    }

    /// Inflected so a one-page document reads "1 page", not "1 pages". Automatic grammar agreement
    /// does the same job for every localisation, which a hand-written `if count == 1` does not.
    private var pageCountLabel: String {
        String(AttributedString(
            localized: "^[\(session.pages.count) pages](inflect: true)",
            comment: "Pill: page count of the document"
        ).characters)
    }

    // MARK: - Format

    private var formatChoice: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            SectionHeader(String(localized: "Format", comment: "Heading above the export format picker")) { EmptyView() }

            Picker(selection: formatSelection) {
                ForEach(ExportPipeline.offerableFormats(for: session.source)) { option in
                    Text(isLocked(option) ? option.lockedDisplayName : option.displayName)
                        .tag(option)
                }
            } label: {
                Text("Export format", comment: "Accessibility label of the export format picker")
            }
            .pickerStyle(.segmented)
            .frame(minHeight: Token.Size.minimumHitTarget)

            Text(formatExplanation)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: Token.Layout.proseWidth, alignment: .leading)

            ForEach(lockedFormats) { locked in
                lockedFormatNotice(locked)
            }
        }
        .glassCard()
    }

    private var lockedFormats: [ExportPipeline.Format] {
        ExportPipeline.lockedFormats(for: session.source, tier: tier)
    }

    private func isLocked(_ format: ExportPipeline.Format) -> Bool {
        lockedFormats.contains(format)
    }

    /// The picker's selection, with the Pro segments intercepted.
    ///
    /// A locked segment is shown and tappable on purpose. Hiding it means the user never learns the
    /// app can do this; disabling it means they learn only that something is off-limits, with no
    /// reason and nowhere to go. Tapping it explains what the format is and opens the subscription
    /// screen, and `format` is left alone so the segmented control snaps back to what will actually
    /// be exported — the screen never claims a state the export cannot deliver.
    private var formatSelection: Binding<ExportPipeline.Format> {
        Binding(
            get: { format },
            set: { chosen in
                guard !isLocked(chosen) else {
                    coordinator.presentPaywall(.pdfExport)
                    return
                }
                format = chosen
            }
        )
    }

    /// States, in the open, exactly what the locked format is and what it costs to have it.
    private func lockedFormatNotice(_ locked: ExportPipeline.Format) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.xs) {
            Text(lockedFormatExplanation(locked))
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(
                String(localized: "Unlock \(locked.displayName) export",
                       comment: "Button opening the subscription screen from a locked export format; parameter is the format name"),
                systemImage: "sparkles",
                prominence: .plain
            ) {
                coordinator.presentPaywall(.pdfExport)
            }
            .accessibilityHint(Text("Opens the Redact Pro subscription screen",
                                    comment: "VoiceOver hint on the button that unlocks a Pro export format"))
        }
        .frame(maxWidth: Token.Layout.proseWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func lockedFormatExplanation(_ locked: ExportPipeline.Format) -> String {
        switch locked {
        case .pdf:
            return String(
                localized: "\(locked.displayName) export saves all \(session.pages.count) pages as one document and is part of Redact Pro. The free tier saves one page at a time as a picture, redacted just as thoroughly.",
                comment: "Explains why the PDF export option is unavailable on the free tier"
            )
        case .png:
            // Unreachable today — PNG is on every tier. Written as a real sentence rather than a
            // fatalError so a future tier change degrades to an honest string, not a crash.
            return String(
                localized: "\(locked.displayName) export is part of Redact Pro.",
                comment: "Explains that an export format is unavailable on the free tier"
            )
        }
    }

    private var formatExplanation: String {
        switch format {
        case .png:
            return String(
                localized: "Page \(session.currentPageIndex + 1) of \(session.pages.count) is saved as a picture.",
                comment: "Explains that PNG export covers a single page; parameters are the page number and the total"
            )
        case .pdf:
            return String(
                localized: "All \(session.pages.count) pages are saved as one document. Pages you redacted become pictures; the rest keep their selectable writing.",
                comment: "Explains what a PDF export contains"
            )
        }
    }

    // MARK: - Plan facts

    /// What each tier does, stated once. No urgency, no countdown, no dark pattern — the free tier
    /// is a real product and this screen says so.
    private var planFacts: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            if tier.isPro {
                Text("Pro: every page, as one document, as often as you like.",
                     comment: "Plan summary shown to a Pro subscriber on the export screen")
                    .typeStyle(Typography.callout)
                    .foregroundStyle(Token.Text.muted)
            } else if usage.remainingFreeDocuments > 0 {
                Text("Free covers one page at a time, saved as a picture — \(usage.remainingFreeDocuments) of \(UsageTracker.freeMonthlyAllowance) left this month. Pro saves every page as one document with no monthly limit.",
                     comment: "Plan summary shown to a free user on the export screen")
                    .typeStyle(Typography.callout)
                    .foregroundStyle(Token.Text.muted)
            } else {
                // Said here, before the Export button is pressed, and with the date attached. The
                // limit is not a dead end — it is a wait with a known end, or a purchase.
                Text("You have used all \(UsageTracker.freeMonthlyAllowance) free documents this month. They come back on \(usage.nextResetDate.formatted(date: .abbreviated, time: .omitted)). Pro removes the monthly limit.",
                     comment: "Plan summary shown to a free user whose monthly quota is spent; parameter is the reset date")
                    .typeStyle(Typography.callout)
                    .foregroundStyle(Token.Text.muted)
            }

            // Suppressed when the format card is already showing an "Unlock PDF export" button —
            // two buttons to the same screen, a thumb's width apart, is nagging.
            if !tier.isPro && lockedFormats.isEmpty {
                SecondaryButton(String(localized: "See what Pro includes", comment: "Button opening the subscription screen from export"),
                                prominence: .plain) {
                    // The wall this user is actually at: the quota, once it is spent; otherwise
                    // they are browsing, and quota copy would be simply untrue.
                    coordinator.presentPaywall(usage.remainingFreeDocuments > 0 ? .general : .monthlyLimit)
                }
                .accessibilityHint(Text("Opens the Redact Pro subscription screen",
                                        comment: "VoiceOver hint on the button that opens the subscription screen"))
            }
        }
        .frame(maxWidth: Token.Layout.proseWidth, alignment: .leading)
        .glassCard()
    }

    // MARK: - Markup notice

    /// Shown when the audit found marks on the source that are covering real text.
    ///
    /// It states the finding and the current decision. Once the user has chosen, the copy reports
    /// what will happen — it never says the file is clean, because on the "leave as is" path it is
    /// not, and claiming otherwise would be the exact lie this whole feature exists to prevent.
    private var markupNotice: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            SectionHeader(
                String(localized: "This file came in with marks on it", comment: "Heading of the inherited-markup notice on the export screen"),
                overline: String(localized: "Check", comment: "Overline of the inherited-markup notice")
            ) { EmptyView() }

            Text(markupNoticeBody)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: Token.Layout.proseWidth, alignment: .leading)

            SecondaryButton(String(localized: "Review the marks", comment: "Button reopening the inherited-markup sheet"),
                            systemImage: "eye.trianglebadge.exclamationmark") {
                showingMarkupSheet = true
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
    }

    /// The audit narrowed to the pages **this format will actually write**.
    ///
    /// `AnnotationAudit` deliberately scans every page, including ones the user is not redacting.
    /// A PNG export writes exactly one page. Offering to make page 3's inherited mark permanent
    /// during a single-page PNG export asks the user to decide about a page that will not be in the
    /// output, and then tells them it was handled — the source PDF is untouched either way. That is
    /// a false reassurance about a leaking page, which is worse than saying nothing.
    private var exportedMarkupReport: AnnotationAudit.Report {
        switch format {
        case .pdf:
            return markupReport
        case .png:
            let page = session.currentPageIndex
            return AnnotationAudit.Report(
                findings: markupReport.findings.filter { $0.pageIndex == page },
                benignMarkupPageIndices: markupReport.benignMarkupPageIndices.filter { $0 == page }
            )
        }
    }

    private var markupNoticeBody: String {
        let pageList = exportedMarkupReport.flaggedPageIndices
            .map { String($0 + 1) }
            .formatted(.list(type: .and))

        guard markupDecisionMade else {
            return String(
                localized: "Something is drawn over the writing on \(pageList). Redact will ask what to do with it before exporting.",
                comment: "Inherited-markup notice before the user has decided; parameter is a list of page numbers"
            )
        }
        // Intersected, not taken as chosen: switching from PDF to PNG after deciding narrows what
        // the export writes, and naming a page that is no longer in the output would tell the user
        // a leaking page was handled when it was not even exported.
        let flagged = Set(exportedMarkupReport.flaggedPageIndices)
        let flattening = pagesToFlatten.intersection(flagged).sorted()

        if flattening.isEmpty {
            return String(
                localized: "You chose to send \(pageList) as they are. What is drawn on them can still be removed by whoever opens the file.",
                comment: "Inherited-markup notice after the user chose to leave the marks in place"
            )
        }
        let chosen = flattening.map { String($0 + 1) }.formatted(.list(type: .and))
        return String(
            localized: "\(chosen) will be made permanent, so nothing on them can be lifted off.",
            comment: "Inherited-markup notice after the user chose to bake the marks in"
        )
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if let artifact {
            VStack(spacing: Token.Space.sm) {
                ShareLink(item: artifact.fileURL) {
                    Text("Share the safe copy", comment: "Share button on the export screen")
                        .typeStyle(Typography.label)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Token.Size.minimumHitTarget)
                        .padding(.horizontal, Token.Space.md)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel(Text("Share the redacted file", comment: "VoiceOver label for the share button"))

                SecondaryButton(String(localized: "Done", comment: "Button that finishes export and opens the saved document")) {
                    coordinator.finish(savedDocumentID: artifact.documentID)
                }

                Text("Saved to your library. The original stayed on this device and was never uploaded.",
                     comment: "Confirmation shown after a successful export")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .frame(maxWidth: Token.Layout.proseWidth, alignment: .leading)
            }
            .accessibleAnimation(Motion.gentle, value: artifact.documentID)
        } else {
            VStack(spacing: Token.Space.sm) {
                PrimaryButton(
                    String(localized: "Export", comment: "Primary button that runs the export"),
                    systemImage: "square.and.arrow.up",
                    isLoading: progress != nil
                ) {
                    Task { await beginExport() }
                }

                if let progress {
                    ProgressView(value: progress.fraction) {
                        Text(progress.stage.description)
                            .typeStyle(Typography.caption)
                            .foregroundStyle(Token.Text.muted)
                    }
                    .tint(Token.Accent.violet)
                    .accessibilityLabel(Text(progress.stage.description))
                }
            }
        }
    }

    // MARK: - Work

    private func prepare() async {
        await buildPreview()
        await auditSourceMarkup()
        if let first = ExportPipeline.availableFormats(for: session.source, tier: tier).first {
            format = first
        }
    }

    private func buildPreview() async {
        previewFailure = nil
        previewImage = nil
        let index = session.currentPageIndex
        guard let page = session.pages.first(where: { $0.index == index }) else { return }
        let regions = session.activeRegions(onPage: index)
        do {
            let data = try await ExportPipeline.previewImageData(pageData: page.imageData, regions: regions)
            previewImage = UIImage(data: data)
            if previewImage == nil { previewFailure = previewUnavailable }
        } catch {
            previewFailure = previewUnavailable
        }
    }

    private var previewUnavailable: String {
        String(localized: "The preview could not be drawn. Exporting still works, and it uses the same code that draws this preview.",
               comment: "Message shown when the export preview fails to render")
    }

    /// Scans the source PDF for marks another tool left behind.
    ///
    /// A failure here is not fatal and is not silent: the report stays empty, the export proceeds,
    /// and no copy anywhere claims the file was checked.
    private func auditSourceMarkup() async {
        guard session.source.isPDF else { return }
        let data = session.source.data
        markupReport = await Task.detached(priority: .utility) {
            (try? AnnotationAudit.audit(pdfData: data)) ?? .clean
        }.value
    }

    private func beginExport() async {
        if !exportedMarkupReport.isEmpty && !markupDecisionMade {
            showingMarkupSheet = true
            return
        }
        await export()
    }

    private func export() async {
        guard progress == nil else { return }
        progress = ExportPipeline.Progress(stage: .preparing)
        defer { progress = nil }

        do {
            artifact = try await ExportPipeline.run(
                session: session,
                format: format,
                tier: tier,
                pagesToFlatten: pagesToFlatten,
                store: DocumentStore(context: modelContext),
                usage: usage
            ) { update in
                withAnimation(accessibleAnimation(Motion.standard)) { progress = update }
            }
        } catch is CancellationError {
            // A cancelled export leaves no file, no record and no quota spent. Nothing to report.
        } catch {
            failure = ExportFailure(error: error)
        }
    }
}

// MARK: - Failure presentation

/// An export failure, in the shape an alert wants.
///
/// Every failure carries a way forward — App Review's "no screen can dead-end" rule, and simple
/// decency at the moment a user's document did not come out.
private struct ExportFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let offersPro: Bool

    /// Which wall the user met, so the subscription screen opens saying the right thing.
    let paywallContext: PaywallContext

    init(error: any Error) {
        let localized = error as? any LocalizedError
        title = localized?.errorDescription
            ?? String(localized: "The export did not finish.", comment: "Generic export failure title")
        message = localized?.recoverySuggestion
            ?? String(localized: "Nothing was saved and nothing left this device. Try again.",
                      comment: "Generic export failure message")

        switch error {
        case ExportPipeline.ExportError.freeAllowanceSpent:
            offersPro = true
            paywallContext = .monthlyLimit
        case ExportPipeline.ExportError.formatRequiresPro:
            offersPro = true
            paywallContext = .pdfExport
        default:
            offersPro = false
            paywallContext = .general
        }
    }
}

#Preview("Export — free") {
    NavigationStack {
        ExportView(session: RedactionSession(source: .image(Data()), title: "Bank statement"),
                   tierOverride: .free)
            .environment(AppCoordinator())
    }
    .preferredColorScheme(.dark)
}

#Preview("Export — Pro") {
    NavigationStack {
        ExportView(session: RedactionSession(source: .image(Data()), title: "Bank statement"),
                   tierOverride: .pro)
            .environment(AppCoordinator())
    }
    .preferredColorScheme(.dark)
}
