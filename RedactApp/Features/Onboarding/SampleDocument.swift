import CoreGraphics
import Foundation
import UIKit

/// The bundled demo document: a completely fictional salary slip, drawn in code.
///
/// **Why this exists.** App Review runs in a VM where the camera does not work, and a reviewer who
/// cannot reach a redacted result in the first half-minute rejects on "the app does not
/// demonstrate its stated functionality". The sample is the zero-setup path: launch, tap, see real
/// personal information found and covered. It is also the best first run for a normal user, who
/// otherwise has to find a document containing their own Aadhaar before the app can prove anything.
///
/// **Why it is drawn rather than bundled as a PNG.** A binary asset is opaque in review and in
/// diffs — nobody can tell what data is inside it, which is exactly the wrong property for a file
/// whose entire job is to contain believable-looking identifiers. Drawing it means every value on
/// the page is visible as source, right here, and can be audited in one read.
///
/// **Every value on this page is invented.** The domain is `example.com`, reserved by RFC 2606 and
/// therefore incapable of belonging to anyone. The company, the employee, the bank and the employee
/// number do not exist. The Aadhaar-shaped number is `9999 8888 7779` — a deliberately patterned
/// number that passes the Verhoeff checksum (it has to, or `PatternDetector` would not classify it
/// and the demo would show nothing), chosen to look synthetic on sight rather than plausible.
public enum SampleDocument {

    /// The title the session and any saved document carry.
    public static let title = String(
        localized: "Sample salary slip",
        comment: "Title of the built-in demo document"
    )

    /// One-line description shown next to the sample action, so the user knows before tapping that
    /// nothing of theirs is involved.
    public static let subtitle = String(
        localized: "A fictional payslip with invented ID numbers. Nothing here belongs to anyone.",
        comment: "Explains that the demo document contains no real personal information"
    )

    // MARK: - Session

    /// Renders the sample and wraps it in a session ready for ``DocumentPipeline``.
    ///
    /// Rendering happens on a detached task: at 1000×1414 it is a few tens of milliseconds, which is
    /// a visible hitch if it lands on the frame the user's tap is being animated on.
    @MainActor
    public static func makeSession() async -> RedactionSession {
        let data = await Task.detached(priority: .userInitiated) { render() }.value
        return RedactionSession(source: .image(data), title: title)
    }

    // MARK: - The fictional content
    //
    // Held as named constants so an auditor can read the entire set of identifiers the app ships
    // without reading any drawing code.

    private enum Content {
        static let company = "Northwind Analytics Private Limited"
        static let companyAddress = "Plot 41, Sector 12, Whitefield, Bengaluru 560066"
        static let documentTitle = "Salary Slip — August 2026"

        static let employeeName = "Ananya Mehra"
        static let employeeID = "NWA-2291"
        static let designation = "Senior Data Analyst"
        static let dateOfBirth = "Date of Birth: 14/03/1994"

        /// Format is 5 letters, 4 digits, 1 letter. No checksum exists for PAN, so shape is all
        /// that can be validated — and all that can be faked.
        static let pan = "AZZPQ4821K"
        /// Verhoeff-valid, and patterned so it reads as a placeholder to a human.
        static let aadhaar = "9999 8888 7779"
        static let mobile = "+91 90000 12345"
        /// `example.com` is reserved for documentation (RFC 2606) and can never be registered.
        static let email = "ananya.mehra@example.com"
        static let bankAccount = "Bank A/C: 0004 1122 3344"
        /// `ZZZZ` is not an allocated bank code.
        static let ifsc = "IFSC: ZZZZ0123456"

        static let earnings: [(String, String)] = [
            ("Basic Salary", "62,500.00"),
            ("House Rent Allowance", "25,000.00"),
            ("Special Allowance", "31,250.00"),
            ("Transport Allowance", "6,250.00")
        ]

        static let deductions: [(String, String)] = [
            ("Provident Fund", "7,500.00"),
            ("Professional Tax", "200.00"),
            ("Income Tax (TDS)", "14,850.00")
        ]

        static let grossPay = "1,25,000.00"
        static let netPay = "1,02,450.00"
        static let footnote = "This is a computer-generated statement and does not require a signature."
    }

    // MARK: - Paper
    //
    // These are ink-on-paper values, not app chrome: a payslip is white with black print, and
    // rendering it in the app's navy-and-violet palette would make it useless as a stand-in for a
    // real scanned document. `DesignSystem` tokens describe the *interface*; this is the *content*
    // the interface operates on, which is why CLAUDE.md rule 3's tokens do not apply inside this
    // renderer. Nothing here escapes into a view.

    private enum Paper {
        static let size = CGSize(width: 1000, height: 1414)
        static let margin: CGFloat = 72

        static let stock = UIColor(white: 0.99, alpha: 1)
        static let ink = UIColor(white: 0.11, alpha: 1)
        static let inkSoft = UIColor(white: 0.42, alpha: 1)
        static let rule = UIColor(white: 0.80, alpha: 1)
        static let band = UIColor(white: 0.94, alpha: 1)
        static let brand = UIColor(red: 0.09, green: 0.22, blue: 0.42, alpha: 1)
    }

    // MARK: - Rendering

    /// Draws the payslip and returns PNG bytes.
    ///
    /// PNG rather than JPEG because the export path re-reads these exact pixels: JPEG ringing
    /// around 9pt print measurably costs Vision recognitions, and a demo that misses a detection is
    /// worse than no demo.
    ///
    /// `nonisolated` and self-contained — every UIKit object is created, used and released inside
    /// this call, so nothing non-`Sendable` crosses an isolation boundary (CLAUDE.md rule 5).
    static func render() -> Data {
        let bounds = CGRect(origin: .zero, size: Paper.size)
        let format = UIGraphicsImageRendererFormat.preferred()
        // Layout is authored in the 1000×1414 space above; rendering at 2× puts ~240 pixels per
        // inch of simulated A4 behind it. Vision reads 10pt print reliably at that density and
        // starts dropping characters below about 150 — and a demo whose whole purpose is to show a
        // detection cannot afford to miss one on a slow device. Scaling here rather than doubling
        // every constant keeps the drawing code readable.
        format.scale = 2
        format.opaque = true

        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            Paper.stock.setFill()
            UIBezierPath(rect: bounds).fill()

            var y = Paper.margin
            y = drawHeader(top: y)
            y = drawEmployeeBlock(top: y + 34)
            y = drawTables(top: y + 34)
            drawFooter(top: y + 28)
        }

        // The renderer always produces a bitmap, so PNG encoding cannot fail here; an empty
        // fallback would be a silent blank demo, which is worse than a loud crash in a path that
        // has no runtime inputs to vary.
        guard let data = image.pngData() else {
            preconditionFailure("UIGraphicsImageRenderer produced an image that cannot be encoded as PNG")
        }
        return data
    }

    private static func drawHeader(top: CGFloat) -> CGFloat {
        var y = top

        // Company mark: a filled square with initials, standing in for a letterhead logo.
        let markSide: CGFloat = 64
        let markRect = CGRect(x: Paper.margin, y: y, width: markSide, height: markSide)
        Paper.brand.setFill()
        UIBezierPath(roundedRect: markRect, cornerRadius: 10).fill()
        draw("NA", font: .systemFont(ofSize: 26, weight: .bold), color: .white,
             in: markRect.offsetBy(dx: 0, dy: 16), alignment: .center)

        let textX = Paper.margin + markSide + 20
        let textWidth = Paper.size.width - textX - Paper.margin
        draw(Content.company, font: .systemFont(ofSize: 26, weight: .bold), color: Paper.ink,
             in: CGRect(x: textX, y: y + 4, width: textWidth, height: 34))
        draw(Content.companyAddress, font: .systemFont(ofSize: 16, weight: .regular), color: Paper.inkSoft,
             in: CGRect(x: textX, y: y + 38, width: textWidth, height: 24))

        y += markSide + 26
        drawRule(y: y)
        y += 22

        draw(Content.documentTitle, font: .systemFont(ofSize: 21, weight: .semibold), color: Paper.ink,
             in: CGRect(x: Paper.margin, y: y, width: contentWidth, height: 28))
        return y + 28
    }

    private static func drawEmployeeBlock(top: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 34
        let left: [(String, String)] = [
            ("Employee", Content.employeeName),
            ("Employee ID", Content.employeeID),
            ("Designation", Content.designation),
            ("", Content.dateOfBirth)
        ]
        let right: [(String, String)] = [
            ("PAN", Content.pan),
            ("Aadhaar", Content.aadhaar),
            ("Mobile", Content.mobile),
            ("Email", Content.email)
        ]

        let blockHeight = rowHeight * CGFloat(max(left.count, right.count)) + 28
        let blockRect = CGRect(x: Paper.margin, y: top, width: contentWidth, height: blockHeight)
        Paper.band.setFill()
        UIBezierPath(roundedRect: blockRect, cornerRadius: 8).fill()

        let columnWidth = (contentWidth - 48) / 2
        drawFieldColumn(left, x: Paper.margin + 16, top: top + 14, width: columnWidth, rowHeight: rowHeight)
        drawFieldColumn(right, x: Paper.margin + 32 + columnWidth, top: top + 14, width: columnWidth, rowHeight: rowHeight)

        var y = top + blockHeight + 16
        draw("\(Content.bankAccount)    \(Content.ifsc)",
             font: .systemFont(ofSize: 17, weight: .regular), color: Paper.ink,
             in: CGRect(x: Paper.margin, y: y, width: contentWidth, height: 24))
        y += 24
        return y
    }

    private static func drawFieldColumn(
        _ fields: [(String, String)],
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        rowHeight: CGFloat
    ) {
        for (index, field) in fields.enumerated() {
            let y = top + CGFloat(index) * rowHeight
            let labelWidth: CGFloat = 120
            if !field.0.isEmpty {
                draw(field.0, font: .systemFont(ofSize: 15, weight: .regular), color: Paper.inkSoft,
                     in: CGRect(x: x, y: y + 3, width: labelWidth, height: 22))
            }
            let valueX = field.0.isEmpty ? x : x + labelWidth
            draw(field.1, font: .systemFont(ofSize: 18, weight: .medium), color: Paper.ink,
                 in: CGRect(x: valueX, y: y, width: width - (valueX - x), height: 26))
        }
    }

    private static func drawTables(top: CGFloat) -> CGFloat {
        var y = top
        y = drawTable(title: "Earnings", rows: Content.earnings, total: ("Gross Pay", Content.grossPay), top: y)
        y = drawTable(title: "Deductions", rows: Content.deductions, total: ("Net Pay", Content.netPay), top: y + 24)
        return y
    }

    private static func drawTable(
        title: String,
        rows: [(String, String)],
        total: (String, String),
        top: CGFloat
    ) -> CGFloat {
        var y = top
        draw(title.uppercased(), font: .systemFont(ofSize: 14, weight: .semibold), color: Paper.inkSoft,
             in: CGRect(x: Paper.margin, y: y, width: contentWidth, height: 20))
        y += 24
        drawRule(y: y)
        y += 12

        for row in rows {
            draw(row.0, font: .systemFont(ofSize: 17, weight: .regular), color: Paper.ink,
                 in: CGRect(x: Paper.margin, y: y, width: contentWidth - 220, height: 26))
            draw("₹ \(row.1)", font: .monospacedDigitSystemFont(ofSize: 17, weight: .regular), color: Paper.ink,
                 in: CGRect(x: Paper.size.width - Paper.margin - 220, y: y, width: 220, height: 26),
                 alignment: .right)
            y += 30
        }

        y += 4
        drawRule(y: y)
        y += 12
        draw(total.0, font: .systemFont(ofSize: 18, weight: .semibold), color: Paper.ink,
             in: CGRect(x: Paper.margin, y: y, width: contentWidth - 220, height: 26))
        draw("₹ \(total.1)", font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold), color: Paper.ink,
             in: CGRect(x: Paper.size.width - Paper.margin - 220, y: y, width: 220, height: 26),
             alignment: .right)
        return y + 30
    }

    private static func drawFooter(top: CGFloat) {
        drawRule(y: top)
        draw(Content.footnote, font: .systemFont(ofSize: 14, weight: .regular), color: Paper.inkSoft,
             in: CGRect(x: Paper.margin, y: top + 12, width: contentWidth, height: 22))
    }

    // MARK: - Primitives

    private static var contentWidth: CGFloat { Paper.size.width - Paper.margin * 2 }

    private static func drawRule(y: CGFloat) {
        Paper.rule.setFill()
        UIBezierPath(rect: CGRect(x: Paper.margin, y: y, width: contentWidth, height: 1)).fill()
    }

    private static func draw(
        _ string: String,
        font: UIFont,
        color: UIColor,
        in rect: CGRect,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        ).draw(in: rect)
    }
}
