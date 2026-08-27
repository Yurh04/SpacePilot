import SpacePilotCore
import SwiftUI

/// Shared action bar for the Skills / Plugins / CLI pages. It exposes
/// "Check Selected for Updates" and "Update Selected…". Both buttons are enabled
/// whenever the user has any visible row selected (never disabled just because
/// the selection is entirely unsupported): checking runs a network check only
/// for supported keys and surfaces unsupported reasons for the rest, while the
/// update action opens a user-confirmed execution sheet. The bar never starts a
/// process, writes files, or contacts the network itself; both are delegated to
/// injected closures which reuse the safe provider/executor path.
struct AIUpdateActionBar: View {
    let plan: AIUpdateSelectionPlan
    let isChecking: Bool
    let onCheckSelected: () -> Void
    let onUpdateSelected: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCheckSelected) {
                Label(L10n.text(.aiUpdateCheckSelected), systemImage: "arrow.triangle.2.circlepath")
            }
            // Enabled for ANY visible selection. When nothing is checkable the
            // action still runs zero network requests but surfaces per-item
            // "unsupported" reasons rather than leaving the button dead.
            .disabled(!plan.hasSelection || isChecking)

            Button(action: onUpdateSelected) {
                Label(L10n.text(.aiUpdateSelected), systemImage: "square.and.arrow.down")
            }
            // Enabled for any selection: opens a confirmation sheet that lists
            // executable vs skipped items. Non-executable items are shown with a
            // reason inside the sheet; the button itself is never a dead control.
            .disabled(!plan.hasSelection || isChecking)

            if isChecking {
                Button(L10n.text(.aiUpdateCancel), action: onCancel)
                ProgressView().controlSize(.small)
            }

            Spacer()

            if !plan.selected.isEmpty {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var summaryText: String {
        var parts: [String] = []
        if !plan.supported.isEmpty {
            parts.append("\(L10n.text(.aiUpdatePlanSupported)): \(plan.supported.count)")
        }
        if !plan.unsupported.isEmpty {
            parts.append("\(L10n.text(.aiUpdatePlanUnsupported)): \(plan.unsupported.count)")
        }
        return parts.joined(separator: " · ")
    }
}
