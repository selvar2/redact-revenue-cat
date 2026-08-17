import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UIKit

/// The one implementation of "source bytes in, populated session out".
///
/// Scan, Library re-open and the sample document all call ``run(on:classifier:)``. Nobody
/// reimplements it, because every reimplementation is a chance to get the coordinate flip, the
/// page indices, or the actor hopping subtly wrong — and each of those failures is silent: the app
/// looks like it worked and ships a document with live personal information on it.
///
/// Shape of the work:
///
/// ```
/// @MainActor  session.setProcessing(.recognising)
///   detached  render pages   (PDFKit → PNG Data, or the source image as-is)
/// @MainActor  session.setPages(...)              ← pages visible while OCR is still running
///   detached  TextRecogniser.recognise(...)      per page
/// @MainActor  session.setProcessing(.classifying)
///   detached  PIIClassifier.classify(...)        per page
/// @MainActor  session.setDetections(...) ; .ready
/// ```
///
/// Only `Data` and `Sendable` value types cross the boundary. `PDFDocument`, `CGImage` and
/// `UIImage` never leave the function body that made them (CLAUDE.md rule 5).
public enum DocumentPipeline {

    /// Pixels per point when rasterising a PDF page for OCR and display.
    ///
    /// 2.0 is the smallest scale at which Vision reliably reads 8pt print — the size a bank account
    /// number is usually set in. Lower, and detections are missed; higher, and a 20-page statement
    /// costs hundreds of megabytes of decoded images for no accuracy gain.
    public static let pageRasterScale: CGFloat = 2

    // MARK: - Entry point

    /// Renders, recognises and classifies `session`'s source, updating the session as it goes.
    ///
    /// Progress is published in stages rather than at the end, so the editor can show page one
    /// while page nine is still being read. Cancelling the calling `Task` cancels the whole run;
    /// the session is left in `.idle` rather than `.failed`, because a cancelled run is not an
    /// error the user should be told about.
    ///
    /// - Parameter classifier: injectable so tests can force the iOS 17 heuristic path
    ///   (`ClassifierFactory.makeHeuristic()`), per DEC-003.
    /// `@MainActor` because it reads and writes session state directly; the expensive work is
    /// pushed off the actor by the detached tasks inside ``renderPages(from:)`` and by
    /// `TextRecogniser`, which detaches internally. The main actor is never blocked, only resumed.
    @MainActor
    public static func run(
        on session: RedactionSession,
        classifier: any PIIClassifier = ClassifierFactory.make()
    ) async {
        let source = session.source
        session.setProcessing(.recognising)

        do {
            let pages = try await renderPages(from: source)
            try Task.checkCancellation()
            session.setPages(pages)

            let recogniser = TextRecogniser(accuracy: .accurate)
            var recognisedByPage: [(Int, RecognisedText)] = []
            for page in pages {
                try Task.checkCancellation()
                let recognised = try await recogniser.recognise(imageData: page.imageData)
                recognisedByPage.append((page.index, recognised))
            }

            session.setProcessing(.classifying)

            var detections: [SessionDetection] = []
            for (pageIndex, recognised) in recognisedByPage {
                try Task.checkCancellation()
                guard !recognised.isEmpty else { continue }
                let classified = try await classifier.classify(recognised.spans)
                detections += classified.map { SessionDetection(pageIndex: pageIndex, pii: $0) }
            }

            try Task.checkCancellation()
            session.setDetections(detections)
            session.setProcessing(.ready)
        } catch is CancellationError {
            session.setProcessing(.idle)
        } catch {
            session.setProcessing(.failed(error))
        }
    }

    // MARK: - Page rendering

    /// Turns source bytes into one PNG per page.
    ///
    /// An image source is passed through untouched rather than re-encoded: re-encoding would change
    /// the pixels Vision reads and the bytes the export path later redacts, and those two must be
    /// the same image or a bar lands in the wrong place.
    public static func renderPages(from source: SessionSource) async throws -> [SessionPage] {
        switch source {
        case .image(let data):
            let size = try await Task.detached(priority: .userInitiated) {
                try imagePixelSize(of: data)
            }.value
            return [SessionPage(index: 0, imageData: data, pixelSize: size)]

        case .pdf(let data):
            let scale = pageRasterScale
            return try await Task.detached(priority: .userInitiated) {
                try rasterisePDF(data, scale: scale)
            }.value
        }
    }

    /// Reads pixel dimensions from the image header without decoding the whole bitmap — a 48MP
    /// photo would otherwise cost tens of megabytes just to learn its aspect ratio.
    private static func imagePixelSize(of data: Data) throws -> CGSize {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double
        else {
            throw PipelineError.unreadableSource
        }

        // A photo shot sideways stores its dimensions unrotated and an orientation tag beside them.
        // Reporting the stored size would give the editor a landscape frame for a portrait page.
        let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let isTransposed = (5...8).contains(orientationValue)
        return isTransposed ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Rasterises every page of a PDF to PNG.
    ///
    /// Runs entirely inside one detached call so `PDFDocument` — which is not `Sendable` — is
    /// created, used and destroyed without ever crossing an isolation boundary.
    private static func rasterisePDF(_ data: Data, scale: CGFloat) throws -> [SessionPage] {
        guard let document = PDFDocument(data: data) else { throw PipelineError.unreadableSource }
        guard document.pageCount > 0 else { throw PipelineError.emptyDocument }

        var pages: [SessionPage] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw PipelineError.pageRenderFailed(index) }

            let box = page.bounds(for: .mediaBox)
            // A page rotated 90° or 270° presents transposed dimensions, and `thumbnail(of:for:)`
            // honours the rotation — so the requested size must be transposed to match, exactly as
            // `RedactionEngine.rasterisedPage` does. The two must agree or the preview and the
            // export disagree about which way is up.
            let isTransposed = abs(page.rotation) % 180 == 90
            let pointSize = isTransposed ? CGSize(width: box.height, height: box.width) : box.size
            guard pointSize.width > 0, pointSize.height > 0 else {
                throw PipelineError.pageRenderFailed(index)
            }

            let pixelSize = CGSize(
                width: (pointSize.width * scale).rounded(),
                height: (pointSize.height * scale).rounded()
            )
            guard let png = page.thumbnail(of: pixelSize, for: .mediaBox).pngData() else {
                throw PipelineError.pageRenderFailed(index)
            }
            pages.append(SessionPage(index: index, imageData: png, pixelSize: pixelSize))
        }
        return pages
    }

    // MARK: - Errors

    /// Failures a user can be shown and can recover from. Every case has a recovery path in the UI:
    /// pick a different file, or continue with manual redaction only.
    public enum PipelineError: Error, Sendable, Equatable, LocalizedError {
        case unreadableSource
        case emptyDocument
        case pageRenderFailed(Int)

        public var errorDescription: String? {
            switch self {
            case .unreadableSource:
                return String(localized: "This file could not be opened.",
                              comment: "Error shown when an imported document cannot be decoded")
            case .emptyDocument:
                return String(localized: "This document has no pages.",
                              comment: "Error shown when an imported PDF contains zero pages")
            case .pageRenderFailed(let index):
                return String(localized: "Page \(index + 1) could not be prepared.",
                              comment: "Error shown when one page of a document fails to render")
            }
        }

        public var recoverySuggestion: String? {
            String(localized: "Try a different file, or take a photo of the page instead.",
                   comment: "Recovery suggestion for a document that could not be prepared")
        }
    }
}
