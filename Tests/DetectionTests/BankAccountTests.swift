import XCTest
@testable import RedactApp

/// Bank account number detection.
///
/// Added after driving the shipped onboarding sample by hand and watching
/// `Bank A/C: 0004 1122 3344` survive export while the IFSC code beside it was
/// covered. Redacting the branch code but not the account it identifies is worse
/// than redacting neither — it signals "handled" over a live number.
///
/// The rule is label-gated by design. Account numbers carry no checksum and no
/// fixed length, so an unlabelled digit run cannot be told apart from an invoice
/// total. The negative cases below are the real specification: a detector that
/// flags every number trains the user to approve everything, and then a genuine
/// leak sails through on the tenth document.
final class BankAccountTests: XCTestCase {

    private let detector = PatternDetector()

    // MARK: - True positives

    func testDetectsLabelledAccountNumbers() throws {
        let cases: [(String, String)] = [
            ("Bank A/C: 0004 1122 3344", "0004 1122 3344"),
            ("Bank A/C 0004 1122 3344", "0004 1122 3344"),
            ("A/C No. 123456789012", "123456789012"),
            ("Account Number: 98765432109", "98765432109"),
            ("account no 5001-2345-6789", "5001-2345-6789"),
            ("ACCOUNT #: 000411223344", "000411223344"),
        ]

        for (input, expected) in cases {
            let found = detector.detect(in: input)
            let accounts = found.filter { $0.kind == .bankAccount }
            XCTAssertEqual(accounts.count, 1, "expected one account in \(input.debugDescription)")
            XCTAssertEqual(
                accounts.first?.span.text.trimmingCharacters(in: .whitespaces),
                expected,
                "wrong span captured in \(input.debugDescription)"
            )
        }
    }

    /// The label itself must survive. Covering the words "Bank A/C" hides nothing
    /// and reads as a rendering bug to the user.
    func testRedactsTheNumberButNotTheLabel() throws {
        let found = detector.detect(in: "Bank A/C: 0004 1122 3344")
        let account = try XCTUnwrap(found.first { $0.kind == .bankAccount })

        XCTAssertFalse(account.span.text.lowercased().contains("bank"))
        XCTAssertFalse(account.span.text.contains(":"))
        XCTAssertTrue(account.span.text.contains("0004"))
    }

    /// The exact line from the bundled onboarding sample — the case that exposed
    /// this gap. If this regresses, the flagship demo leaks again.
    func testShippedSampleDocumentLineIsCovered() throws {
        let line = "Bank A/C: 0004 1122 3344    IFSC: HDFC0001234"
        let found = detector.detect(in: line)

        XCTAssertTrue(found.contains { $0.kind == .bankAccount },
                      "the onboarding sample's account number must be detected")
        XCTAssertTrue(found.contains { $0.kind == .ifsc },
                      "adding the account rule must not displace the IFSC match")
    }

    // MARK: - False positives — the harder half

    func testUnlabelledDigitRunsAreNotFlagged() {
        let benign = [
            "Gross Pay 1,25,000.00",
            "Invoice 4500123456789 dated 3 August",
            "Order 987654321098 shipped",
            "Employee ID NWA-2291",
            "Basic Salary 62,500.00",
        ]

        for text in benign {
            let accounts = detector.detect(in: text).filter { $0.kind == .bankAccount }
            XCTAssertTrue(accounts.isEmpty,
                          "false positive on \(text.debugDescription): \(accounts.map(\.span.text))")
        }
    }

    /// Too short to be an account number even with a label present.
    func testShortNumbersAreRejected() {
        let accounts = detector.detect(in: "A/C: 12345").filter { $0.kind == .bankAccount }
        XCTAssertTrue(accounts.isEmpty, "8 digits or fewer is not a bank account")
    }

    /// A Luhn-valid card must stay classified as a card. `creditCard` carries an
    /// actual checksum, so it is the stronger claim and must win the overlap.
    func testCardNumbersRemainCards() throws {
        let found = detector.detect(in: "Account: 4539 1488 0343 6467")

        XCTAssertTrue(found.contains { $0.kind == .creditCard },
                      "a Luhn-valid number is a card, not an account")
        XCTAssertFalse(found.contains { $0.kind == .bankAccount },
                       "overlap resolution must prefer the checksummed kind")
    }
}
