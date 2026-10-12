import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import StorageCore


// Storage Center UI localization. Key values live in Localizable.strings (ru/en/ja).
private func backupL10n(_ key: String, _ arguments: [String] = []) -> String {
    var result = NSLocalizedString(key, comment: "Sakura Storage Center")
    for (index, value) in arguments.enumerated() {
        result = result.replacingOccurrences(of: "{\(index)}", with: value)
    }
    return result
}

struct SakuraBackupView: View {
    @State private var disks: [SakuraBackupDisk] = []
    @State private var selectedSource: String?
    @State private var destination: URL?
    @State private var status = backupL10n("sakura.backup.000")
    @State private var error: String?
    @State private var loading = false
    @State private var skippedPaths: [String] = []
    @State private var exclusionsApproved = false
    @State private var confirmBackup = false
    @State private var ready = false
    @State private var running = false
    @State private var completedFiles = 0
    @State private var totalFiles = 0
    @State private var copiedBytes: UInt64 = 0
    @State private var totalCopyBytes: UInt64 = 0
    @State private var verifiedFiles = 0
    @State private var verificationTotal = 0
    @State private var backupPath: String?
    @State private var completedBackupCount = 0
    @State private var backupSucceeded = false
    @State private var resumeFolder: URL?
    @State private var resumeCheckpoint: URL?
    @State private var confirmResume = false
    @State private var autoResumeMessage: String?
    @State private var findingResume = false
    @State private var discoveringBackups = false
    @State private var discoveredBackupMessage: String?
    @State private var discoveredBackupFolders: [URL] = []



    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(backupL10n("sakura.backup.001"))
                    .font(.title2.weight(.semibold))

                Text(backupL10n("sakura.backup.002"))
                    .foregroundStyle(.secondary)

                Label(backupL10n("sakura.backup.003"), systemImage: "sdcard")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox(backupL10n("sakura.backup.004")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(backupL10n("sakura.backup.005"), selection: $selectedSource) {
                            Text(backupL10n("sakura.backup.006")).tag(nil as String?)
                            ForEach(disks) { disk in
                                Text("\(disk.name) · \(disk.id) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: disk.size), countStyle: .file))")
                                    .tag(Optional(disk.id))
                            }
                        }
                        .disabled(running || loading)

                        Button(backupL10n("sakura.backup.007")) {
                            Task { await refresh() }
                        }
                        .disabled(loading || running)
                    }
                    .padding(8)
                }

                GroupBox(backupL10n("sakura.backup.008")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(destination?.path ?? backupL10n("sakura.backup.009"))
                            .textSelection(.enabled)

                        Button(backupL10n("sakura.backup.010")) {
                            chooseDestination()
                        }
                        .disabled(running || loading)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(backupL10n("sakura.backup.011")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(status, systemImage: "info.circle")
                        if !skippedPaths.isEmpty {
                            DisclosureGroup(backupL10n("sakura.backup.012", [String(describing: skippedPaths.count)])) {
                                ForEach(skippedPaths, id: \.self) { path in
                                    Text(path).font(.caption).textSelection(.enabled)
                                }
                            }
                            Toggle(backupL10n("sakura.backup.013"),
                                   isOn: $exclusionsApproved)
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }

                        Button(backupL10n("sakura.backup.014")) {
                            Task { await validateSelection() }
                        }
                        .disabled(selectedSource == nil || destination == nil || loading || running)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(backupL10n("sakura.backup.015")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button(backupL10n("sakura.backup.016")) {
                                Task { await discoverUnfinishedBackups() }
                            }
                            .disabled(running || loading || discoveringBackups || findingResume)
                            if discoveringBackups { ProgressView().controlSize(.small) }
                        }
                        if let discoveredBackupMessage {
                            Text(discoveredBackupMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if !discoveredBackupFolders.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(discoveredBackupFolders, id: \.path) { folder in
                                    HStack(spacing: 12) {
                                        Image(systemName: resumeFolder == folder ? "checkmark.circle.fill" : "externaldrive.badge.questionmark")
                                            .foregroundStyle(resumeFolder == folder ? Color.green : Color.accentColor)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(folder.lastPathComponent)
                                                .font(.callout.weight(.medium))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text(resumeFolder == folder ? (autoResumeMessage ?? backupL10n("sakura.backup.017")) : backupL10n("sakura.backup.018"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 8)
                                        Button(resumeFolder == folder ? backupL10n("sakura.backup.019") : backupL10n("sakura.backup.020")) {
                                            inspectResumeFolder(folder)
                                        }
                                        .disabled(running || loading || findingResume || resumeFolder == folder)
                                    }
                                    .padding(10)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        Text(backupL10n("sakura.backup.021"))
                            .foregroundStyle(.secondary)
                        Button(backupL10n("sakura.backup.022")) {
                            guard let folder = chooseResumeFolder() else { return }
                            inspectResumeFolder(folder)
                        }
                        .disabled(running || loading || findingResume)
                        Text(resumeFolder?.path ?? backupL10n("sakura.backup.023"))
                            .font(.caption)
                            .textSelection(.enabled)
                        if findingResume { ProgressView().controlSize(.small) }
                        if let autoResumeMessage {
                            Text(autoResumeMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        DisclosureGroup(backupL10n("sakura.backup.024")) {
                            Button(backupL10n("sakura.backup.025")) {
                                resumeCheckpoint = chooseResumeCheckpoint()
                                if resumeCheckpoint != nil {
                                    autoResumeMessage = backupL10n("sakura.backup.026")
                                }
                            }
                            .disabled(running || loading || findingResume)
                        }
                        Text(resumeCheckpoint?.lastPathComponent ?? backupL10n("sakura.backup.027"))
                            .font(.caption)
                            .textSelection(.enabled)
                        Button(backupL10n("sakura.backup.028")) {
                            confirmResume = true
                        }
                        .disabled(!ready || selectedSource == nil || resumeFolder == nil ||
                                  resumeCheckpoint == nil || findingResume || running || loading ||
                                  (!skippedPaths.isEmpty && !exclusionsApproved))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(backupL10n("sakura.backup.029")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(backupL10n("sakura.backup.030")) {
                            confirmBackup = true
                        }
                        .disabled(!ready || running || loading ||
                                  (!skippedPaths.isEmpty && !exclusionsApproved))
                        if running {
                            ProgressView(value: Double(completedFiles),
                                         total: Double(max(totalFiles, 1)))
                            if totalCopyBytes > 0 {
                                ProgressView(value: Double(copiedBytes), total: Double(totalCopyBytes))
                                Text(backupL10n("sakura.backup.031", [String(describing: ByteCountFormatter.string(fromByteCount: Int64(clamping: copiedBytes), countStyle: .file)), String(describing: ByteCountFormatter.string(fromByteCount: Int64(clamping: totalCopyBytes), countStyle: .file))]))
                                    .font(.callout)
                            }
                            Text(backupL10n("sakura.backup.032", [String(describing: completedFiles), String(describing: totalFiles)]))
                            Text(backupL10n("sakura.backup.033", [String(describing: verifiedFiles), String(describing: verificationTotal)]))
                        }
                        if let backupPath {
                            Text(backupL10n("sakura.backup.034", [String(describing: backupPath)])).textSelection(.enabled)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // SAKURA_BACKUP_SUCCESS_CARD_V1
                if backupSucceeded, let backupPath {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(backupL10n("sakura.backup.035"), systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            Text(backupL10n("sakura.backup.036"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(backupL10n("sakura.backup.037"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(completedBackupCount.formatted())
                                        .font(.title3.weight(.semibold))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(backupL10n("sakura.backup.038"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Label(backupL10n("sakura.backup.039"), systemImage: "checkmark.shield.fill")
                                        .foregroundStyle(.green)
                                }
                            }

                            Text(backupL10n("sakura.backup.040"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(backupPath)
                                .font(.caption)
                                .textSelection(.enabled)

                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: backupPath, isDirectory: true))
                            } label: {
                                Label(backupL10n("sakura.backup.041"), systemImage: "folder")
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
        }
.confirmationDialog(
            backupL10n("sakura.backup.042"),
            isPresented: $confirmBackup
        ) {
            Button(backupL10n("sakura.backup.043")) {
                Task { await startBackup() }
            }
            Button(backupL10n("sakura.backup.044"), role: .cancel) {}
        } message: {
            Text(backupL10n("sakura.backup.045"))
        }
        .confirmationDialog(
            backupL10n("sakura.backup.046"),
            isPresented: $confirmResume
        ) {
            Button(backupL10n("sakura.backup.047")) {
                Task { await resumeExistingBackup() }
            }
            Button(backupL10n("sakura.backup.048"), role: .cancel) {}
        } message: {
            Text(backupL10n("sakura.backup.049"))
        }
        .task {
            await refresh()
            await discoverUnfinishedBackups()
        }
        .onChange(of: selectedSource) { _, _ in
            skippedPaths = []
            ready = false
            backupSucceeded = false
            exclusionsApproved = false
            status = backupL10n("sakura.backup.050")
        }
        .onChange(of: destination) { _, _ in
            skippedPaths = []
            ready = false
            backupSucceeded = false
            exclusionsApproved = false
            status = backupL10n("sakura.backup.051")
        }
    }


    @MainActor
    private func startBackup() async {
        guard ready, !running, !loading,
              let id = selectedSource, let folder = destination,
              skippedPaths.isEmpty || exclusionsApproved else { return }

        let approved = Set(skippedPaths)
        running = true
        ready = false
        error = nil
        backupPath = nil
        backupSucceeded = false
        completedBackupCount = 0
        completedFiles = 0
        verifiedFiles = 0
        totalFiles = 0
        copiedBytes = 0
        totalCopyBytes = 0
        verificationTotal = 0
        status = backupL10n("sakura.backup.052")
        defer { running = false }

        do {
            let result = try await Task.detached {
                try SakuraBackupEngine.run(
                    diskID: id,
                    destination: folder,
                    approvedSkippedPaths: approved,
                    shouldStop: { Task.isCancelled },
                    onProgress: { progress in
                        Task { @MainActor in
                            self.completedFiles = progress.verifiedFiles
                            self.totalFiles = progress.totalFiles
                            self.copiedBytes = progress.verifiedBytes
                            self.totalCopyBytes = progress.totalBytes
                        }
                    },
                    onVerification: { checked, total in
                        Task { @MainActor in
                            self.verifiedFiles = checked
                            self.verificationTotal = total
                        }
                    }
                )
            }.value
            backupPath = result.backupFolder.path
            completedBackupCount = result.fileCount
            backupSucceeded = true
            status = backupL10n("sakura.backup.053")
        } catch {
            status = backupL10n("sakura.backup.054")
            self.error = error.localizedDescription
        }
    }

    // Candidate discovery is read-only and limited to the user's Downloads directory.
    // Never silently select between multiple incomplete archives.
    private nonisolated static func unfinishedBackupsInDownloads() -> [URL] {
        let fm = FileManager.default
        let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.filter { folder in
            let name = folder.lastPathComponent
            guard name.hasPrefix("Sakura-Backup_"),
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { return false }
            return fm.fileExists(atPath: folder.appendingPathComponent("data", isDirectory: true).path)
                && !fm.fileExists(atPath: folder.appendingPathComponent("checksums.json").path)
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @MainActor
    private func discoverUnfinishedBackups() async {
        guard !running, !loading, !discoveringBackups else { return }
        discoveringBackups = true
        defer { discoveringBackups = false }
        let folders = await Task.detached(priority: .utility) {
            SakuraBackupView.unfinishedBackupsInDownloads()
        }.value
        discoveredBackupFolders = folders
        switch folders.count {
        case 0:
            discoveredBackupMessage = backupL10n("sakura.backup.055")
        case 1:
            discoveredBackupMessage = backupL10n("sakura.backup.056")
            inspectResumeFolder(folders[0])
        default:
            discoveredBackupMessage = backupL10n("sakura.backup.057", [String(describing: folders.count)])
        }
    }

    @MainActor
    private func inspectResumeFolder(_ folder: URL) {
        resumeFolder = folder
        resumeCheckpoint = nil
        autoResumeMessage = backupL10n("sakura.backup.058")
        findingResume = true
        Task {
            let result = await Task.detached(priority: .utility) {
                SakuraBackupView.findMatchingCheckpoint(for: folder)
            }.value
            // Ignore an older asynchronous result if the user has picked another folder.
            guard resumeFolder == folder else { return }
            findingResume = false
            resumeCheckpoint = result.0
            autoResumeMessage = result.1
        }
    }

    // UI discovery only: a matching checkpoint is never proof that resuming is safe.
    // SakuraBackupEngine.resumeBackup and SakuraResumePreflight retain final authority.
    private nonisolated static func findMatchingCheckpoint(for backup: URL) -> (URL?, String) {
        let fm = FileManager.default
        let root = backup.standardizedFileURL
        let data = root.appendingPathComponent("data", isDirectory: true)
        guard root.lastPathComponent.hasPrefix("Sakura-Backup_"),
              fm.fileExists(atPath: data.path),
              !fm.fileExists(atPath: root.appendingPathComponent("checksums.json").path) else {
            return (nil, backupL10n("sakura.backup.059"))
        }

        let journals = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SakuraSwitch/Backups", isDirectory: true)
        guard let sessions = try? fm.contentsOfDirectory(
            at: journals, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return (nil, backupL10n("sakura.backup.060")) }

        var matches: [(URL, Int)] = []
        for session in sessions where session.lastPathComponent.hasPrefix("SakuraBackup-") {
            guard (try? session.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fm.contentsOfDirectory(
                    at: session, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
                  ) else { continue }
            let prefix = session.lastPathComponent + "-"
            let snapshots = files.compactMap { url -> (URL, Int)? in
                let name = url.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(".json"),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let number = Int(name.dropFirst(prefix.count).dropLast(5)),
                      number > 0 else { return nil }
                return (url, number)
            }.sorted { $0.1 > $1.1 }
            guard let latest = snapshots.first,
                  let checkpoint = try? SakuraTransferJournal.load(from: latest.0),
                  checkpoint.files.count == latest.1,
                  let first = checkpoint.files.first,
                  let last = checkpoint.files.last else { continue }

            // Cheap read-only filters. Full SHA-256 and source matching happen in resume preflight.
            func matchesEntry(_ entry: SakuraTransferJournal.Entry) -> Bool {
                let file = data.appendingPathComponent(entry.relativePath)
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true, let size = values.fileSize, size >= 0 else { return false }
                return UInt64(size) == entry.bytes
            }
            if matchesEntry(first) && matchesEntry(last) { matches.append(latest) }
        }
        if matches.count == 1 {
            return (matches[0].0, backupL10n("sakura.backup.061", [String(describing: matches[0].1)]))
        }
        if matches.count > 1 {
            return (nil, backupL10n("sakura.backup.062"))
        }
        return (nil, backupL10n("sakura.backup.063"))
    }

    private func chooseResumeFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = backupL10n("sakura.backup.064")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseResumeCheckpoint() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = backupL10n("sakura.backup.065")
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private func resumeExistingBackup() async {
        guard ready, !running, !loading,
              let id = selectedSource,
              let backup = resumeFolder,
              let checkpoint = resumeCheckpoint,
              skippedPaths.isEmpty || exclusionsApproved else { return }

        // The checkpoint name includes the session ID and a six-digit file count.
        // Never invent a session or permit an arbitrary journal filename.
        let name = checkpoint.lastPathComponent
        let baseName = name.hasSuffix(".json") ? String(name.dropLast(5)) : ""
        let parts = baseName.split(separator: "-")
        guard parts.count >= 3,
              let last = parts.last,
              last.count == 6,
              last.allSatisfy({ $0.isNumber }) else {
            error = backupL10n("sakura.backup.066")
            return
        }
        let session = String(baseName.dropLast(7))
        guard session.hasPrefix("SakuraBackup-"),
              checkpoint.deletingLastPathComponent().lastPathComponent == session else {
            error = backupL10n("sakura.backup.067")
            return
        }
        let approved = Set(skippedPaths)
        running = true
        ready = false
        error = nil
        backupPath = nil
        backupSucceeded = false
        completedBackupCount = 0
        completedFiles = 0
        verifiedFiles = 0
        totalFiles = 0
        copiedBytes = 0
        totalCopyBytes = 0
        verificationTotal = 0
        status = backupL10n("sakura.backup.068")
        defer { running = false }

        do {
            let result = try await Task.detached {
                try SakuraBackupEngine.resumeBackup(
                    diskID: id,
                    backupRoot: backup,
                    journalDirectory: checkpoint.deletingLastPathComponent(),
                    session: session,
                    checkpointURL: checkpoint,
                    approvedSkippedPaths: approved,
                    shouldStop: { Task.isCancelled },
                    onProgress: { progress in
                        Task { @MainActor in
                            self.completedFiles = progress.verifiedFiles
                            self.totalFiles = progress.totalFiles
                            self.copiedBytes = progress.verifiedBytes
                            self.totalCopyBytes = progress.totalBytes
                        }
                    },
                    onVerification: { checked, total in
                        Task { @MainActor in
                            self.verifiedFiles = checked
                            self.verificationTotal = total
                        }
                    }
                )
            }.value
            backupPath = result.backupFolder.path
            completedBackupCount = result.fileCount
            backupSucceeded = true
            status = backupL10n("sakura.backup.069")
        } catch {
            status = backupL10n("sakura.backup.070")
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func refresh() async {
        loading = true
        defer { loading = false }

        do {
            let found = try await Task.detached {
                try SakuraBackupDiskScanner.scan()
            }.value

            disks = found

            if !found.contains(where: { $0.id == selectedSource }) {
                selectedSource = nil
            }
            error = nil
        } catch {
            disks = []
            selectedSource = nil
            self.error = error.localizedDescription
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = backupL10n("sakura.backup.074")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        destination = url
        error = nil
        status = backupL10n("sakura.backup.071")
    }

    @MainActor
    private func validateSelection() async {
        guard let id = selectedSource, let destination else { return }
        loading = true
        ready = false
        defer { loading = false }

        do {
            let result = try await Task.detached {
                try SakuraBackupPreflight.inspect(diskID: id, destination: destination)
            }.value

            let required = ByteCountFormatter.string(fromByteCount: Int64(clamping: result.requiredBytes), countStyle: .file)
            let free = ByteCountFormatter.string(fromByteCount: Int64(clamping: result.availableBytes), countStyle: .file)

            ready = true
            skippedPaths = result.skippedPaths
            exclusionsApproved = false
            error = nil
            status = backupL10n("sakura.backup.072", [String(describing: result.sourceName), String(describing: result.fileCount), String(describing: required), String(describing: free)])
        } catch {
            status = backupL10n("sakura.backup.073")
            self.error = error.localizedDescription
        }
    }
}
