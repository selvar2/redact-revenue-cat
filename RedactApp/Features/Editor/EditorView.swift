import SwiftUI
import UIKit

/// The review screen: the page, everything found on it, and every control needed to decide what
/// actually gets destroyed.
///
/// This is the product. Scan is plumbing and Export is a confirmation; this is where the user does
/// the work and where the app either earns trust or loses it. Three commitments shape it:
///
/// - **Nothing has happened yet.** Every box on screen is a proposal. The source bytes are untouched
///   until `RedactionEngine` runs at export, which is what makes undo free and the destroy path
///   singular. The visual language reflects that: outlines while reviewing, solid bars once the
///   reveal lands.
/// - **Every gesture has a non-gesture equal.** Tap-to-toggle is mirrored by ``DetectionListSheet``;
///   drag-to-draw is mirrored by the box's own VoiceOver actions; pinch-to-zoom is mirrored by the
///   zoom button. A canvas is not an accessible control surface on its own, and pretending otherwise
///   would fail `CLAUDE.md` rule 4.
/// - **The animation is never a gate.** The scanline reveal is the app's signature frame, but the
///   first touch settles it instantly. Motion that blocks input is decoration pretending to be UI.
@MainActor
struct EditorView: View {

    let session: RedactionSession

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibleAnimation) private var accessibleAnimation

    @State private var director = ScanlineDirector()
    @State private var pageImage: UIImage?

    // Zoom and pan. The committed value plus the in-flight gesture value, so a gesture that is
    // cancelled mid-flight cannot leave the canvas in a half-transformed state.
    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var gesturePan: CGSize = .zero

    @State private var draft: CGRect?
    @State private var draftDidSnap = false
    @State private var isDrawMode = false
    @State private var selectedManualID: UUID?
    @State private var showsDetectionList = false

    private var effectiveZoom: CGFloat {
        min(max(zoom * gestureZoom, EditorMetric.minimumZoom), EditorMetric.maximumZoom)
    }

    var body: some View {
        ZStack {
            Color.clear.ambientBackground()

            VStack(spacing: Token.Space.sm) {
                canvasArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if session.processing.isReady {
                    summaryBar
                    actionBar
                }
            }
            .padding(.horizontal, Token.Space.md)
            .padding(.bottom, Token.Space.md)
        }
        .navigationTitle(Text(AppRoute.editor(session).accessibilityTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showsDetectionList) {
            DetectionListSheet(session: session)
        }
        .task {
            // Scan normally runs the pipeline before pushing here. If the editor is reached with an
            // untouched session (a deep link, a retry, a preview) it runs it itself rather than
            // showing an empty page with no explanation.
            if case .idle = session.processing {
                await DocumentPipeline.run(on: session)
            }
        }
        .task(id: session.processing.isReady) {
            guard session.processing.isReady else { return }
            await loadPageImage()
            await director.reveal(reduceMotion: reduceMotion)
            announceResult()
        }
        .task(id: session.currentPageIndex) {
            await loadPageImage()
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvasArea: some View {
        switch session.processing {
        case .idle, .recognising, .classifying:
            ProcessingState(state: session.processing)
        case .failed(let error):
            FailureState(
                error: error,
                onRetry: { Task { await DocumentPipeline.run(on: session) } },
                onBack: { coordinator.pop() }
            )
        case .ready:
            pageCanvas
        }
    }

    private var pageCanvas: some View {
        GeometryReader { proxy in
            let page = currentPage
            let contentSize = EditorGeometry.fittedSize(
                for: page?.pixelSize ?? .zero,
                in: proxy.size
            )

            ZStack {
                if let pageImage, contentSize != .zero {
                    documentStack(image: pageImage, contentSize: contentSize)
                        .scaleEffect(effectiveZoom)
                        .offset(committedPan(contentSize: contentSize))
                        .gesture(magnifyGesture(contentSize: contentSize))
                        .simultaneousGesture(panGesture(contentSize: contentSize))
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ProgressView()
                        .tint(Token.Accent.violetLight)
                        .accessibilityLabel(Text(String(
                            localized: "Preparing the page",
                            comment: "VoiceOver label while the page image decodes"
                        )))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    /// The page and every layer over it, in the page's own coordinate space.
    ///
    /// The draw gesture is attached **inside** the zoom transform on purpose: gesture locations then
    /// arrive already in content points, so `RedactionRegion(userDrawnRect:in:)` receives exactly
    /// what it documents and no call site ever inverts a transform by hand.
    private func documentStack(image: UIImage, contentSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: contentSize.width, height: contentSize.height)
                .accessibilityLabel(Text(pageAccessibilityLabel))

            DetectionOverlay(
                items: overlayItems,
                contentSize: contentSize,
                zoom: effectiveZoom,
                director: director,
                onToggle: toggle
            )

            ManualRegionLayer(
                regions: session.manualRegions(onPage: session.currentPageIndex),
                contentSize: contentSize,
                zoom: effectiveZoom,
                selectedID: $selectedManualID,
                onResize: { manual, rect in resize(manual, to: rect, contentSize: contentSize) },
                onDelete: { session.removeManualRegion(id: $0) }
            )

            if let draft {
                DraftRegionView(rect: draft, zoom: effectiveZoom, isSnapped: draftDidSnap)
            }

            if director.isSweeping {
                ScanlineSweep(progress: director.progress, contentSize: contentSize)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.card, style: .continuous))
        .shadow(Token.Shadow.card)
        // Hold-then-drag draws a box without leaving the normal browsing mode; the explicit draw
        // mode below is the same gesture with the hold removed, for users who cannot hold steady.
        .gesture(holdToDrawGesture(contentSize: contentSize),
                 including: isDrawMode ? .subviews : .all)
        .gesture(drawGesture(contentSize: contentSize),
                 including: isDrawMode ? .all : .subviews)
    }

    private var overlayItems: [DetectionOverlay.Item] {
        session.detections(onPage: session.currentPageIndex).compactMap { detection in
            guard let region = RedactionRegion(detected: detection.pii) else { return nil }
            return DetectionOverlay.Item(
                detection: detection,
                region: region,
                isEnabled: session.isEnabled(detection)
            )
        }
    }

    // MARK: - Bars

    private var summaryBar: some View {
        HStack(spacing: Token.Space.sm) {
            IconWell("eye.slash.fill", tint: .gradient)

            VStack(alignment: .leading, spacing: Token.Space.xs / 2) {
                Text(EditorSummary.headline(for: session))
                    .typeStyle(Typography.bodyEmphasis)
                    .foregroundStyle(Token.Text.primary)
                Text(String(
                    localized: "Tap a box to keep it. Hold and drag to cover anything else.",
                    comment: "Instructional subtitle in the editor summary bar"
                ))
                .typeStyle(Typography.caption)
                .foregroundStyle(Token.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if session.pages.count > 1 {
                Pill(pageIndicator, style: .neutral, accessibilityLabel: pageIndicatorSpoken)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(EditorSummary.spoken(for: session)))
    }

    private var actionBar: some View {
        HStack(spacing: Token.Space.sm) {
            if session.pages.count > 1 {
                pageButton(systemImage: "chevron.left",
                           label: String(localized: "Previous page", comment: "Editor page navigation"),
                           enabled: session.currentPageIndex > 0) {
                    session.currentPageIndex -= 1
                }
                pageButton(systemImage: "chevron.right",
                           label: String(localized: "Next page", comment: "Editor page navigation"),
                           enabled: session.currentPageIndex < session.pages.count - 1) {
                    session.currentPageIndex += 1
                }
            }

            PrimaryButton(String(localized: "Review and export", comment: "Moves from the editor to the export screen"),
                          systemImage: "square.and.arrow.up") {
                coordinator.showExport(for: session)
            }
        }
    }

    private func pageButton(systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(Token.Text.primary)
                .frame(width: Token.Size.minimumHitTarget, height: Token.Size.minimumHitTarget)
        }
        .buttonStyle(.plain)
        .glassCapsule()
        .disabled(!enabled)
        .opacity(enabled ? 1 : Token.Alpha.disabled)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            toolbarButton(
                systemImage: "arrow.uturn.backward",
                label: String(localized: "Undo", comment: "Editor toolbar"),
                enabled: session.canUndo
            ) {
                withAnimation(accessibleAnimation(Motion.snappy)) { session.undo() }
            }

            toolbarButton(
                systemImage: "arrow.uturn.forward",
                label: String(localized: "Redo", comment: "Editor toolbar"),
                enabled: session.canRedo
            ) {
                withAnimation(accessibleAnimation(Motion.snappy)) { session.redo() }
            }

            toolbarButton(
                systemImage: isDrawMode ? "rectangle.dashed.badge.record" : "rectangle.dashed",
                label: isDrawMode
                    ? String(localized: "Stop drawing boxes", comment: "Editor toolbar")
                    : String(localized: "Draw a box", comment: "Editor toolbar"),
                enabled: session.processing.isReady,
                isOn: isDrawMode
            ) {
                withAnimation(accessibleAnimation(Motion.snappy)) { isDrawMode.toggle() }
            }

            toolbarButton(
                systemImage: "list.bullet.rectangle",
                label: String(localized: "Show everything we found", comment: "Editor toolbar"),
                enabled: session.processing.isReady
            ) {
                director.settleImmediately()
                showsDetectionList = true
            }
        }
    }

    private func toolbarButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? Token.Accent.violetLight : Token.Text.primary)
                .frame(minWidth: Token.Size.minimumHitTarget, minHeight: Token.Size.minimumHitTarget)
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Gestures

    private func magnifyGesture(contentSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                gestureZoom = value.magnification
            }
            .onEnded { _ in
                zoom = effectiveZoom
                gestureZoom = 1
                pan = EditorGeometry.clampedPan(pan, contentSize: contentSize, zoom: zoom)
            }
    }

    private func panGesture(contentSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: Token.Space.sm)
            .onChanged { value in
                guard draft == nil, effectiveZoom > EditorMetric.minimumZoom else { return }
                gesturePan = value.translation
            }
            .onEnded { _ in
                pan = EditorGeometry.clampedPan(
                    CGSize(width: pan.width + gesturePan.width, height: pan.height + gesturePan.height),
                    contentSize: contentSize,
                    zoom: effectiveZoom
                )
                gesturePan = .zero
            }
    }

    private func committedPan(contentSize: CGSize) -> CGSize {
        EditorGeometry.clampedPan(
            CGSize(width: pan.width + gesturePan.width, height: pan.height + gesturePan.height),
            contentSize: contentSize,
            zoom: effectiveZoom
        )
    }

    /// Hold, then drag: draws a box without needing a mode.
    private func holdToDrawGesture(contentSize: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: EditorMetric.minimumDraftSide)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    updateDraft(from: drag, contentSize: contentSize)
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    updateDraft(from: drag, contentSize: contentSize)
                }
                commitDraft(contentSize: contentSize)
            }
    }

    /// The same thing without the hold, for when the user has explicitly entered draw mode.
    private func drawGesture(contentSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { updateDraft(from: $0, contentSize: contentSize) }
            .onEnded { _ in commitDraft(contentSize: contentSize) }
    }

    private func updateDraft(from value: DragGesture.Value, contentSize: CGSize) {
        director.settleImmediately()
        let raw = EditorGeometry.confine(
            EditorGeometry.rect(from: value.startLocation, to: value.location),
            to: contentSize
        )
        let snapped = EditorGeometry.snapped(raw, to: snapTargets(contentSize: contentSize))
        draftDidSnap = snapped != raw
        draft = snapped
    }

    private func commitDraft(contentSize: CGSize) {
        defer {
            draft = nil
            draftDidSnap = false
        }
        guard let rect = draft,
              rect.width >= EditorMetric.minimumDraftSide,
              rect.height >= EditorMetric.minimumDraftSide,
              let region = RedactionRegion(userDrawnRect: rect, in: contentSize) else { return }

        let added = session.addManualRegion(region, onPage: session.currentPageIndex)
        withAnimation(accessibleAnimation(Motion.snappy)) { selectedManualID = added.id }
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Redaction box added", comment: "VoiceOver announcement after drawing a box")
        )
    }

    /// The detected text boxes a hand-drawn rect can snap onto, in content points.
    private func snapTargets(contentSize: CGSize) -> [CGRect] {
        overlayItems.map { $0.region.displayRect(in: contentSize) }
    }

    // MARK: - Actions

    private func toggle(_ detection: SessionDetection) {
        director.settleImmediately()
        withAnimation(accessibleAnimation(Motion.snappy)) {
            session.toggle(detection)
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: session.isEnabled(detection)
                ? String(localized: "Will be removed", comment: "VoiceOver announcement after enabling a redaction")
                : String(localized: "Kept", comment: "VoiceOver announcement after disabling a redaction")
        )
    }

    /// Commits a resized hand-drawn box.
    ///
    /// `RedactionSession` exposes add and remove but no in-place update, so a resize is recorded as
    /// a remove followed by an add. The visible result is correct; the cost is that undoing a resize
    /// takes two steps rather than one. Logged in `docs/memory/gotchas/manual-region-resize-undo.md`
    /// — the fix is an `updateManualRegion(id:region:)` on the session, which lives in another
    /// agent's allowlist.
    private func resize(_ manual: ManualRegion, to rect: CGRect, contentSize: CGSize) {
        guard rect.width >= EditorMetric.minimumDraftSide,
              rect.height >= EditorMetric.minimumDraftSide,
              let region = RedactionRegion(userDrawnRect: rect, in: contentSize, style: manual.region.style)
        else { return }

        session.removeManualRegion(id: manual.id)
        let replacement = session.addManualRegion(region, onPage: manual.pageIndex)
        selectedManualID = replacement.id
    }

    private func toggleZoom() {
        withAnimation(accessibleAnimation(Motion.standard)) {
            if effectiveZoom > EditorMetric.minimumZoom {
                zoom = EditorMetric.minimumZoom
                pan = .zero
            } else {
                zoom = 2
            }
            gestureZoom = 1
        }
    }

    private func loadPageImage() async {
        pageImage = currentPage?.image()
    }

    /// Speaks the outcome once detection finishes. This is the accessible counterpart of the
    /// scanline: a sighted user learns "seven things were found" from the reveal, and a VoiceOver
    /// user must learn the same thing at the same moment rather than by exploring the canvas.
    private func announceResult() {
        UIAccessibility.post(notification: .screenChanged, argument: EditorSummary.spoken(for: session))
    }

    // MARK: - Derived

    private var currentPage: SessionPage? {
        session.pages.indices.contains(session.currentPageIndex)
            ? session.pages[session.currentPageIndex]
            : nil
    }

    private var pageIndicator: String {
        "\(session.currentPageIndex + 1)/\(session.pages.count)"
    }

    private var pageIndicatorSpoken: String {
        String(
            format: String(localized: "Page %lld of %lld", comment: "Spoken page position"),
            session.currentPageIndex + 1,
            session.pages.count
        )
    }

    private var pageAccessibilityLabel: String {
        session.pages.count > 1
            ? String(format: String(localized: "Document page %lld", comment: "VoiceOver label for the page image"),
                     session.currentPageIndex + 1)
            : String(localized: "Document page", comment: "VoiceOver label for the page image")
    }
}

// MARK: - Non-ready states

/// What the screen shows while detection runs.
///
/// Named stages rather than a bare spinner: OCR then classification is several seconds on a dense
/// page, and a progress indicator that says what it is doing is the difference between "working" and
/// "stuck". No percentage is shown because we do not have an honest one.
@MainActor
private struct ProcessingState: View {

    let state: SessionProcessingState

    var body: some View {
        VStack(spacing: Token.Space.md) {
            ProgressView()
                .tint(Token.Accent.violetLight)
                .scaleEffect(1.4)

            Text(message)
                .typeStyle(Typography.headline)
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.center)

            Text(String(
                localized: "Everything happens on this device. Nothing is uploaded.",
                comment: "Reassurance shown while a document is analysed"
            ))
            .typeStyle(Typography.caption)
            .foregroundStyle(Token.Text.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Token.Layout.proseWidth)
        }
        .padding(Token.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var message: String {
        switch state {
        case .recognising:
            String(localized: "Reading the document…", comment: "Detection stage: OCR")
        case .classifying:
            String(localized: "Looking for personal information…", comment: "Detection stage: classification")
        case .idle, .ready, .failed:
            String(localized: "Getting started…", comment: "Detection stage: not begun")
        }
    }
}

/// The failure state.
///
/// Two ways out, always. The App Review checklist forbids a screen that dead-ends, and more to the
/// point a user whose document failed to open needs to be able to try again *or* leave without
/// force-quitting.
@MainActor
private struct FailureState: View {

    let error: any Error
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: Token.Space.md) {
            IconWell("exclamationmark.triangle.fill", size: 64, tint: .solid)

            Text(String(localized: "We could not read this document", comment: "Editor failure title"))
                .typeStyle(Typography.title)
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.center)

            Text(message)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Token.Layout.proseWidth)

            PrimaryButton(String(localized: "Try again", comment: "Retries document processing"),
                          systemImage: "arrow.clockwise",
                          action: onRetry)

            SecondaryButton(String(localized: "Choose another document", comment: "Returns to the scan screen"),
                            prominence: .plain,
                            action: onBack)
        }
        .padding(Token.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Prefers the error's own description when it has one — `DocumentPipeline.PipelineError` is
    /// `LocalizedError` precisely so this screen can say which page failed rather than "an error
    /// occurred".
    private var message: String {
        (error as? LocalizedError)?.errorDescription
            ?? String(
                localized: "The file may be damaged, password-protected, or in a format we cannot open.",
                comment: "Fallback explanation when a document cannot be processed"
            )
    }
}
