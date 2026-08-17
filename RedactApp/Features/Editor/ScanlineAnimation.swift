import SwiftUI
import UIKit

/// The signature moment: a violet→amber scanline sweeps the page, each detection fades in with a
/// small bounce as the line crosses it, and when the sweep lands the bars slam into place with a
/// single impact haptic.
///
/// DEC-002 calls this "the screenshot that wins or loses the Design Award", so the mechanics are
/// worth stating plainly:
///
/// - The stagger is **geometric, not scheduled.** There is no per-box timer. Every box knows its own
///   vertical midpoint in normalised 0...1 page coordinates and reveals itself when ``progress``
///   passes it. A page with detections spread down its length therefore reveals them in reading
///   order, at the speed of the line, for free — and the animation stays correct if a detection is
///   added, removed, or the page is re-laid-out mid-sweep.
/// - The sweep is one animated `Double`. Nothing else moves; "premium, not busy" is mostly a
///   question of how many things are in flight at once.
/// - Under reduced motion the whole thing collapses to a cross-fade: ``progress`` goes straight to
///   1, the band is never drawn, and **the haptic does not fire.** A user who has asked the system
///   to calm down should not be punched in the hand by a vestibular-safe UI.
@Observable
@MainActor
final class ScanlineDirector {

    /// Where the sweep is, 0 (top of page) to 1 (bottom).
    private(set) var progress: Double = 0

    /// True once the sweep has completed and the bars have landed.
    private(set) var hasLanded = false

    /// True while the band itself should be drawn.
    private(set) var isSweeping = false

    /// Has this director already run for the current page? Re-entering the editor, rotating the
    /// device, or a stray view rebuild must not replay the sweep — it is a reveal, and a reveal that
    /// repeats reads as a glitch.
    private var hasRun = false

    /// How long the sweep takes. DEC-002's meter duration, reused so the editor's headline motion is
    /// the same tempo as every progress fill in the app.
    private let sweepDuration = Motion.Duration.meter

    /// Runs the reveal. Idempotent: the second call is a no-op.
    ///
    /// - Parameter reduceMotion: read from the environment by the caller. Passed in rather than read
    ///   here because an `@Observable` model has no environment, and inventing one would put the
    ///   accessibility decision somewhere a reviewer cannot see it.
    func reveal(reduceMotion: Bool) async {
        guard !hasRun else { return }
        hasRun = true

        guard !reduceMotion else {
            withAnimation(Motion.crossFade) {
                progress = 1
                hasLanded = true
            }
            return
        }

        isSweeping = true
        withAnimation(Motion.meter) { progress = 1 }

        try? await Task.sleep(nanoseconds: UInt64(sweepDuration * 1_000_000_000))
        guard !Task.isCancelled else { return }

        isSweeping = false
        land()
    }

    /// Skips straight to the landed state — used when the user starts editing before the sweep has
    /// finished. An animation must never be a gate on a control.
    func settleImmediately() {
        hasRun = true
        isSweeping = false
        progress = 1
        hasLanded = true
    }

    /// True when the sweep has passed a detection sitting at `normalisedMidY` down the page.
    func hasReached(_ normalisedMidY: CGFloat) -> Bool {
        hasLanded || progress >= Double(normalisedMidY)
    }

    private func land() {
        withAnimation(Motion.standard) { hasLanded = true }
        Haptics.barsLanded()
    }
}

// MARK: - Haptics

/// The one impact in the app.
///
/// Wrapped rather than called inline so there is a single place to check that we are not firing
/// feedback the user asked not to receive, and so no other agent adds a second generator with a
/// different intensity.
enum Haptics {
    /// The bars landing. `.rigid` because the gesture being described is a solid object arriving,
    /// not a soft one — the metaphor is a stamp, and a `.light` tap undersells it.
    ///
    /// Only ever called from the non-reduced-motion path in ``ScanlineDirector/reveal(reduceMotion:)``.
    @MainActor
    static func barsLanded() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - The band

/// The sweeping band itself: a violet→amber gradient with a soft leading glow.
///
/// Drawn as an overlay sized to the page content, so it travels exactly the page's height however
/// the document is aspect-fitted.
@MainActor
struct ScanlineSweep: View {

    /// 0...1 down the page.
    let progress: Double
    let contentSize: CGSize

    var body: some View {
        let height = EditorMetric.scanlineHeight
        let y = contentSize.height * CGFloat(progress)

        ZStack(alignment: .top) {
            // The trailing wash: everything the line has already passed sits under a faint gradient
            // veil, which is what makes the sweep read as *processing* rather than as a stray line.
            Rectangle()
                .fill(Token.gradientSoft)
                .frame(width: contentSize.width, height: max(y, 0))
                .frame(maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Token.Accent.violet.opacity(0),
                            Token.Accent.violetLight,
                            Token.Accent.amberLight,
                            Token.Accent.amber.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: contentSize.width, height: height)
                .shadow(Token.Shadow.glow)
                .offset(y: y - height / 2)
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Scanline") {
    ScanlineSweep(progress: 0.45, contentSize: CGSize(width: 280, height: 380))
        .frame(width: 280, height: 380)
        .background(Token.BG.card)
        .padding(Token.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ambientBackground()
        .preferredColorScheme(.dark)
}
