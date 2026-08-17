import XCTest
import SwiftUI
@testable import RedactApp

/// Phase 0 smoke tests.
///
/// These exist to prove the test target is wired and the token layer matches its
/// spec — not to chase coverage. Real behavioural tests arrive with the detection
/// engine (F03) and the redaction core (F04), where the irreversibility test is
/// the one that actually matters.
final class DesignSystemTests: XCTestCase {

    /// Tokens are the contract between DEC-002 and every view. If a hex drifts,
    /// the whole design language drifts silently — so pin the ones that define
    /// the app's identity.
    func testSignatureAccentsMatchDesignSpec() {
        assertColor(Token.Accent.violet, equals: (0xA8, 0x55, 0xF7), name: "accentViolet")
        assertColor(Token.Accent.amber, equals: (0xFF, 0x6B, 0x3D), name: "accentAmber")
        assertColor(Token.BG.base, equals: (0x0A, 0x0E, 0x1A), name: "bg.base")
    }

    func testSpacingScaleIsMonotonic() {
        let scale = [Token.Space.xs, Token.Space.sm, Token.Space.md,
                     Token.Space.lg, Token.Space.xl]
        XCTAssertEqual(scale, scale.sorted(),
                       "Spacing scale must increase monotonically to stay predictable in layouts.")
    }

    // MARK: - Helper

    private func assertColor(
        _ color: Color,
        equals expected: (UInt8, UInt8, UInt8),
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)

        let actual = (UInt8(round(r * 255)), UInt8(round(g * 255)), UInt8(round(b * 255)))
        XCTAssertEqual(actual.0, expected.0, "\(name) red channel", file: file, line: line)
        XCTAssertEqual(actual.1, expected.1, "\(name) green channel", file: file, line: line)
        XCTAssertEqual(actual.2, expected.2, "\(name) blue channel", file: file, line: line)
    }
}
