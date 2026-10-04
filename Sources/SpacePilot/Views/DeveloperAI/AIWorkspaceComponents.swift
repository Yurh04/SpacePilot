import SpacePilotCore
import SwiftUI

/// Shared, native workspace chrome. Semantic backgrounds work in both appearances;
/// file images reuse the same bounded cache as Applications and Storage.
enum AIWorkspaceLayout {
    static let pagePadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let fileIconSize: CGFloat = 24
    static let rowPadding: CGFloat = 3
    /// The section list must not be renegotiated by `HSplitView` when the
    /// selected destination changes its intrinsic content width.
    static let sidebarWidth: CGFloat = 232
}

struct AIWorkspaceIcon: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

struct AIWorkspaceHeader: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var count: Int? = nil
    var contentPadding: CGFloat = AIWorkspaceLayout.pagePadding

    var body: some View {
        HStack(spacing: 10) {
            AIWorkspaceIcon(systemImage: systemImage, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let count {
                Text(count.formatted())
                    .font(.title2.weight(.medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(contentPadding)
    }
}

struct AIWorkspaceCard<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AIWorkspaceIcon(systemImage: systemImage, tint: tint, size: 20)
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

struct AIMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AIWorkspaceIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Keeps native table selection and double-click handling on the table itself.
/// This is only a cell, with no nested buttons or tap recognizers.
struct AIAssetIdentity: View {
    let name: String
    let subtitle: String
    var url: URL? = nil
    var systemImage: String = "folder.fill"
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            if let url {
                FileSystemItemIcon(url: url, size: AIWorkspaceLayout.fileIconSize)
            } else {
                AIWorkspaceIcon(systemImage: systemImage, tint: tint, size: AIWorkspaceLayout.fileIconSize)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                    .lineLimit(1).truncationMode(.tail)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AIWorkspaceLayout.rowPadding)
        .help(subtitle)
    }
}

struct AIAssetGroupRow: View {
    let group: AIAssetGroup
    let title: String
    var agents: [AIAgentEntry] = []

    private var agentIcon: AgentIconDescriptor? {
        guard case .tool(let id) = group.kind else { return nil }
        return agents.first { $0.contains(definitionID: id) }?.icon
            ?? KnownAIToolDefinitions.all.first { $0.id == id }?.agentProfile.map {
                .systemSymbol(name: $0.fallbackSymbolName)
            }
    }

    private var symbol: String {
        switch group.kind {
        case .shared: "folder.badge.person.crop"
        case .tool: "folder.fill"
        case .unknown: "folder.badge.questionmark"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let agentIcon {
                AgentIcon(descriptor: agentIcon, size: 24)
            } else {
                AIWorkspaceIcon(systemImage: symbol, size: 24)
            }
            Text(title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(group.itemCount.formatted())
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .help(title)
    }
}
