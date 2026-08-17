import SwiftUI

/// Every detection on the document, grouped by category, each with a toggle.
///
/// **This sheet is not a convenience — it is the accessible path to the editor's core controls.**
/// The canvas asks the user to tap a rectangle a few points tall, positioned by pixel coordinates,
/// on a surface that can be zoomed and panned. That is unusable with VoiceOver and hard with a motor
/// impairment. This list exposes exactly the same decisions as ordinary, focusable, labelled rows:
/// what was found, what it says, whether it will be removed. Anything the canvas can do to a
/// detection, this can do too. If a control is ever added to the canvas alone, this screen has a bug.
///
/// It also happens to be the fastest way for *anyone* to audit a dense page, which is why it is
/// reachable from the toolbar rather than buried in a menu.
@MainActor
struct DetectionListSheet: View {

    let session: RedactionSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                summarySection

                ForEach(groups, id: \.kind) { group in
                    Section {
                        ForEach(group.detections) { detection in
                            DetectionRow(
                                detection: detection,
                                isEnabled: session.isEnabled(detection),
                                onToggle: { session.setEnabled($0, for: detection) }
                            )
                        }
                    } header: {
                        Text(group.kind.displayName)
                            .typeStyle(Typography.overline)
                            .foregroundStyle(Token.Accent.violetLight)
                    }
                    .listRowBackground(Token.BG.card.opacity(Token.Alpha.glassTint))
                }

                manualSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Token.BG.base)
            .navigationTitle(Text(String(
                localized: "What we found",
                comment: "Title of the sheet listing detected personal information"
            )))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Dismisses the detection list")) {
                        dismiss()
                    }
                    .frame(minWidth: Token.Size.minimumHitTarget,
                           minHeight: Token.Size.minimumHitTarget)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    @ViewBuilder
    private var summarySection: some View {
        Section {
            HStack(spacing: Token.Space.sm) {
                VStack(alignment: .leading, spacing: Token.Space.xs) {
                    Text(EditorSummary.headline(for: session))
                        .typeStyle(Typography.bodyEmphasis)
                        .foregroundStyle(Token.Text.primary)
                    Text(String(
                        localized: "Turn anything off to leave it visible in the exported file.",
                        comment: "Explains what the toggles in the detection list do"
                    ))
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button(allEnabled
                       ? String(localized: "Keep all", comment: "Turns every detection off")
                       : String(localized: "Remove all", comment: "Turns every detection on")) {
                    session.setEnabledForAll(!allEnabled)
                }
                .typeStyle(Typography.label)
                .foregroundStyle(Token.Accent.violetLight)
                .buttonStyle(.plain)
                .frame(minWidth: Token.Size.minimumHitTarget,
                       minHeight: Token.Size.minimumHitTarget)
            }
            .padding(.vertical, Token.Space.xs)
        }
        .listRowBackground(Token.BG.card.opacity(Token.Alpha.glassTint))
    }

    @ViewBuilder
    private var manualSection: some View {
        let manual = session.editState.manualRegions
        if !manual.isEmpty {
            Section {
                ForEach(manual) { region in
                    HStack(spacing: Token.Space.sm) {
                        IconWell("rectangle.dashed", tint: .muted)
                        VStack(alignment: .leading, spacing: Token.Space.xs / 2) {
                            Text(String(
                                localized: "Hand-drawn box",
                                comment: "List row for a redaction rectangle the user drew"
                            ))
                            .typeStyle(Typography.body)
                            .foregroundStyle(Token.Text.primary)
                            Text(pageDescription(region.pageIndex))
                                .typeStyle(Typography.caption)
                                .foregroundStyle(Token.Text.muted)
                        }
                        Spacer(minLength: Token.Space.sm)
                        Button {
                            session.removeManualRegion(id: region.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Token.Accent.amberLight)
                                .frame(width: Token.Size.minimumHitTarget,
                                       height: Token.Size.minimumHitTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(String(
                            localized: "Delete hand-drawn box",
                            comment: "VoiceOver label for the delete button on a manual redaction"
                        )))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            session.removeManualRegion(id: region.id)
                        } label: {
                            Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text(String(localized: "Drawn by you", comment: "Section header for manual redactions"))
                    .typeStyle(Typography.overline)
                    .foregroundStyle(Token.Accent.violetLight)
            }
            .listRowBackground(Token.BG.card.opacity(Token.Alpha.glassTint))
        }
    }

    // MARK: Data

    private struct Group {
        let kind: PIIKind
        let detections: [SessionDetection]
    }

    /// Grouped by category, categories in first-appearance order.
    ///
    /// First-appearance rather than alphabetical or by-count so the list reads in the same order as
    /// the page: someone comparing the sheet against the document scrolls both the same way.
    private var groups: [Group] {
        let detections = session.detections(onPage: session.currentPageIndex)
        var order: [PIIKind] = []
        var buckets: [PIIKind: [SessionDetection]] = [:]
        for detection in detections {
            let kind = detection.pii.kind
            if buckets[kind] == nil { order.append(kind) }
            buckets[kind, default: []].append(detection)
        }
        return order.map { Group(kind: $0, detections: buckets[$0] ?? []) }
    }

    private var allEnabled: Bool {
        let redactable = session.detected.filter(\.isRedactable)
        return !redactable.isEmpty && redactable.allSatisfy(session.isEnabled)
    }

    private func pageDescription(_ index: Int) -> String {
        String(
            format: String(localized: "Page %lld", comment: "Page number label, 1-based"),
            index + 1
        )
    }
}

// MARK: - Row

@MainActor
private struct DetectionRow: View {

    let detection: SessionDetection
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: Token.Space.sm) {
            IconWell(detection.pii.kind.symbolName, tint: isEnabled ? .gradient : .muted)

            VStack(alignment: .leading, spacing: Token.Space.xs / 2) {
                Text(detection.pii.text)
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Text.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if detection.isRedactable {
                    Text(isEnabled
                         ? String(localized: "Will be removed", comment: "Status under a detection row")
                         : String(localized: "Kept visible", comment: "Status under a detection row"))
                    .typeStyle(Typography.caption)
                    .foregroundStyle(isEnabled ? Token.Accent.violetLight : Token.Text.muted)
                } else {
                    // Rule 10: no dead controls. A detection with no OCR geometry has nothing on the
                    // page to cover, so it gets an explanation instead of a switch that does nothing.
                    Text(String(
                        localized: "Found in the text, but not located on the page — nothing to cover here.",
                        comment: "Why a detection has no toggle"
                    ))
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if detection.isRedactable {
                Toggle(isOn: Binding(get: { isEnabled }, set: onToggle)) {
                    Text(String(
                        localized: "Remove this",
                        comment: "VoiceOver label for the per-detection redaction switch"
                    ))
                }
                .labelsHidden()
                .tint(Token.Accent.violet)
                .frame(minWidth: Token.Size.minimumHitTarget,
                       minHeight: Token.Size.minimumHitTarget)
                .accessibilityLabel(Text("\(detection.pii.kind.displayName): \(detection.pii.text)"))
            } else {
                Pill(String(localized: "No location", comment: "Badge on a detection with no page geometry"))
            }
        }
        .padding(.vertical, Token.Space.xs / 2)
    }
}

// MARK: - Shared summary wording

/// The one place the editor's counts are turned into words.
///
/// Both the canvas summary bar and the sheet header show this, and they must never disagree — a
/// screen that says "6 will be removed" beside a sheet that says "5" is the kind of thing that makes
/// a user distrust the export, which is the only thing this app is asking them to trust.
@MainActor
enum EditorSummary {

    static func headline(for session: RedactionSession) -> String {
        let found = session.detected.count
        let removing = session.activeRedactionCount

        let foundText = String(
            format: String(localized: "%lld items found", comment: "Count of detected personal information"),
            found
        )
        let removingText = String(
            format: String(localized: "%lld will be removed", comment: "Count of redactions that will be applied"),
            removing
        )
        return "\(foundText) · \(removingText)"
    }

    /// The spoken form. VoiceOver reads "·" as nothing at all, so the two halves are joined with a
    /// comma instead of relying on a decorative separator to imply a pause.
    static func spoken(for session: RedactionSession) -> String {
        headline(for: session).replacingOccurrences(of: " · ", with: ", ")
    }
}
