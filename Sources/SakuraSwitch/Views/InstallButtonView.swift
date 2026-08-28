import SwiftUI
import Installer

/// Displays the appropriate install/progress/cancel/complete/error UI based on coordinator state.
struct InstallButtonView: View {
    let state: InstallationCoordinator.State
    let progress: TransferProgress
    let isDisabled: Bool
    let onInstall: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch state {
        case .idle:
            Button(L10n.install, action: onInstall)
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)

        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.connecting)
            }

        case .connected:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.connectedWaiting)
            }

        case .transferring:
            transferringView

        case .reconnecting(let attempt):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.reconnecting(attempt))
                    .foregroundStyle(.orange)
                cancelButton
            }

        case .complete:
            Label(L10n.done, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private var transferringView: some View {
        let stats = progress.overallStats
        return HStack(spacing: 8) {
            ProgressView(value: progress.overallFraction)
                .frame(width: 80)
            Text("\(Int(progress.overallFraction * 100))%")
                .font(.system(.caption, design: .monospaced))

            if stats.bytesPerSecond > 0 {
                Text(stats.formattedSpeed)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let eta = stats.formattedETA {
                Text(eta)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            cancelButton
        }
    }

    private var cancelButton: some View {
        Button(L10n.cancel, action: onCancel)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
    }
}
