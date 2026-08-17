import SwiftUI

/// The transient bar that reports a destructive action and offers to take it back.
///
/// Chosen over a confirmation alert for the swipe-delete path. An alert on every
/// swipe puts a modal between the user and a routine action, and people learn to
/// dismiss it without reading — after which the confirmation protects nothing. A
/// snackbar keeps the action instant and keeps the escape hatch visible for as long
/// as it can honestly be offered (see ``LibraryModel`` on why the delete is staged).
///
/// VoiceOver never sees this as a passing decoration: it is a live region, and the
/// Undo button is reachable in the normal focus order rather than only by a gesture.
struct UndoSnackbar: View {

    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Token.Space.sm) {
            Image(systemName: "trash")
                .foregroundStyle(Token.Text.muted)
                .accessibilityHidden(true)

            Text(message)
                .typeStyle(Typography.callout)
                .foregroundStyle(Token.Text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)

            Button(action: undo) {
                Text("Undo")
                    .typeStyle(Typography.label)
                    .foregroundStyle(Token.Accent.violetLight)
                    .frame(minWidth: Token.Size.minimumHitTarget,
                           minHeight: Token.Size.minimumHitTarget)
            }
            .accessibilityLabel("Undo delete")
            .accessibilityHint("Keeps the document and its files")
        }
        .padding(.leading, Token.Space.md)
        .padding(.trailing, Token.Space.xs)
        .padding(.vertical, Token.Space.xs)
        .glassCard(cornerRadius: Token.Radius.control, padding: nil)
        .accessibilityElement(children: .contain)
    }
}

#Preview("UndoSnackbar") {
    VStack {
        Spacer()
        UndoSnackbar(message: "Salary slip deleted") {}
            .padding(Token.Space.md)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
