import Foundation
@testable import RedactApp

/// Fixture corpus for the detection engine.
///
/// **Every value here is fabricated.** The identifiers are structurally valid — they pass
/// Verhoeff, Luhn, and the GSTIN check character — because a corpus of invalid numbers cannot
/// prove the detector works. None of them belong to a real person, account, or business, and
/// none may ever be replaced with real data: this file is committed to a public repository.
///
/// The negative corpus matters as much as the positive one. A redaction tool that flags every
/// long number teaches users to click "accept all", and that is how real personal information
/// slips through.
enum DetectionFixtures {

    // MARK: - Aadhaar

    /// 12 digits, first digit 2–9, Verhoeff-valid. Derived, not invented — see
    /// ``Checksum/Verhoeff/checkDigit(for:)``, which the tests re-derive them with.
    static let validAadhaar = [
        "234567890124",
        "987654321096",
        "543210987652",
        "789012345674",
    ]

    /// Correct shape and length, wrong final digit. These must never be flagged.
    static let verhoeffFailingAadhaar = [
        "234567890123",
        "987654321098",
        "543210987651",
    ]

    /// Real Aadhaar numbers never begin with 0 or 1, so these are rejected on shape alone.
    static let malformedAadhaar = [
        "123456789012",
        "012345678901",
    ]

    // MARK: - PAN

    static let validPAN = ["ABCDE1234F", "AAGCB1286Q", "AAACH7409R"]

    /// Wrong shape: too few letters, digits in the wrong place, or a trailing digit.
    static let invalidPAN = ["ABCD1234F", "ABCDE12345", "ABCDE1234", "1BCDE1234F"]

    // MARK: - GSTIN

    /// State code + PAN + entity digit + Z + valid base-36 check character.
    static let validGSTIN = [
        "27ABCDE1234F1Z0",
        "29AAGCB1286Q1Z0",
        "07AAACH7409R1Z3",
    ]

    /// Right shape, wrong check character or an out-of-range state code.
    static let invalidGSTIN = [
        "27ABCDE1234F1Z9",  // check character does not match the body
        "99ABCDE1234F1Z0",  // no state 99
    ]

    // MARK: - IFSC

    static let validIFSC = ["HDFC0001234", "SBIN0000456", "ICIC0AB1234"]

    /// The fifth character of an IFSC is always a literal zero.
    static let invalidIFSC = ["HDFC1001234", "HDF00001234", "HDFC000123"]

    // MARK: - Payment cards

    /// Luhn-valid, 13 to 19 digits, spanning the common network prefixes.
    static let luhnValidCards = [
        "4539241592066114",     // 16, Visa-shaped
        "5500241592066116",     // 16, Mastercard-shaped
        "378282266473782",      // 15, Amex-shaped
        "6011241592066116",     // 16, Discover-shaped
        "4198344417470",        // 13, short Visa
        "6212345674431148544",  // 19, long UnionPay-shaped
    ]

    /// Card-shaped, Luhn-failing. The commonest real-world source of these is an order number.
    static let luhnInvalidCards = [
        "4539578763621487",
        "1234567812345678",
        "4111111111111112",
    ]

    // MARK: - Contact details

    static let validEmails = [
        "priya.sharma@example.com",
        "r.kumar+billing@mail.example.co.in",
        "accounts@vendor-name.example.org",
    ]

    static let validIndianPhones = [
        "9876543210",
        "+91 98765 43210",
        "+91-9876543210",
    ]

    static let validInternationalPhones = [
        "+1 415 555 0198",
        "+44 20 7946 0958",
    ]

    // MARK: - Negative corpus

    /// Text that looks numeric and official but contains no personal information.
    /// Anything flagged here is a false positive and a bug.
    static let negativeDocument = """
    TAX INVOICE
    Invoice Number: INV-2024-0001
    Order ID: 1234567812345678
    Purchase Order: PO-8842-99017
    Invoice Date: 2024-01-15
    Due Date: 15/02/2024
    Reference: ABCDE12345
    HSN Code: 998314
    Quantity: 12 units at 4,999.00
    Subtotal: 59988.00
    Total Payable: 123456789012
    Tracking: ORD-8901234567
    PIN Code: 600001
    """

    /// A realistic mixed document. Fake throughout.
    static let mixedDocument = """
    KYC VERIFICATION FORM
    Applicant: Priya Sharma
    Date of Birth: 12/04/1991
    Aadhaar Number: 2345 6789 0124
    PAN: ABCDE1234F
    Email: priya.sharma@example.com
    Mobile: +91 98765 43210
    Bank: IFSC HDFC0001234
    Card on file: 4539 2415 9206 6114
    Employer GSTIN: 27ABCDE1234F1Z0
    Invoice reference INV-2024-0001 dated 2024-01-15
    """
}
