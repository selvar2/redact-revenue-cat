import CoreGraphics
import Foundation
import Observation
import UIKit

// MARK: - Source

/// The bytes the user brought in, and what kind of document they are.
///
/// `Data` rather than `UIImage`/`PDFDocument` on purpose: `Data` is `Sendable`, so the same value
/// crosses into the detached tasks that do OCR and rasterisation without an `@unchecked` escape
/// (CLAUDE.md rule 5), and it is the exact input `RedactionEngine` wants at export time.
///
/// **These bytes are never mutated.** Every edit the user makes is recorded as regions to apply
/// *later*; the source is destroyed once, at export, by `RedactionEngine`. That is what makes undo
/// free (it is a struct swap, not a re-render) and what makes export safe (there is exactly one
/// destroy path, and it always starts from the pristine original).
public enum SessionSource: Sendable, Hashable {
    case image(Data)
    case pdf(Data)

    public var data: Data {
        switch self {
        case .image(let data), .pdf(let data): return data
        }
    }

    public var isPDF: Bool {
        if case .pdf = self { return true }
        return false
    }

    /// Maps onto the persistence layer's vocabulary so Library and Export agree on one word.
    public var kind: DocumentSourceKind {
        switch self {
        // Persisted raw values must not change, so there is no `.image` case to add: an imported
        // image is recorded as `.photo`, and Scan overwrites it with `.scan` when it came from
        // the camera.
        case .image: return .photo
        case .pdf:   return .pdf
        }
    }
}

// MARK: - Page

/// One rendered page, ready to show and ready to OCR.
///
/// `imageData` is PNG bytes for a single page. For an image source it is the source itself; for a
/// PDF it is the rasterised page produced by ``DocumentPipeline``. Keeping it as `Data` means the
/// page can be handed straight to `TextRecogniser` from a background task, while the UI decodes it
/// to a `UIImage` on the main actor through ``image``.
public struct SessionPage: Sendable, Hashable, Identifiable {
    /// Zero-based page index, matching `PageRedaction.pageIndex`.
    public let index: Int
    public let imageData: Data
    /// Pixel dimensions of the rendered page, for aspect-ratio layout before the image decodes.
    public let pixelSize: CGSize

    public var id: Int { index }

    public init(index: Int, imageData: Data, pixelSize: CGSize) {
        self.index = index
        self.imageData = imageData
        self.pixelSize = pixelSize
    }

    /// Decoded image for display. Decoding is not free; hold the result in view state rather than
    /// calling this inside a `body` that re-evaluates on every gesture change.
    @MainActor
    public func image() -> UIImage? { UIImage(data: imageData) }
}

// MARK: - Detection identity

/// Stable identity for one detection within a session.
///
/// `DetectedPII.id` is unique only within a page (it is built from character offsets, and page two
/// restarts at zero), so the page index is part of the key. Undo state stores these rather than the
/// detections themselves, which keeps each undo entry tiny.
public struct SessionDetectionID: Sendable, Hashable, Codable {
    public let pageIndex: Int
    public let detectionID: String

    public init(pageIndex: Int, detectionID: String) {
        self.pageIndex = pageIndex
        self.detectionID = detectionID
    }
}

/// A detection bound to the page it was found on.
public struct SessionDetection: Sendable, Hashable, Identifiable {
    public let pageIndex: Int
    public let pii: DetectedPII

    public var id: SessionDetectionID {
        SessionDetectionID(pageIndex: pageIndex, detectionID: pii.id)
    }

    /// False when the detection has no OCR geometry — it can be listed, but there is nothing on the
    /// page to cover. The editor shows these as informational rows, never as a toggle that does
    /// nothing (CLAUDE.md rule 10: no dead controls).
    public var isRedactable: Bool { pii.span.hasGeometry }

    public init(pageIndex: Int, pii: DetectedPII) {
        self.pageIndex = pageIndex
        self.pii = pii
    }
}

/// A rectangle the user drew by hand, with identity so it can be selected and deleted.
public struct ManualRegion: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let pageIndex: Int
    public var region: RedactionRegion

    public init(id: UUID = UUID(), pageIndex: Int, region: RedactionRegion) {
        self.id = id
        self.pageIndex = pageIndex
        self.region = region
    }
}

// MARK: - Edit state

/// The entire user-editable state of a session, as one value.
///
/// Undo/redo is implemented by pushing copies of this struct. That is only cheap because it holds
/// *decisions*, not pixels: a set of opt-outs and a list of drawn rectangles. If anything expensive
/// (page images, source bytes, detection results) is ever added here, undo stops being free — put
/// it on the session instead.
public struct SessionEditState: Sendable, Hashable {
    /// Detections the user chose **not** to redact.
    ///
    /// Stored as opt-outs rather than opt-ins so that the safe state is the default: a detection
    /// that arrives after this set was built is redacted unless the user says otherwise. An
    /// opt-in set would fail open, which for this app means shipping a document with live PII.
    public var disabledDetections: Set<SessionDetectionID>
    public var manualRegions: [ManualRegion]

    public init(disabledDetections: Set<SessionDetectionID> = [], manualRegions: [ManualRegion] = []) {
        self.disabledDetections = disabledDetections
        self.manualRegions = manualRegions
    }
}

// MARK: - Processing state

/// Where the session is in the detect pipeline.
///
/// Every case is a state the UI must be able to draw, including `failed` — which carries the error
/// so the screen can offer a real recovery path rather than a dead end (App Review checklist).
public enum SessionProcessingState: Sendable {
    case idle
    case recognising
    case classifying
    case ready
    case failed(any Error)

    public var isBusy: Bool {
        switch self {
        case .recognising, .classifying: return true
        case .idle, .ready, .failed:     return false
        }
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var error: (any Error)? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

// MARK: - Session

/// The document currently being worked on, shared by Scan, Editor and Export.
///
/// One session is created when a document is imported and lives until it is exported or discarded.
/// It is a reference type because three screens edit the same document and must see each other's
/// changes; it is `@MainActor` because it is UI state, and `@Observable` so SwiftUI tracks the
/// individual properties a view actually reads.
///
/// **What it does not do:** it does not run detection (``DocumentPipeline`` does) and it does not
/// redact anything (`RedactionEngine` does, at export). It owns state and the undo stack.
@Observable
@MainActor
public final class RedactionSession: Identifiable {

    public let id: UUID
    public let source: SessionSource

    /// A display title, seeded from the import and editable before saving.
    public var title: String

    /// Rendered pages in document order. Empty until ``DocumentPipeline`` populates it.
    public private(set) var pages: [SessionPage] = []

    /// The page the editor is showing.
    ///
    /// Clamped on write rather than trusted: a page-view binding can transiently propose an index
    /// past the end while `pages` is still being populated, and an out-of-range index here would
    /// mean the editor draws page N's boxes over page M's pixels.
    public var currentPageIndex: Int {
        get { storedPageIndex }
        set { storedPageIndex = clampPageIndex(newValue) }
    }

    private var storedPageIndex: Int = 0

    /// Everything detection found, across all pages, in page then reading order.
    public private(set) var detected: [SessionDetection] = []

    public private(set) var processing: SessionProcessingState = .idle

    /// The current user edits. Assign through the mutating helpers so undo stays correct.
    public private(set) var editState = SessionEditState()

    private var undoStack: [SessionEditState] = []
    private var redoStack: [SessionEditState] = []

    /// Undo depth. Deep enough that a long editing pass is fully reversible, bounded so a user who
    /// draws hundreds of boxes cannot grow the stack without limit.
    private let undoLimit = 50

    public init(source: SessionSource, title: String, id: UUID = UUID()) {
        self.id = id
        self.source = source
        self.title = title
    }

    // MARK: Pipeline hand-off
    //
    // Only `DocumentPipeline` should call these. They are `public` because it is a separate type,
    // not because features should drive them by hand — a feature that sets `.ready` itself will
    // show an editor with no detections and no error.

    public func setProcessing(_ state: SessionProcessingState) {
        processing = state
    }

    public func setPages(_ pages: [SessionPage]) {
        self.pages = pages
        storedPageIndex = clampPageIndex(storedPageIndex)
    }

    /// Replaces the detection results. Clears any opt-outs that no longer refer to a live
    /// detection, so a stale key cannot silently suppress a *different* detection later.
    public func setDetections(_ detections: [SessionDetection]) {
        detected = detections
        let live = Set(detections.map(\.id))
        var state = editState
        state.disabledDetections.formIntersection(live)
        editState = state
    }

    // MARK: Queries

    public func detections(onPage pageIndex: Int) -> [SessionDetection] {
        detected.filter { $0.pageIndex == pageIndex }
    }

    public func manualRegions(onPage pageIndex: Int) -> [ManualRegion] {
        editState.manualRegions.filter { $0.pageIndex == pageIndex }
    }

    /// True when this detection will be redacted on export.
    public func isEnabled(_ detection: SessionDetection) -> Bool {
        detection.isRedactable && !editState.disabledDetections.contains(detection.id)
    }

    /// How many redactions the export will actually perform. Drives the export screen's summary and
    /// the audit trail count — it must never be a guess.
    public var activeRedactionCount: Int {
        detected.filter(isEnabled).count + editState.manualRegions.count
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Editing

    public func setEnabled(_ enabled: Bool, for detection: SessionDetection) {
        guard detection.isRedactable else { return }
        mutate { state in
            if enabled {
                state.disabledDetections.remove(detection.id)
            } else {
                state.disabledDetections.insert(detection.id)
            }
        }
    }

    public func toggle(_ detection: SessionDetection) {
        setEnabled(!isEnabled(detection), for: detection)
    }

    /// Enables or disables every redactable detection at once, as one undoable step.
    public func setEnabledForAll(_ enabled: Bool) {
        mutate { state in
            if enabled {
                state.disabledDetections.removeAll()
            } else {
                state.disabledDetections = Set(detected.filter(\.isRedactable).map(\.id))
            }
        }
    }

    @discardableResult
    public func addManualRegion(_ region: RedactionRegion, onPage pageIndex: Int) -> ManualRegion {
        let manual = ManualRegion(pageIndex: pageIndex, region: region)
        mutate { $0.manualRegions.append(manual) }
        return manual
    }

    public func removeManualRegion(id: ManualRegion.ID) {
        mutate { state in state.manualRegions.removeAll { $0.id == id } }
    }

    // MARK: Undo / redo

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(editState)
        editState = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(editState)
        editState = next
    }

    /// The single funnel every edit goes through, so no code path can change state without
    /// recording an undo entry. A mutation that leaves the state unchanged records nothing —
    /// otherwise tapping a toggle twice would need two undos to get back.
    private func mutate(_ change: (inout SessionEditState) -> Void) {
        var updated = editState
        change(&updated)
        guard updated != editState else { return }
        undoStack.append(editState)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        editState = updated
    }

    // MARK: Export input

    /// The regions to destroy on one page: enabled detections plus hand-drawn boxes.
    ///
    /// This is the single derivation from "what the user decided" to "what gets burned in". Export
    /// must call this rather than rebuilding the list, so what the editor previewed and what the
    /// engine destroys cannot drift apart.
    public func activeRegions(onPage pageIndex: Int) -> [RedactionRegion] {
        let fromDetections = detected
            .filter { $0.pageIndex == pageIndex && isEnabled($0) }
            .compactMap { RedactionRegion(detected: $0.pii) }
        return fromDetections + manualRegions(onPage: pageIndex).map(\.region)
    }

    /// Every page's regions, in the shape `RedactionEngine.redactedPDFData(from:redactions:)` wants.
    /// Pages with nothing to redact are omitted, which is what keeps them text-searchable.
    public func pageRedactions() -> [PageRedaction] {
        pages.compactMap { page in
            let regions = activeRegions(onPage: page.index)
            guard !regions.isEmpty else { return nil }
            return PageRedaction(pageIndex: page.index, regions: regions)
        }
    }

    private func clampPageIndex(_ index: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(index, 0), pages.count - 1)
    }
}
