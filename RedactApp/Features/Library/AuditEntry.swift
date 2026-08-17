import Foundation

/// One line of the Pro redaction audit log: what kind of information was removed,
/// from which page, and when.
///
/// It deliberately carries **no sample of the removed text**. `RedactionRecord` does
/// not store one, and reconstructing "the last four digits" here would re-introduce
/// the personal information the app just destroyed — `CLAUDE.md` rule 2.
struct AuditEntry: Identifiable, Hashable, Sendable {

    let id: UUID
    /// Zero-based in the store, presented one-based.
    let pageIndex: Int
    let redactedAt: Date
    /// Resolved display name, e.g. "Aadhaar".
    let kindLabel: String
    let symbolName: String

    var pageLabel: String {
        String(localized: "Page \(pageIndex + 1)", comment: "Audit log: which page an item was removed from")
    }

    var timeLabel: String {
        redactedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var accessibilityLabel: String {
        String(
            localized: "\(kindLabel), removed from page \(pageIndex + 1) on \(timeLabel)",
            comment: "VoiceOver: one audit log entry"
        )
    }

    @MainActor
    init(_ record: RedactionRecord) {
        let kind = PIIKindNaming.kind(forIdentifier: record.kindIdentifier)
        self.id = record.id
        self.pageIndex = record.pageIndex
        self.redactedAt = record.redactedAt
        self.kindLabel = kind?.displayName ?? PIIKindNaming.humanised(record.kindIdentifier)
        self.symbolName = kind?.symbolName ?? "shield.lefthalf.filled"
    }
}

/// Resolves the persisted `RedactionRecord.kindIdentifier` string back to a ``PIIKind``.
///
/// `RedactionRecord` stores a plain `String` on purpose: the persisted store has to
/// survive `PIIKind` gaining, renaming or reordering cases, and its doc comment states
/// that "the display name is resolved at read time by the layer that owns the
/// taxonomy". This is that resolution.
///
/// It is lenient by construction. An identifier written by an older build — or a
/// user's custom rule name, which is free text — must still produce a readable line
/// rather than an empty row or a crash. Anything unrecognised is title-cased and shown
/// as-is, which is honest: the log still records that *something* was removed there.
enum PIIKindNaming {

    /// Every case without an associated value, keyed by its own case name lowercased.
    ///
    /// Built from `String(describing:)` rather than a hand-written table so a new
    /// `PIIKind` case is picked up automatically. The one thing that must be
    /// maintained by hand is ``aliases``, for identifiers that differ from the case name.
    private static let byCaseName: [String: PIIKind] = {
        let all: [PIIKind] = [
            .personName, .organisation, .place, .email, .phone,
            .pan, .aadhaar, .ifsc, .gstin, .creditCard, .dateOfBirth, .address
        ]
        return Dictionary(uniqueKeysWithValues: all.map { (String(describing: $0).lowercased(), $0) })
    }()

    /// Spellings a writer might reasonably have used for the same category.
    private static let aliases: [String: PIIKind] = [
        "emailaddress": .email,
        "phonenumber": .phone,
        "name": .personName,
        "person": .personName,
        "org": .organisation,
        "location": .place,
        "dob": .dateOfBirth,
        "card": .creditCard,
        "cardnumber": .creditCard,
        "postaladdress": .address
    ]

    static func kind(forIdentifier identifier: String) -> PIIKind? {
        let key = identifier
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return byCaseName[key] ?? aliases[key]
    }

    /// Best-effort readable form of an identifier we do not recognise:
    /// `"loyalty_card_id"` → `"Loyalty card id"`, `"customRuleName"` → `"Custom rule name"`.
    static func humanised(_ identifier: String) -> String {
        let spaced = identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .reduce(into: "") { result, character in
                if character.isUppercase, !result.isEmpty, result.last != " " {
                    result.append(" ")
                }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        guard let first = spaced.first else {
            return String(localized: "Removed item", comment: "Audit log: an entry whose category could not be named")
        }
        return first.uppercased() + spaced.dropFirst()
    }
}
