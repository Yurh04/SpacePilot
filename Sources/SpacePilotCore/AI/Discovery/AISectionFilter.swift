import Foundation

/// Pure, deterministic in-memory filtering for the Developer & AI section pages.
/// Each section filters only its own records; filtering never triggers new CLI
/// probes or any I/O. An empty/whitespace query returns the input unchanged.
public enum AISectionFilter {
    public static func filterSkills(_ skills: [SkillRecord], query: String) -> [SkillRecord] {
        let needle = normalized(query)
        guard let needle else { return skills }
        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(needle)
                || skill.url.path.localizedCaseInsensitiveContains(needle)
                || skill.summary.localizedCaseInsensitiveContains(needle)
        }
    }

    public static func filterPlugins(_ plugins: [PluginRecord], query: String) -> [PluginRecord] {
        let needle = normalized(query)
        guard let needle else { return plugins }
        return plugins.filter { plugin in
            plugin.name.localizedCaseInsensitiveContains(needle)
                || plugin.source.localizedCaseInsensitiveContains(needle)
                || plugin.url.path.localizedCaseInsensitiveContains(needle)
        }
    }

    public static func filterTools(_ tools: [AIToolRecord], query: String) -> [AIToolRecord] {
        let needle = normalized(query)
        guard let needle else { return tools }
        return tools.filter { tool in
            tool.displayName.localizedCaseInsensitiveContains(needle)
                || (tool.evidence.executableURL?.path.localizedCaseInsensitiveContains(needle) ?? false)
                || (tool.evidence.detectedVersion?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    private static func normalized(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
