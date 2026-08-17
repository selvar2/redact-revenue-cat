import SwiftData
import SwiftUI

/// Everything the user has already redacted.
///
/// ## Why a `List` and not a `LazyVGrid`
///
/// The brief asks for thumbnails *and* swipe-to-delete *and* multi-select. Only `List`
/// gives the last two for free, and hand-rolling a swipe gesture inside a grid breaks
/// both of the things this project treats as non-negotiable: a custom drag has no
/// VoiceOver equivalent, and a fixed-height grid cell clips at the larger Dynamic Type
/// sizes. A list row with a page-shaped thumbnail carries the same information density
/// as a grid tile at a fraction of the risk, and it scrolls faster because each row
/// decodes one small image (see ``ThumbnailLoader``).
struct LibraryView: View {

    @Environment(AppCoordinator.self) private var coordinator
    /// The store arrives via `AppEnvironment`, which is what `RootView` installs — there is exactly
    /// one `DocumentStore` for the app so the library and the export screen agree about what is saved.
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = LibraryModel()
    @State private var editMode: EditMode = .inactive
    @State private var isConfirmingBulkDelete = false

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .bottom) {
            content

            if let pending = model.pendingDeletion {
                UndoSnackbar(message: pending.message) {
                    model.undoPendingDeletion()
                }
                .padding(.horizontal, Token.Space.md)
                .padding(.bottom, Token.Space.md)
                .accessibleTransition(Motion.contentTransition)
            }
        }
        .accessibleAnimation(Motion.standard, value: model.pendingDeletion)
        .ambientBackground(.subdued)
        .navigationTitle(AppRoute.library.accessibilityTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .environment(\.editMode, $editMode)
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search by name or date")
        )
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isConfirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationAction, role: .destructive) {
                model.stageDeleteSelection()
                editMode = .inactive
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("The redacted pages are erased from this device. This cannot be undone once the undo bar disappears.")
        }
        // Runs on every appearance, including the return from the detail screen and the jump the
        // coordinator makes after an export. Re-fetching is cheap by construction: `RedactedDocument`
        // holds no image bytes, so this is a sorted row read, not a page load.
        .task {
            model.attach(store: appEnvironment.store)
            model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            // A staged delete must not survive into the background as an invisible
            // promise — commit it while the app is still alive to do so.
            if phase != .active { model.commitPendingDeletionNow() }
        }
        .onDisappear {
            model.commitPendingDeletionNow()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let failure = model.failureMessage, model.documents.isEmpty {
            LibraryMessage(
                symbol: "exclamationmark.triangle",
                title: String(localized: "Something went wrong"),
                message: failure,
                actionTitle: String(localized: "Try again"),
                action: { model.reload() }
            )
        } else if !model.hasLoaded {
            ProgressView()
                .tint(Token.Accent.violetLight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Opening your library")
        } else if model.isLibraryEmpty {
            emptyLibrary
        } else if model.isSearchEmpty {
            emptySearch
        } else {
            documentList
        }
    }

    private var documentList: some View {
        @Bindable var model = model

        return List(selection: $model.selection) {
            ForEach(model.visibleDocuments) { summary in
                row(for: summary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if let failure = model.failureMessage {
                Text(failure)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Accent.amberLight)
                    .multilineTextAlignment(.center)
                    .padding(Token.Space.sm)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    @ViewBuilder
    private func row(for summary: DocumentSummary) -> some View {
        // A `Button`, not an `onTapGesture`: it gets the button trait, the activation
        // behaviour VoiceOver and Switch Control expect, and it steps aside on its own
        // in edit mode so `List` selection takes the tap.
        Button {
            coordinator.push(.documentDetail(id: summary.id))
        } label: {
            DocumentRow(summary: summary)
        }
        .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Token.Space.xs, leading: Token.Space.md,
                bottom: Token.Space.xs, trailing: Token.Space.md
            ))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    model.stageDelete(summary)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            // VoiceOver users cannot perform a swipe action. The destructive intent is
            // therefore published as a custom action on the row (rotor: Actions) as well.
            // A swipe-only delete is an inaccessible delete.
            .accessibilityAction(named: Text("Delete")) {
                model.stageDelete(summary)
            }
    }

    // MARK: - Empty states

    /// The genuinely-empty state. It routes to scanning, because a library screen with
    /// nothing in it and nothing to do is a dead end (`CLAUDE.md`: no screen may
    /// dead-end).
    private var emptyLibrary: some View {
        LibraryMessage(
            symbol: "tray",
            title: String(localized: "Nothing here yet"),
            message: String(localized: "Documents you redact are saved here, on this device only. Start with a photo, a scan, or a PDF."),
            actionTitle: String(localized: "Redact a document"),
            action: { coordinator.push(.scan) }
        )
    }

    private var emptySearch: some View {
        @Bindable var model = model

        return LibraryMessage(
            symbol: "magnifyingglass",
            title: String(localized: "No matches"),
            message: noMatchesMessage(for: model.searchText),
            actionTitle: String(localized: "Clear search"),
            action: { model.searchText = "" }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !model.isLibraryEmpty && model.hasLoaded {
                EditButton()
                    .accessibilityLabel(editMode == .active ? "Done selecting" : "Select documents")
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            if editMode == .active && !model.selection.isEmpty {
                Button(role: .destructive) {
                    isConfirmingBulkDelete = true
                } label: {
                    Label(deleteConfirmationAction, systemImage: "trash")
                }
                .tint(Token.Accent.amberLight)
                .accessibilityLabel(deleteConfirmationAction)
            }
        }
    }

    /// The query is interpolated into a *formatted* string rather than into a
    /// `String(localized:)` key. A key that changes with the user's typing cannot be
    /// looked up in a strings table — every keystroke would be a different, missing key.
    private func noMatchesMessage(for query: String) -> String {
        let template = String(
            localized: "Nothing matches %@. Search by document name, or by date — try “August” or “2026”.",
            comment: "Library: no search results. %@ is the user's query, already quoted."
        )
        return String(format: template, "“\(query)”")
    }

    private var deleteConfirmationTitle: String {
        model.selection.count == 1
            ? String(localized: "Delete this document?")
            : String(localized: "Delete \(model.selection.count) documents?")
    }

    private var deleteConfirmationAction: String {
        model.selection.count == 1
            ? String(localized: "Delete")
            : String(localized: "Delete \(model.selection.count)")
    }
}

// MARK: - Row

/// One saved document.
///
/// The whole row is a single VoiceOver element reading
/// "Salary slip, 3 items removed, 17 August" — the pills and the thumbnail are
/// decoration around that sentence, and announcing each separately would make the
/// list four times longer to hear for no extra information.
private struct DocumentRow: View {

    let summary: DocumentSummary

    var body: some View {
        HStack(spacing: Token.Space.sm) {
            VaultImage(
                key: summary.thumbnailCacheKey,
                relativePath: summary.displayImagePath,
                maxPixel: LibraryLayout.rowThumbnailPixels,
                fallbackSymbol: summary.sourceKind.symbolName
            )
            .frame(width: LibraryLayout.rowThumbnailWidth,
                   height: LibraryLayout.rowThumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                    .strokeBorder(Token.Line.hairline, lineWidth: Token.Size.hairlineWidth)
            )

            VStack(alignment: .leading, spacing: Token.Space.xs) {
                Text(summary.title)
                    .typeStyle(Typography.bodyEmphasis)
                    .foregroundStyle(Token.Text.primary)
                    .lineLimit(2)

                Text(summary.dateLabel)
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.muted)

                HStack(spacing: Token.Space.xs) {
                    Pill(
                        summary.redactionLabel,
                        systemImage: "eye.slash.fill",
                        style: summary.redactionCount == 0 ? .neutral : .success
                    )
                    Pill(summary.sourceKind.displayName, style: .neutral)
                    if summary.pageCount > 1 {
                        Pill(summary.pageLabel, style: .neutral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.faint)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Token.Size.minimumHitTarget)
        .glassCard(cornerRadius: Token.Radius.card, padding: Token.Space.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityHint("Opens the redacted document")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Message screen

/// A centred glyph, a sentence, and exactly one thing to do next.
///
/// Used for empty, no-results and failure states so all three have the same shape and
/// none of them is a dead end.
private struct LibraryMessage: View {

    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Token.Space.md) {
            IconWell(symbol, size: Token.Size.mark, tint: .gradient)

            VStack(spacing: Token.Space.sm) {
                Text(title)
                    .typeStyle(Typography.title)
                    .foregroundStyle(Token.Text.primary)

                Text(message)
                    .typeStyle(Typography.body)
                    .foregroundStyle(Token.Text.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Token.Layout.proseWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            PrimaryButton(actionTitle, action: action)
                .frame(maxWidth: Token.Layout.proseWidth)
        }
        .padding(Token.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Library") {
    let appEnvironment = AppEnvironment()

    return NavigationStack {
        LibraryView()
    }
    .environment(appEnvironment)
    .environment(AppCoordinator())
    .preferredColorScheme(.dark)
}
