import XCTest
@testable import RedactApp

/// The checksum layer is what separates detection from guessing. If these tests are wrong,
/// every downstream assertion about false positives is meaningless.
final class ChecksumTests: XCTestCase {

    // MARK: - Verhoeff

    func testVerhoeffAcceptsValidAadhaarNumbers() {
        for number in DetectionFixtures.validAadhaar {
            XCTAssertTrue(Checksum.Verhoeff.isValid(number),
                          "\(number) should pass Verhoeff")
        }
    }

    func testVerhoeffRejectsWrongCheckDigit() {
        for number in DetectionFixtures.verhoeffFailingAadhaar {
            XCTAssertFalse(Checksum.Verhoeff.isValid(number),
                           "\(number) has a bad check digit and must fail Verhoeff")
        }
    }

    /// Verhoeff's whole point is catching the two errors OCR actually makes.
    func testVerhoeffCatchesEverySingleDigitErrorAndAdjacentTransposition() {
        let valid = Array(DetectionFixtures.validAadhaar[0])

        for position in valid.indices {
            for replacement in "0123456789" where replacement != valid[position] {
                var mutated = valid
                mutated[position] = replacement
                XCTAssertFalse(Checksum.Verhoeff.isValid(String(mutated)),
                               "single-digit error at \(position) slipped through")
            }
        }

        for position in 0 ..< (valid.count - 1) where valid[position] != valid[position + 1] {
            var mutated = valid
            mutated.swapAt(position, position + 1)
            XCTAssertFalse(Checksum.Verhoeff.isValid(String(mutated)),
                           "transposition at \(position) slipped through")
        }
    }

    /// The fixtures are derived, not memorised — this proves it, so a future agent can mint
    /// more of them without hunting for real numbers.
    func testVerhoeffCheckDigitReproducesTheFixtures() {
        for number in DetectionFixtures.validAadhaar {
            let body = String(number.dropLast())
            let expected = number.last.flatMap { $0.wholeNumberValue }
            XCTAssertEqual(Checksum.Verhoeff.checkDigit(for: body), expected,
                           "check digit for \(body) does not reproduce \(number)")
        }
    }

    func testVerhoeffRejectsNonDigits() {
        XCTAssertFalse(Checksum.Verhoeff.isValid("23456789012A"))
        XCTAssertFalse(Checksum.Verhoeff.isValid(""))
    }

    // MARK: - Luhn

    func testLuhnAcceptsValidCards() {
        for card in DetectionFixtures.luhnValidCards {
            XCTAssertTrue(Checksum.isLuhnValid(card), "\(card) should pass Luhn")
        }
    }

    func testLuhnRejectsInvalidCards() {
        for card in DetectionFixtures.luhnInvalidCards {
            XCTAssertFalse(Checksum.isLuhnValid(card), "\(card) must fail Luhn")
        }
    }

    func testLuhnRejectsNonDigitsAndDegenerateInput() {
        XCTAssertFalse(Checksum.isLuhnValid("4539241592066 14"))
        XCTAssertFalse(Checksum.isLuhnValid("0"))
    }

    // MARK: - GSTIN

    func testGSTINChecksumAcceptsValidNumbers() {
        for gstin in DetectionFixtures.validGSTIN {
            XCTAssertTrue(Checksum.isGSTINChecksumValid(gstin), "\(gstin) should pass")
        }
    }

    func testGSTINChecksumRejectsAWrongCheckCharacter() {
        XCTAssertFalse(Checksum.isGSTINChecksumValid("27ABCDE1234F1Z9"))
        XCTAssertFalse(Checksum.isGSTINChecksumValid("27ABCDE1234F1Z"))
    }

    func testGSTINCheckCharacterReproducesTheFixtures() {
        for gstin in DetectionFixtures.validGSTIN {
            let body = String(gstin.dropLast())
            XCTAssertEqual(Checksum.gstinCheckCharacter(forBody: body), gstin.last,
                           "check character for \(body) does not reproduce \(gstin)")
        }
    }
}
