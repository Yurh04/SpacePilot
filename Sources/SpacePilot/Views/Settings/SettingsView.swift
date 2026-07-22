import SpacePilotCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section(L10n.text(.settingsPrivacy)) {
                Text(verbatim: L10n.text(.settingsPrivacyDescription))
            }
            Section(L10n.text(.settingsDiskAccess)) {
                Text(verbatim: L10n.text(.settingsDiskAccessDescription))
                    .foregroundStyle(.secondary)
                Button(L10n.text(.settingsOpenDiskAccess)) {
                    PermissionService().openFullDiskAccessSettings()
                }
            }
            Section(L10n.text(.settingsDiagnostics)) {
                Text(verbatim: L10n.text(.settingsDiagnosticsDescription))
                    .foregroundStyle(.secondary)
                Button(L10n.text(.settingsExportDiagnostics)) { model.exportDiagnostics() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 400)
    }
}
