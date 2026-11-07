import SpacePilotCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage(AppPresentationMode.defaultsKey) private var presentationModeRawValue =
        AppPresentationMode.window.rawValue

    var body: some View {
        Form {
            Section(L10n.text(.settingsAppearance)) {
                Picker(
                    L10n.text(.settingsPresentationMode),
                    selection: presentationModeBinding
                ) {
                    Text(L10n.text(.settingsPresentationWindow))
                        .tag(AppPresentationMode.window)
                    Text(L10n.text(.settingsPresentationDynamicIsland))
                        .tag(AppPresentationMode.dynamicIsland)
                }
                .pickerStyle(.segmented)

                Text(verbatim: presentationDescription)
                    .foregroundStyle(.secondary)
            }
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
        .frame(width: 520, height: 500)
    }

    private var presentationModeBinding: Binding<AppPresentationMode> {
        Binding {
            AppPresentationMode(rawValue: presentationModeRawValue) ?? .window
        } set: { mode in
            presentationModeRawValue = mode.rawValue
            AppPresentationMode.select(mode)
        }
    }

    private var presentationDescription: String {
        switch AppPresentationMode(rawValue: presentationModeRawValue) ?? .window {
        case .window:
            L10n.text(.settingsPresentationWindowDescription)
        case .dynamicIsland:
            L10n.text(.settingsPresentationDynamicIslandDescription)
        }
    }
}
