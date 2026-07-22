import Foundation
import SpacePilotCore

enum PluginDiagnosticPresentation {
    static func summaries(_ diagnostics: [String], locale: Locale? = nil) -> [String] {
        var summaries: [String] = []
        for diagnostic in diagnostics {
            let copy: L10n.Copy
            if PluginDiscoveryDiagnostic(rawValue: diagnostic) != nil {
                copy = .pluginDiagnosticPathInaccessible
            } else if diagnostic.hasPrefix("Missing Plugin manifest") {
                copy = .pluginDiagnosticMissingManifest
            } else if diagnostic.hasPrefix("Invalid Plugin manifest") {
                copy = .pluginDiagnosticInvalidManifest
            } else if diagnostic.hasPrefix("Rejected or empty Plugin skill declaration") {
                copy = .pluginDiagnosticEmptySkill
            } else {
                copy = .pluginDiagnosticGeneric
            }
            let summary = L10n.text(copy, locale: locale)
            if !summaries.contains(summary) {
                summaries.append(summary)
            }
        }
        return summaries
    }
}
