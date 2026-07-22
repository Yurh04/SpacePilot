import SwiftUI

struct ScanStatusView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isScanning {
                ProgressView(value: model.scanProgress)
                    .frame(width: 120)
                Text(verbatim: L10n.scanStatus(for: model.scanStage))
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.bar)
    }
}
