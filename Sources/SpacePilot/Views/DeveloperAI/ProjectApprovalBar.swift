import AppKit
import SpacePilotCore
import SwiftUI

struct ProjectApprovalBar: View {
    let approvedProjectRoots: [ApprovedProjectRoot]
    let approvedProjectRootIssues: [ApprovedProjectRootIssue]
    let projectScanIssues: [ProjectAIAssetScanIssue]
    let isScanningProjects: Bool
    let projectScanError: String?
    let onAddProjectRoot: (URL) -> Void
    let onRemoveProjectRoot: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(L10n.text(.aiProjectAddFolder), action: chooseFolder)
                Menu(L10n.text(.aiProjectRemoveFolder)) {
                    if approvedProjectRoots.isEmpty {
                        Text(L10n.text(.aiProjectNoApprovedFolders))
                    } else {
                        ForEach(approvedProjectRoots) { root in
                            Button(root.identity.displayName) {
                                onRemoveProjectRoot(root.id)
                            }
                        }
                    }
                }
                .disabled(approvedProjectRoots.isEmpty)
                if isScanningProjects {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text(.aiProjectScanning))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(projectSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let message = issueSummary {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var projectSummary: String {
        guard !approvedProjectRoots.isEmpty else { return L10n.text(.aiProjectNoApprovedFolders) }
        return approvedProjectRoots
            .map { $0.identity.displayName }
            .joined(separator: ", ")
    }

    private var issueSummary: String? {
        if let projectScanError { return projectScanError }
        let rootIssues = approvedProjectRootIssues.map { L10n.name(for: $0) }
        let scanIssues = projectScanIssues.map { L10n.name(for: $0) }
        let messages = rootIssues + scanIssues
        return messages.isEmpty ? nil : messages.joined(separator: " · ")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.text(.aiProjectAddFolder)
        if panel.runModal() == .OK, let url = panel.url {
            onAddProjectRoot(url)
        }
    }
}
