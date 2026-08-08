import SwiftUI

/// A lightweight, non-blocking status banner shown above existing read-only AI
/// data while a new discovery pass is running or the last one failed. It never
/// hides or replaces the underlying table — it only annotates freshness.
struct AIDiscoveryBanner: View {
    let text: String
    let systemImage: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isError {
                Image(systemName: systemImage)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isError ? Color.orange : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
