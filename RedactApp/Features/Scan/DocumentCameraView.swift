import SwiftUI
import UIKit
import VisionKit

/// SwiftUI wrapper around `VNDocumentCameraViewController`.
///
/// We use VisionKit rather than a bare `AVCaptureSession` because it already does the two hard
/// things — live page-edge detection and perspective correction — and does them better than we
/// would. A photo of a page taken at an angle produces a trapezoid; Vision's OCR reads trapezoidal
/// text poorly, and every miss is personal information left on the page. Rebuilding that would be
/// weeks of work to arrive somewhere worse.
///
/// The controller is created once and never reconfigured: `updateUIViewController` is deliberately
/// empty, because re-assigning the delegate or pushing state into a camera mid-session is how you
/// get a controller that fires its callback twice.
struct DocumentCameraView: UIViewControllerRepresentable {

    /// How the capture ended.
    ///
    /// `[UIImage]` rather than `Data` because that is what VisionKit hands us, and converting here
    /// would block the main actor while the camera is still dismissing. ``ImportPipeline`` does the
    /// encoding a moment later, behind the progress overlay, where the user can see it happening.
    /// The payload is not `Sendable`, which is exactly why ``onFinish`` is `@MainActor` — the images
    /// never leave the actor they were created on.
    enum Outcome {
        case completed([UIImage])
        case cancelled
        case failed(any Error)
    }

    /// Called exactly once, on the main actor. The caller is responsible for dismissing.
    let onFinish: @MainActor (Outcome) -> Void

    /// Whether this device can scan at all.
    ///
    /// False in the Simulator, and false on any device without the required camera. Callers must
    /// check it *before* presenting: presenting an unsupported controller shows a black screen with
    /// no way out, which is a dead end (`CLAUDE.md` rule 10).
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// The delegate.
    ///
    /// It holds the callback and nothing else — in particular it never holds the controller. The
    /// controller holds the delegate `weak`, SwiftUI holds the coordinator, and the coordinator
    /// holds only a closure owned by the presenting view, so the graph is acyclic and the whole
    /// thing deallocates when the cover dismisses.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {

        private let onFinish: @MainActor (Outcome) -> Void

        /// VisionKit can deliver a cancel *and* a save in rare teardown races, and a second callback
        /// after the caller has already navigated away would push a duplicate editor onto the stack.
        private var hasFinished = false

        init(onFinish: @escaping @MainActor (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        private func finish(_ outcome: Outcome) {
            guard !hasFinished else { return }
            hasFinished = true
            onFinish(outcome)
        }

        // The three delegate methods are `nonisolated` witnesses that immediately re-enter the main
        // actor. VisionKit documents these as main-thread callbacks, so `assumeIsolated` is a
        // statement of a fact the compiler cannot see rather than a hop that might fail — and it
        // keeps the file compiling whether or not the SDK annotates the protocol as `@MainActor`.

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [UIImage] = []
            pages.reserveCapacity(scan.pageCount)
            for index in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: index))
            }
            finish(pages.isEmpty ? .failed(ImportPipeline.ImportError.emptyScan) : .completed(pages))
        }

        nonisolated func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            MainActor.assumeIsolated { finish(.cancelled) }
        }

        nonisolated func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            MainActor.assumeIsolated { finish(.failed(error)) }
        }
    }
}
