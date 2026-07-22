import SpacePilotCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Privacy") {
                Text("All analysis stays on this Mac. SpacePilot stores metadata, not conversation or log contents.")
            }
            Section("Disk access") {
                Text("Grant Full Disk Access only if you want broader coverage. SpacePilot reports inaccessible folders instead of guessing.")
                    .foregroundStyle(.secondary)
                Button("Open Full Disk Access Settings") {
                    PermissionService().openFullDiskAccessSettings()
                }
            }
            Section("Diagnostics") {
                Text("Exported diagnostics contain counts and status metadata, not file paths, conversations, or log contents.")
                    .foregroundStyle(.secondary)
                Button("Export Diagnostics…") { model.exportDiagnostics() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 400)
    }
}
