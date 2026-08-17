import Foundation

/// Checksum validators for the structured identifiers Redact detects.
///
/// These are the difference between a useful tool and one that blacks out random numbers.
/// A bare `\d{12}` matches invoice totals, order IDs, and concatenated phone lists; on a
/// real invoice that is a false-positive rate high enough that users stop trusting the
/// review screen and start accepting everything — which is how genuine PII gets missed.
public enum Checksum {

    // MARK: - Verhoeff (Aadhaar)

    /// Verhoeff dihedral-group checksum, as used by UIDAI for Aadhaar numbers.
    ///
    /// Catches all single-digit errors and all adjacent transpositions, which is precisely
    /// the failure mode of OCR on a scanned card.
    public enum Verhoeff {
        /// Multiplication table for the dihedral group D5.
        private static let d: [[Int]] = [
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
            [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
            [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
            [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
            [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
            [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
            [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
            [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
            [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
        ]

        /// Permutation table, applied with period 8 across the digit positions.
        private static let p: [[Int]] = [
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
            [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
            [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
            [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
            [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
            [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
            [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
        ]

        /// Multiplicative inverse table for D5.
        private static let inverse: [Int] = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9]

        /// True when `digits` (a digits-only string, check digit included) validates.
        public static func isValid(_ digits: String) -> Bool {
            guard !digits.isEmpty else { return false }
            var c = 0
            for (i, character) in digits.reversed().enumerated() {
                guard let value = character.wholeNumberValue, (0...9).contains(value) else {
                    return false
                }
                c = d[c][p[i % 8][value]]
            }
            return c == 0
        }

        /// The check digit that would make `body` (payload without its check digit) valid.
        ///
        /// Used by the tests to mint fake-but-well-formed fixtures rather than hardcoding
        /// numbers nobody can re-derive.
        public static func checkDigit(for body: String) -> Int? {
            var c = 0
            for (i, character) in body.reversed().enumerated() {
                guard let value = character.wholeNumberValue, (0...9).contains(value) else {
                    return nil
                }
                c = d[c][p[(i + 1) % 8][value]]
            }
            return inverse[c]
        }
    }

    // MARK: - Luhn (payment cards)

    /// Luhn mod-10 checksum, as used by every major card network.
    public static func isLuhnValid(_ digits: String) -> Bool {
        guard digits.count >= 2 else { return false }
        var sum = 0
        for (i, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue, (0...9).contains(value) else {
                return false
            }
            if i % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    // MARK: - GSTIN

    /// Alphabet for the GSTIN base-36 checksum. Index in this string *is* the digit value.
    private static let base36 = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Validates the 15th character of a GSTIN against the preceding 14.
    ///
    /// Weights alternate 1, 2 from the left; each product is folded as
    /// `quotient + remainder` in base 36, and the check character completes the sum to a
    /// multiple of 36.
    public static func isGSTINChecksumValid(_ gstin: String) -> Bool {
        let characters = Array(gstin.uppercased())
        guard characters.count == 15 else { return false }
        guard let expected = gstinCheckCharacter(forBody: String(characters.prefix(14))) else {
            return false
        }
        return characters[14] == expected
    }

    /// The check character completing a 14-character GSTIN body, or `nil` if the body is malformed.
    public static func gstinCheckCharacter(forBody body: String) -> Character? {
        let characters = Array(body.uppercased())
        guard characters.count == 14 else { return nil }
        var sum = 0
        for (i, character) in characters.enumerated() {
            guard let value = base36.firstIndex(of: character) else { return nil }
            let product = value * (i % 2 == 0 ? 1 : 2)
            sum += product / 36 + product % 36
        }
        return base36[(36 - sum % 36) % 36]
    }
}
