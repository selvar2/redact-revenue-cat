import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The app's front door: three ways to bring a document in, and honest progress while it is read.
///
/// Three routes rather than one because the documents people need to redact do not all arrive the
/// same way — a rent agreement is a photo, a bank statement is a PDF in Files, and an ID card is
/// something you point a camera at. Collapsing them into "import" would make two of the three feel
/// like a workaround.
///
/// **Photo access uses `PhotosPicker` and nothing else.** The picker runs out of process and hands
/// back only the item the user tapped, so it needs no authorisation prompt at all. Calling
/// `PHPhotoLibrary.requestAuthorization` to achieve the same result asks for the whole library, is a
/// documented App Review finding, and would contradict the privacy promise printed at the bottom of
/// this very screen.
@MainActor
struct ScanView: View {

    @Environment(AppCoordinator.self) private var coordinator

    /// Injected so a preview or test can pin the quota without touching `UserDefaults.standard`.
    private let usage: UsageTracker

    @State private var stage: Stage = .idle
    @State private var session: RedactionSession?
    @State private var work: Task<Void, Never>?
    @State private var failure: Failure?

    @State private var isPresentingCamera = false
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingFileImporter = false
    @State private var photoSelection: PhotosPickerItem?

    init(usage: UsageTracker = .shared) {
        self.usage = usage
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.lg) {
                header
                options
                if let failure {
                    errorCard(failure)
                }
                privacyNote
            }
            .padding(.horizontal, Token.Space.md)
            .padding(.vertical, Token.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ambientBackground()
        .overlay { progressOverlay }
        .accessibleAnimation(Motion.gentle, value: stage)
        .accessibleAnimation(Motion.standard, value: failure?.id)
        .fullScreenCover(isPresented: $isPresentingCamera) {
            DocumentCameraView { outcome in
                isPresentingCamera = false
                handle(outcome)
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isPresentingPhotoPicker,
            selection: $photoSelection,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            photoSelection = nil
            importPhoto(item)
        }
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onDisappear {
            // A screen the user has navigated away from must not keep an OCR pass alive; on a long
            // PDF that is minutes of CPU nobody is waiting on.
            work?.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Token.Space.md) {
            SectionHeader(
                "Add a document",
                overline: "Step 1",
                subtitle: "Redact reads it on this device, finds names, numbers and IDs, and removes them for good."
            )
            quotaPill
        }
    }

    /// The free-tier counter.
    ///
    /// Shown before the user commits rather than after, because discovering the limit *at* export —
    /// having already picked, waited for OCR and reviewed detections — is where people uninstall.
    /// Phase 3 hides this for subscribers; it is a usage counter and knows nothing about purchases.
    @ViewBuilder
    private var quotaPill: some View {
        let remaining = usage.remainingFreeDocuments
        if remaining > 0 {
            Pill(
                "\(remaining) of \(UsageTracker.freeMonthlyAllowance) free this month",
                systemImage: "doc.badge.clock",
                style: .accent,
                accessibilityLabel: "\(remaining) of \(UsageTracker.freeMonthlyAllowance) free documents remaining this month"
            )
        } else {
            Pill(
                "Free documents used",
                systemImage: "exclamationmark.circle",
                style: .warning,
                accessibilityLabel: "You have used all \(UsageTracker.freeMonthlyAllowance) free documents this month. Choosing a document will show upgrade options."
            )
        }
    }

    // MARK: - Options

    private var options: some View {
        VStack(spacing: Token.Space.sm) {
            OptionRow(
                icon: "doc.viewfinder",
                title: "Scan with the camera",
                detail: cameraDetail,
                isEnabled: DocumentCameraView.isSupported
            ) {
                begin(.camera)
            }

            OptionRow(
                icon: "photo.on.rectangle",
                title: "Choose a photo",
                detail: "Pick one photo. Redact never sees the rest of your library."
            ) {
                begin(.photo)
            }

            OptionRow(
                icon: "doc.text",
                title: "Open a PDF",
                detail: "Multi-page statements, forms and letters from Files or iCloud Drive."
            ) {
                begin(.pdf)
            }
        }
    }

    /// The Simulator has no document camera, and neither do some devices. Saying so in the row —
    /// rather than presenting a black screen or silently doing nothing — is what keeps this from
    /// being a dead control (`CLAUDE.md` rule 10).
    private var cameraDetail: String {
        DocumentCameraView.isSupported
            ? "Edges and perspective are corrected automatically. Capture as many pages as you need."
            : "Not available on this device. Choose a photo or open a PDF instead."
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressOverlay: some View {
        if stage != .idle {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: Token.Space.md) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Token.Accent.violetLight)

                    VStack(spacing: Token.Space.xs) {
                        Text(progressTitle)
                            .typeStyle(Typography.headline)
                            .foregroundStyle(Token.Text.primary)
                        Text(progressDetail)
                            .typeStyle(Typography.callout)
                            .foregroundStyle(Token.Text.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: Token.Layout.proseWidth)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SecondaryButton("Cancel", systemImage: "xmark") {
                        cancel()
                    }
                }
                .frame(maxWidth: Token.Layout.proseWidth)
                .glassCard()
                .padding(.horizontal, Token.Space.lg)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(progressTitle)
                .accessibilityAddTraits(.updatesFrequently)
            }
            .accessibleTransition(Motion.contentTransition)
        }
    }

    /// Named for the work actually happening, not "Loading…". On a twenty-page statement the OCR
    /// stage is where the seconds go, and a user who knows the app is *reading* waits; a user
    /// staring at an unlabelled spinner force-quits.
    private var progressTitle: String {
        guard let processing = session?.processing else { return "Preparing your document" }
        switch processing {
        case .recognising: return "Reading the document"
        case .classifying: return "Looking for personal information"
        case .ready:       return "Opening the editor"
        case .idle, .failed: return "Preparing your document"
        }
    }

    private var progressDetail: String {
        let pageCount = session?.pages.count ?? 0
        guard let processing = session?.processing else {
            return "Getting the pages ready. Nothing leaves this device."
        }
        switch processing {
        case .recognising where pageCount > 1:
            return "Recognising text across \(pageCount) pages. Nothing leaves this device."
        case .recognising, .classifying, .ready, .idle, .failed:
            return "This runs entirely on this device, so it takes a moment on a long document."
        }
    }

    // MARK: - Errors

    private func errorCard(_ failure: Failure) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.sm) {
            HStack(alignment: .top, spacing: Token.Space.sm) {
                IconWell("exclamationmark.triangle", tint: .muted)
                VStack(alignment: .leading, spacing: Token.Space.xs) {
                    Text(failure.title)
                        .typeStyle(Typography.bodyEmphasis)
                        .foregroundStyle(Token.Text.primary)
                    Text(failure.suggestion)
                        .typeStyle(Typography.callout)
                        .foregroundStyle(Token.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SecondaryButton("Dismiss", prominence: .plain) {
                self.failure = nil
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(failure.title) \(failure.suggestion)")
    }

    // MARK: - Privacy note

    private var privacyNote: some View {
        HStack(spacing: Token.Space.xs) {
            Image(systemName: "lock.fill")
                .typeStyle(Typography.caption)
            Text("No document ever leaves this device")
                .typeStyle(Typography.caption)
        }
        .foregroundStyle(Token.Text.faint)
        .padding(.horizontal, Token.Space.md)
        .padding(.vertical, Token.Space.sm)
        .glassCapsule()
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No document ever leaves this device. Nothing is uploaded.")
    }

    // MARK: - Intent

    private enum Action { case camera, photo, pdf }

    /// The free-tier gate, checked *before* any picker opens.
    ///
    /// Deliberately in front of the work rather than after it: letting someone capture eight pages
    /// and wait through OCR only to be told they are out of quota wastes their time and their
    /// battery, and reads as a bait-and-switch. `UsageTracker` counts documents actually processed;
    /// nothing is consumed here.
    private func begin(_ action: Action) {
        failure = nil

        guard usage.canProcessDocument() else {
            coordinator.presentPaywall()
            return
        }

        switch action {
        case .camera:
            guard DocumentCameraView.isSupported else {
                failure = Failure(ImportPipeline.ImportError.cameraUnavailable)
                return
            }
            isPresentingCamera = true
        case .photo:
            isPresentingPhotoPicker = true
        case .pdf:
            isPresentingFileImporter = true
        }
    }

    private func handle(_ outcome: DocumentCameraView.Outcome) {
        switch outcome {
        case .cancelled:
            break
        case .failed(let error):
            failure = Failure(error)
        case .completed(let images):
            run(title: ImportPipeline.Origin.camera.defaultTitle()) {
                try await ImportPipeline.makeSource(scannedPages: images)
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        run(title: ImportPipeline.Origin.photoLibrary.defaultTitle()) {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImportPipeline.ImportError.unreadableImage
            }
            return try await ImportPipeline.makeSource(imageData: data)
        }
    }

    private func handleFileImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            failure = Failure(error)
        case .success(let urls):
            guard let url = urls.first else { return }
            run(title: ImportPipeline.title(forFileAt: url)) {
                try await ImportPipeline.makeSource(pdfAt: url)
            }
        }
    }

    /// Import, then detect, then navigate — as **one** task.
    ///
    /// One task rather than two chained ones is what makes cancellation real: `Cancel` cancels this
    /// task, the cancellation propagates into `DocumentPipeline`'s `checkCancellation` calls between
    /// pages, and the OCR loop actually stops. A spinner hidden over work that keeps running is the
    /// version of this that looks identical and drains the battery.
    private func run(title: String, makeSource: @escaping @MainActor () async throws -> SessionSource) {
        work?.cancel()
        failure = nil
        stage = .preparing

        work = Task { @MainActor in
            do {
                let source = try await makeSource()
                try Task.checkCancellation()

                let newSession = RedactionSession(source: source, title: title)
                session = newSession
                stage = .working

                await DocumentPipeline.run(on: newSession)
                try Task.checkCancellation()

                if let error = newSession.processing.error {
                    fail(error)
                } else if newSession.processing.isReady {
                    coordinator.push(.editor(newSession))
                    reset()
                } else {
                    // `.idle` — the pipeline absorbed a cancellation. Not an error, nothing to say.
                    reset()
                }
            } catch is CancellationError {
                reset()
            } catch {
                fail(error)
            }
        }
    }

    private func cancel() {
        work?.cancel()
        // Reset immediately as well as in the task's cancellation path: the running task may be
        // parked inside a Vision call that takes a beat to unwind, and the overlay must go now.
        reset()
    }

    private func reset() {
        work = nil
        session = nil
        stage = .idle
    }

    private func fail(_ error: any Error) {
        failure = Failure(error)
        reset()
    }

    // MARK: - Local state types

    private enum Stage: Equatable {
        /// Nothing running — the three choices are live.
        case idle
        /// Decoding, validating, or packaging what the user picked.
        case preparing
        /// `DocumentPipeline` is running; the detail line comes from the session.
        case working
    }

    /// A displayable failure.
    ///
    /// Resolved to strings at construction so the view never branches on error *type*, and so a
    /// `LocalizedError` from any layer — import, pipeline, or the file importer itself — renders the
    /// same way. The fallback text is a real sentence with a real next step, never a bare
    /// "Something went wrong".
    private struct Failure: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let suggestion: String

        init(_ error: any Error) {
            let localized = error as? any LocalizedError
            title = localized?.errorDescription
                ?? String(localized: "This document could not be opened.",
                          comment: "Fallback error title on the scan screen")
            suggestion = localized?.recoverySuggestion
                ?? String(localized: "Try a different file, or photograph the page with the camera.",
                          comment: "Fallback recovery suggestion on the scan screen")
        }

        static func == (lhs: Failure, rhs: Failure) -> Bool { lhs.id == rhs.id }
    }
}

// MARK: - Option row

/// One import route, as a full-width glass card.
///
/// A card rather than a button style because each route needs an icon, a title *and* a sentence
/// explaining what it does — the explanations are what make the choice obvious to someone opening
/// the app for the first time. VoiceOver reads it as a single button whose label is the title and
/// whose hint is the detail, so the explanation is available without being read out on every swipe.
private struct OptionRow: View {

    let icon: String
    let title: String
    let detail: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Token.Space.sm) {
                IconWell(icon)

                VStack(alignment: .leading, spacing: Token.Space.xs) {
                    Text(title)
                        .typeStyle(Typography.bodyEmphasis)
                        .foregroundStyle(Token.Text.primary)
                    Text(detail)
                        .typeStyle(Typography.callout)
                        .foregroundStyle(Token.Text.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .typeStyle(Typography.caption)
                    .foregroundStyle(Token.Text.faint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Token.Size.minimumHitTarget)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(OptionRowStyle())
        .opacity(isEnabled ? 1 : Token.Alpha.disabled)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(.isButton)
    }
}

/// Sinks the card while it is held.
///
/// A `ButtonStyle` rather than a press gesture on top of the button: a `.onLongPressGesture` with a
/// zero minimum duration competes with the button's own tap recognition and swallows taps on some
/// devices. `GlassCard` already animates its elevation through the reduced-motion guardrail, so the
/// style only has to pick the right one.
private struct OptionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassCard(elevation: configuration.isPressed ? .pressed : .resting)
    }
}

#Preview("Scan") {
    ScanView()
        .environment(AppCoordinator())
        .preferredColorScheme(.dark)
}
