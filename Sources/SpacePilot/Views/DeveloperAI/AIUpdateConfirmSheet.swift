import SpacePilotCore
import SwiftUI

/// User-confirmed update execution sheet. It lists the executable steps
/// (current → target, which manager) and the skipped items (with an honest
/// reason), warns that package managers may run their own install scripts, and
/// only runs anything when the user presses "Confirm Update". Cancelling has no
/// side effects. While executing it shows per-step outcomes. The sheet itself
/// never starts a process — it delegates to injected closures on the model.
struct AIUpdateConfirmSheet: View {
    let plan: UpdateExecutionPlan
    let isExecuting: Bool
    let results: [UpdateExecutionStepResult]
    let executionError: String?
    let onConfirm: () -> Void
    let onClose: () -> Void

    private var resultByKey: [AIUpdateAssetKey: UpdateExecutionStepResult] {
        Dictionary(results.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(.aiUpdateConfirmTitle))
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !plan.executable.isEmpty {
                        section(title: L10n.text(.aiUpdateConfirmExecutable)) {
                            ForEach(plan.executable) { item in
                                executableRow(item)
                            }
                        }
                    }
                    if !plan.skipped.isEmpty {
                        section(title: L10n.text(.aiUpdateConfirmSkipped)) {
                            ForEach(plan.skipped) { item in
                                skippedRow(item)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 320)

            if plan.hasExecutable {
                Text(L10n.text(.aiUpdateConfirmWarning))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let executionError {
                Text(executionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack {
                if isExecuting {
                    ProgressView().controlSize(.small)
                    Text(L10n.text(.aiUpdateConfirmRunning))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text(.aiUpdateConfirmClose), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text(.aiUpdateConfirmButton), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    // Only enabled when there is at least one executable step and
                    // nothing is currently running. Skipped-only plans keep the
                    // button disabled but the sheet remains fully informative.
                    .disabled(!plan.hasExecutable || isExecuting)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            content()
        }
    }

    private func executableRow(_ item: UpdateExecutionPlan.Item) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text("\(item.currentVersion ?? "—") → \(item.targetVersion) · \(L10n.text(.aiUpdateConfirmVia)) \(item.managerDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let result = resultByKey[item.key] {
                Text(outcomeText(result.outcome))
                    .font(.caption)
                    .foregroundStyle(outcomeColor(result.outcome))
                    .lineLimit(1)
            }
        }
    }

    private func skippedRow(_ item: UpdateExecutionPlan.SkippedItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.displayName)
                .lineLimit(1)
            Spacer()
            Text(skipReasonText(item.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func skipReasonText(_ reason: UpdateExecutionSkipReason) -> String {
        switch reason {
        case .unsupported: L10n.text(.aiUpdateSkipUnsupported)
        case .checkOnly: L10n.text(.aiUpdateSkipCheckOnly)
        case .notChecked: L10n.text(.aiUpdateSkipNotChecked)
        case .alreadyLatest: L10n.text(.aiUpdateSkipAlreadyLatest)
        case .noTargetVersion: L10n.text(.aiUpdateSkipNoTarget)
        case .invalidTargetVersion: L10n.text(.aiUpdateSkipInvalidTarget)
        }
    }

    private func outcomeText(_ outcome: UpdateExecutionOutcome) -> String {
        switch outcome {
        case .succeeded: L10n.text(.aiUpdateOutcomeSucceeded)
        case .managerUnavailable: L10n.text(.aiUpdateOutcomeManagerUnavailable)
        case .failed: L10n.text(.aiUpdateOutcomeFailed)
        case .timedOut: L10n.text(.aiUpdateOutcomeTimedOut)
        case .cancelled: L10n.text(.aiUpdateOutcomeCancelled)
        case .versionMismatch: L10n.text(.aiUpdateOutcomeVersionMismatch)
        }
    }

    private func outcomeColor(_ outcome: UpdateExecutionOutcome) -> Color {
        switch outcome {
        case .succeeded: .green
        case .cancelled: .secondary
        default: .red
        }
    }
}
