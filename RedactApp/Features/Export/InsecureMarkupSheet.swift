import SwiftUI
import UIKit

/// The warning shown **before** export when the source PDF already carries marks that are covering
/// real text.
///
/// The whole point is plain language. The user does not need to know what an annotation is, what
/// flattening means, or that PDF has a layer model — they need to know that someone can peel the
/// black box off page two and read what is under it, and they need two obvious buttons. So this
/// screen contains no jargon by rule: not "flatten", not "rasterise", not "annotation", not "layer".
///
/// It also never claims the choice they did not make was wrong. Leaving the marks as they are is a
/// legitimate decision — it is their document — and the copy says what happens either way without
/// pushing.
@MainActor
struct InsecureMarkupSheet: View {

    /// What the audit found. Only pages that are actually hiding text reach this screen.
    let report: AnnotationAudit.Report
    /// Rendered pages, for the thumbnails. Indexed by ``SessionPage/index``.
    let pages: [SessionPage]

    /// Called with the pages the user chose to make permanent. An empty set means "leave as is",
    /// which is a completed decision, not a cancellation.
    let onDecide: (Set<Int>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibleAnimation) private var accessibleAnimation

    @State private var selection: Set<Int> = []

    private var isMultiPage: Bool { report.findings.count > 1 }
    private var allSelected: Bool { selection.count == report.findings.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Token.Space.md) {
                    header
                    if isMultiPage { applyToAllRow }
                    ForEach(report.findings) { finding in
                        pageRow(finding)
                    }
                    choiceExplanation
                    actions
                }
                .padding(Token.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AmbientBackground(intensity: .subdued).ignoresSafeArea())
            .navigationTitle(Text("Before you export", comment: "Title of the sheet warning about existing marks on a PDF"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Pre-selected, because the safe option should be the default one — but every row is a
            // switch the user can turn off, so nothing is decided for them silently.
            selection = Set(report.flaggedPageIndices)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            IconWell("exclamationmark.triangle.fill", tint: .gradient)
            Text(headline)
                .typeStyle(Typography.title)
                .foregroundStyle(Token.Text.primary)
            Text("Someone could remove it and read what is underneath. Redact did not put it there — it was already in the file you brought in.",
                 comment: "Explanation under the insecure-markup warning headline")
                .typeStyle(Typography.body)
                .foregroundStyle(Token.Text.muted)
                .frame(maxWidth: Token.Layout.proseWidth, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var headline: String {
        guard let first = report.findings.first else {
            return String(localized: "This file already has something drawn on it.",
                          comment: "Insecure-markup headline when no page detail is available")
        }
        if report.findings.count == 1 {
            return String(
                localized: "Page \(first.pageIndex + 1) already has \(first.primaryMarkType.plainName) drawn over the writing.",
                comment: "Insecure-markup headline for one affected page; parameters are the page number and a plain-language mark name"
            )
        }
        return String(
            localized: "\(report.findings.count) pages already have something drawn over the writing.",
            comment: "Insecure-markup headline for several affected pages"
        )
    }

    // MARK: - Rows

    private var applyToAllRow: some View {
        Toggle(isOn: Binding(
            get: { allSelected },
            set: { isOn in
                withAnimation(accessibleAnimation(Motion.snappy)) {
                    selection = isOn ? Set(report.flaggedPageIndices) : []
                }
            }
        )) {
            Text("Make every page permanent", comment: "Toggle that selects every affected page at once")
                .typeStyle(Typography.bodyEmphasis)
                .foregroundStyle(Token.Text.primary)
        }
        .tint(Token.Accent.violet)
        .frame(minHeight: Token.Size.minimumHitTarget)
        .glassCard(padding: Token.Space.sm)
        .accessibilityHint(Text("Applies your choice to all listed pages.", comment: "VoiceOver hint for the apply-to-all toggle"))
    }

    private func pageRow(_ finding: AnnotationAudit.Finding) -> some View {
        HStack(alignment: .top, spacing: Token.Space.sm) {
            PageMarkThumbnail(
                page: pages.first { $0.index == finding.pageIndex },
                markRects: finding.markRects
            )

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text(rowTitle(finding))
                    .typeStyle(Typography.bodyEmphasis)
                    .foregroundStyle(Token.Text.primary)
                Text(rowDetail(finding))
                    .typeStyle(Typography.callout)
                    .foregroundStyle(Token.Text.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { selection.contains(finding.pageIndex) },
                set: { isOn in
                    withAnimation(accessibleAnimation(Motion.snappy)) {
                        if isOn { selection.insert(finding.pageIndex) } else { selection.remove(finding.pageIndex) }
                    }
                }
            ))
            .labelsHidden()
            .tint(Token.Accent.violet)
            .frame(minWidth: Token.Size.minimumHitTarget, minHeight: Token.Size.minimumHitTarget)
            .accessibilityLabel(Text("Make page \(finding.pageIndex + 1) permanent", comment: "VoiceOver label for the per-page make-permanent switch"))
        }
        .glassCard(padding: Token.Space.sm)
        .accessibilityElement(children: .contain)
    }

    private func rowTitle(_ finding: AnnotationAudit.Finding) -> String {
        String(
            localized: "Page \(finding.pageIndex + 1)",
            comment: "Row title in the insecure-markup list; parameter is a page number"
        )
    }

    private func rowDetail(_ finding: AnnotationAudit.Finding) -> String {
        String(
            localized: "There is \(finding.primaryMarkType.plainName) here with real writing under it.",
            comment: "Row detail describing what is covering text on a page; parameter is a plain-language mark name"
        )
    }

    // MARK: - Explanation

    private var choiceExplanation: some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            explanation(
                symbol: "lock.fill",
                title: String(localized: "Make permanent", comment: "Name of the make-permanent choice"),
                body: String(
                    localized: "Redact turns the pages you picked into flat pictures, so nothing on them can be lifted off. You will not be able to select or search the writing on those pages afterwards.",
                    comment: "What happens if the user makes the marked pages permanent"
                )
            )
            explanation(
                symbol: "arrow.right.circle",
                title: String(localized: "Leave as is", comment: "Name of the leave-as-is choice"),
                body: String(
                    localized: "The pages go out exactly as they came in. Whatever was already drawn on them can still be removed by whoever opens the file.",
                    comment: "What happens if the user leaves the marked pages untouched"
                )
            )
        }
    }

    private func explanation(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Token.Space.sm) {
            IconWell(symbol, size: Token.Space.lg, tint: .muted)
            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text(title)
                    .typeStyle(Typography.bodyEmphasis)
                    .foregroundStyle(Token.Text.primary)
                Text(body)
                    .typeStyle(Typography.callout)
                    .foregroundStyle(Token.Text.muted)
            }
        }
        .glassCard(padding: Token.Space.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Token.Space.sm) {
            PrimaryButton(makePermanentTitle, systemImage: "lock.fill") {
                onDecide(selection)
                dismiss()
            }
            .disabled(selection.isEmpty)

            SecondaryButton(String(localized: "Leave as is", comment: "Button: export without changing the existing marks")) {
                onDecide([])
                dismiss()
            }
        }
        .padding(.top, Token.Space.sm)
    }

    private var makePermanentTitle: String {
        selection.count > 1
            ? String(localized: "Make \(selection.count) pages permanent", comment: "Button: bake the marks into several pages")
            : String(localized: "Make permanent", comment: "Button: bake the marks into the page")
    }
}

// MARK: - Thumbnail

/// A small picture of the affected page with the covering marks outlined.
///
/// Showing the page matters: "page 2" is an abstraction, and the user may well not remember what is
/// on page 2 of a document they scanned an hour ago. Seeing the black box is what makes the warning
/// land.
@MainActor
private struct PageMarkThumbnail: View {

    let page: SessionPage?
    /// Normalised, top-left origin. Already flipped by ``AnnotationAudit`` — nothing here converts
    /// coordinates, and nothing here may start.
    let markRects: [CGRect]

    @State private var image: UIImage?

    /// Scaled so the thumbnail keeps pace with the text beside it: at accessibility sizes a fixed
    /// 72pt tile sits next to three wrapped lines and the row stops reading as one thing.
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = Token.Size.thumbnailSmall

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay(markOverlay)
            } else {
                RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                    .fill(Token.BG.raised)
                    .aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                .strokeBorder(Token.Line.strong, lineWidth: Token.Size.hairlineWidth)
        )
        // The picture repeats what the adjacent text already says, and VoiceOver users get that
        // text. A second description of the same thing is noise.
        .accessibilityHidden(true)
        .task(id: page?.index) {
            guard let page else { return }
            image = page.image()
        }
    }

    private var aspectRatio: CGFloat {
        guard let size = page?.pixelSize, size.height > 0 else { return 0.75 }
        return size.width / size.height
    }

    private var markOverlay: some View {
        GeometryReader { proxy in
            ForEach(Array(markRects.enumerated()), id: \.offset) { _, rect in
                let frame = CGRect(
                    x: rect.minX * proxy.size.width,
                    y: rect.minY * proxy.size.height,
                    width: rect.width * proxy.size.width,
                    height: rect.height * proxy.size.height
                )
                Rectangle()
                    .strokeBorder(Token.Accent.amber, lineWidth: Token.Size.hairlineWidth)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}

#Preview("Insecure markup") {
    InsecureMarkupSheet(
        report: AnnotationAudit.Report(
            findings: [
                AnnotationAudit.Finding(
                    pageIndex: 1,
                    markTypes: [.box],
                    hiddenCharacterCount: 42,
                    markRects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.06)]
                )
            ],
            benignMarkupPageIndices: []
        ),
        pages: [],
        onDecide: { _ in }
    )
    .preferredColorScheme(.dark)
}
