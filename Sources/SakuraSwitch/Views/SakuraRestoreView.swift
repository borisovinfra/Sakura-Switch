import Foundation
import SwiftUI
import AppKit
import StorageCore


// Storage Center UI localization. Key values live in Localizable.strings (ru/en/ja).
private func restoreL10n(_ key: String, _ arguments: [String] = []) -> String {
    var result = NSLocalizedString(key, comment: "Sakura Storage Center")
    for (index, value) in arguments.enumerated() {
        result = result.replacingOccurrences(of: "{\(index)}", with: value)
    }
    return result
}

struct SakuraRestoreView: View {
    @State private var backup: URL?
    @State private var destination: URL?
    @State private var confirmRestore = false
    @State private var restoring = false
    @State private var restoredFiles = 0
    @State private var restoreTotal = 0
    @State private var restoredBytes: UInt64 = 0
    @State private var restoreTotalBytes: UInt64 = 0
    @State private var finalChecked = 0
    @State private var finalTotal = 0
    @State private var verifying = false
    @State private var verified = false
    @State private var checkedFiles = 0
    @State private var totalFiles = 0
    @State private var checkStatus = restoreL10n("sakura.restore.047")
    @State private var checkFailed = false
    @State private var restoreFailed = false
    @State private var restoreSucceeded = false
    @State private var successfulRestoredCount = 0
    @State private var detailedError: String?


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(restoreL10n("sakura.restore.000"))
                    .font(.title2.weight(.semibold))

                Text(restoreL10n("sakura.restore.001"))
                    .foregroundStyle(.secondary)

                Label(restoreL10n("sakura.restore.002"), systemImage: "sdcard")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox(restoreL10n("sakura.restore.003")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(backup?.path ?? restoreL10n("sakura.restore.004"))
                            .textSelection(.enabled)
                        Button(restoreL10n("sakura.restore.005")) {
                            backup = chooseFolder()
                            verified = false
                            restoreSucceeded = false
                            restoreFailed = false
                            checkFailed = false
                            detailedError = nil
                            checkedFiles = 0
                            totalFiles = 0
                            checkStatus = restoreL10n("sakura.restore.006")

                        }
                        .disabled(verifying || restoring)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox(restoreL10n("sakura.restore.007")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(destination?.path ?? restoreL10n("sakura.restore.008"))
                            .textSelection(.enabled)
                        Button(restoreL10n("sakura.restore.009")) {
                            if let selected = chooseFolder() {
                                destination = selected
                                restoreSucceeded = false
                                restoreFailed = false
                            }
                        }
                        .disabled(verifying || restoring)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox(restoreL10n("sakura.restore.010")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(restoreL10n("sakura.restore.011")) {
                            Task { await verifySelectedBackup() }
                        }
                        .disabled(backup == nil || verifying || restoring)

                        if verifying {
                            ProgressView(
                                value: Double(checkedFiles),
                                total: Double(max(totalFiles, 1))
                            )
                        }

                        if verified && !verifying && !restoring && !restoreSucceeded {
                            Label(restoreL10n("sakura.restore.012", [String(describing: checkedFiles), String(describing: totalFiles)]), systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                        } else if checkFailed {
                            Label(restoreL10n("sakura.restore.013"), systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(restoreL10n("sakura.restore.014"))
                                .font(.callout)
                            DisclosureGroup(restoreL10n("sakura.restore.015")) {
                                Text(detailedError ?? checkStatus)
                                    .font(.caption).textSelection(.enabled)
                            }
                        } else if verifying {
                            Text(restoreL10n("sakura.restore.016", [String(describing: checkedFiles), String(describing: totalFiles)]))
                                .foregroundStyle(.secondary)
                        } else if !restoreSucceeded && !restoring {
                            Text(checkStatus)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox(restoreL10n("sakura.restore.017")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(restoreL10n("sakura.restore.018"), systemImage: "shield.lefthalf.filled")
                        if restoring {
                            ProgressView(
                                value: Double(restoredFiles),
                                total: Double(max(restoreTotal, 1))
                            )
                            if restoreTotalBytes > 0 {
                                ProgressView(value: Double(restoredBytes), total: Double(restoreTotalBytes))
                                Text(restoreL10n("sakura.restore.019", [String(describing: ByteCountFormatter.string(fromByteCount: Int64(clamping: restoredBytes), countStyle: .file)), String(describing: ByteCountFormatter.string(fromByteCount: Int64(clamping: restoreTotalBytes), countStyle: .file))]))
                                    .font(.callout)
                            }
                            Text(restoreL10n("sakura.restore.020", [String(describing: restoredFiles), String(describing: restoreTotal)]))
                            Text(restoreL10n("sakura.restore.021", [String(describing: finalChecked), String(describing: finalTotal)]))
                        }
                        if restoreFailed {
                            Label(restoreL10n("sakura.restore.022"), systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(restoreL10n("sakura.restore.023"))
                                .font(.callout)
                            DisclosureGroup(restoreL10n("sakura.restore.024")) {
                                Text(detailedError ?? restoreL10n("sakura.restore.025"))
                                    .font(.caption).textSelection(.enabled)
                            }
                        }
                        Button(restoreL10n("sakura.restore.026")) {
                            confirmRestore = true
                        }
                        .disabled(!verified || verifying || restoring || destination == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                if restoreSucceeded, let destination {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(restoreL10n("sakura.restore.027"), systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text(restoreL10n("sakura.restore.028"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(restoreL10n("sakura.restore.029"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("\(successfulRestoredCount) / \(successfulRestoredCount)")
                                        .font(.title3.weight(.semibold))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(restoreL10n("sakura.restore.030"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Label(restoreL10n("sakura.restore.031"), systemImage: "checkmark.shield.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(restoreL10n("sakura.restore.032"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(destination.path)
                                .font(.caption).textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.open(destination)
                            } label: {
                                Label(restoreL10n("sakura.restore.033"), systemImage: "folder")
                            }
                            Text(restoreL10n("sakura.restore.034"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog(
            restoreL10n("sakura.restore.035"),
            isPresented: $confirmRestore
        ) {
            Button(restoreL10n("sakura.restore.036")) {
                do {
                    try checkRestoreDestination()
                    Task { await startRestore() }
                } catch {
                    restoreFailed = true
                    restoreSucceeded = false
                    detailedError = error.localizedDescription
                    checkStatus = error.localizedDescription
                }
            }
            Button(restoreL10n("sakura.restore.037"), role: .cancel) {}
        } message: {
            Text(restoreL10n("sakura.restore.038"))
        }
    }

    @MainActor
    private func verifySelectedBackup() async {
        guard let backup, !verifying else { return }

        verifying = true
        verified = false
        checkFailed = false
        detailedError = nil
        checkedFiles = 0
        totalFiles = 0
        checkStatus = restoreL10n("sakura.restore.039")
        defer { verifying = false }

        do {
            let count = try await Task.detached {
                let journal = try SakuraTransferJournal.load(
                    from: backup.appendingPathComponent("checksums.json")
                )
                return try SakuraTransferJournal.verify(
                    journal,
                    at: backup.appendingPathComponent("data", isDirectory: true),
                    onProgress: { checked, total in
                        Task { @MainActor in
                            self.checkedFiles = checked
                            self.totalFiles = total
                        }
                    }
                )
            }.value

            verified = true
            checkedFiles = count
            totalFiles = count
            checkStatus = restoreL10n("sakura.restore.040", [String(describing: count)])
        } catch {
            checkFailed = true
            detailedError = error.localizedDescription
            checkStatus = restoreL10n("sakura.restore.041") + error.localizedDescription
        }
    }

    @MainActor
    private func checkRestoreDestination() throws {
        guard let destination else {
            throw RestoreError.invalidDestination
        }

        guard try SakuraRestoreEngine.destinationIsEffectivelyEmpty(destination) else {
            throw RestoreError.destinationNotEmpty
        }
    }

    private enum RestoreError: LocalizedError {
        case invalidDestination
        case destinationNotEmpty

        var errorDescription: String? {
            switch self {
            case .invalidDestination:
                return restoreL10n("sakura.restore.042")
            case .destinationNotEmpty:
                return restoreL10n("sakura.restore.043")
            }
        }
    }

    @MainActor
    private func startRestore() async {
        guard verified, !restoring, !verifying,
              let backup, let destination else { return }

        restoring = true
        restoreSucceeded = false
        restoreFailed = false
        checkFailed = false
        detailedError = nil
        verified = false
        restoredFiles = 0
        restoreTotal = 0
        restoredBytes = 0
        restoreTotalBytes = 0
        finalChecked = 0
        finalTotal = 0
        checkStatus = restoreL10n("sakura.restore.044")
        defer { restoring = false }

        do {
            let journalParent = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("SakuraSwitch/RestoreJournals")

            try FileManager.default.createDirectory(
                at: journalParent,
                withIntermediateDirectories: true
            )

            let journal = journalParent.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: journal,
                withIntermediateDirectories: false
            )

            let count = try await Task.detached {
                try SakuraRestoreEngine.restore(
                    backup: backup,
                    destination: destination,
                    journalDirectory: journal,
                    shouldStop: { Task.isCancelled },
                    onProgress: { progress in
                        Task { @MainActor in
                            self.restoredFiles = progress.verifiedFiles
                            self.restoreTotal = progress.totalFiles
                            self.restoredBytes = progress.verifiedBytes
                            self.restoreTotalBytes = progress.totalBytes
                        }
                    },
                    onVerification: { checked, total in
                        Task { @MainActor in
                            self.finalChecked = checked
                            self.finalTotal = total
                        }
                    }
                )
            }.value

            successfulRestoredCount = count
            restoredFiles = count
            restoreTotal = count
            finalChecked = count
            finalTotal = count
            restoreSucceeded = true
            checkStatus = restoreL10n("sakura.restore.045", [String(describing: count)])
        } catch {
            restoreFailed = true
            detailedError = error.localizedDescription
            checkStatus = restoreL10n("sakura.restore.046") + error.localizedDescription
        }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
