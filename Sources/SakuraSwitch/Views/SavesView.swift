import Foundation
import SwiftUI
import AppKit
import Installer

struct SavesView: View {

    @Bindable var appState: AppState

    // MARK: - Games

    @State private var saveGames: [InstallationCoordinator.SDCardItem] = []
    @State private var selectedGame: InstallationCoordinator.SDCardItem?

    @State private var isLoadingGames = false
    @State private var gamesError: String?

    // MARK: - Save Entries

    @State private var saveEntries: [InstallationCoordinator.SDCardItem] = []
    @State private var selectedSaveEntry: InstallationCoordinator.SDCardItem?

    @State private var isLoadingEntries = false
    @State private var entriesError: String?

    // MARK: - Save Files

    @State private var saveFiles: [InstallationCoordinator.SDCardItem] = []

    @State private var isLoadingSaveFiles = false
    @State private var saveFilesError: String?

    // MARK: - Backup

    @State private var isBackingUp = false
    @State private var backupStatus: String?
    @State private var backupError: String?

    // MARK: - Restore

    @State private var isRestoring = false
    @State private var restoreStatus: String?
    @State private var restoreError: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            header

            Divider()

            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .task {
            // Do not query DBI Saves before the USB/MTP monitor
            // has confirmed that the Switch is actually connected.
            if appState.isDeviceConnected &&
               saveGames.isEmpty &&
               !isLoadingGames {
                await loadGames()
            }
        }
        .onChange(of: appState.isDeviceConnected) { _, connected in
            guard connected else { return }

            Task {
                // DBI exposes fresh MTP object handles after every USB reconnect.
                // Reload Sakura Saves automatically instead of keeping stale state.
                await loadGames()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {

            VStack(alignment: .leading, spacing: 2) {

                Text("Сохранения")
                    .font(.title2.weight(.semibold))

                Text("Sakura Saves")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await loadGames()
                }
            } label: {
                Label(
                    "Обновить",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingGames || isBackingUp || isRestoring)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {

        if isLoadingGames {

            loadingView(
                "Загрузка сохранений..."
            )

        } else if let gamesError {

            errorView(
                title: "Не удалось загрузить сохранения",
                message: gamesError
            ) {
                Task {
                    await loadGames()
                }
            }

        } else if saveGames.isEmpty {

            emptyGamesView

        } else {

            HSplitView {

                gamesList
                    .frame(
                        minWidth: 300,
                        idealWidth: 360
                    )

                gameDetail
                    .frame(
                        minWidth: 500,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Empty Games

    private var emptyGamesView: some View {
        VStack(spacing: 10) {

            Image(systemName: "archivebox")
                .font(
                    .system(
                        size: 30,
                        weight: .light
                    )
                )
                .foregroundStyle(.secondary)

            Text("Сохранения не найдены")
                .font(.headline)

            Text(
                "Подключите Switch с запущенным DBI MTP responder."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button("Загрузить сохранения") {
                Task {
                    await loadGames()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Games List

    private var gamesList: some View {
        List(saveGames) { game in

            Button {
                selectedGame = game

                Task {
                    await loadEntries(
                        for: game
                    )
                }

            } label: {

                HStack(spacing: 10) {

                    Image(
                        systemName: "gamecontroller"
                    )
                    .foregroundStyle(.secondary)

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {

                        Text(
                            displayName(game.name)
                        )
                        .lineLimit(1)

                        if let titleID =
                            titleID(game.name) {

                            Text(titleID)
                                .font(
                                    .system(
                                        .caption2,
                                        design: .monospaced
                                    )
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBackingUp)
            .listRowBackground(
                selectedGame?.id == game.id
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Game Detail

    @ViewBuilder
    private var gameDetail: some View {

        if let game = selectedGame {

            VStack(
                alignment: .leading,
                spacing: 0
            ) {

                gameHeader(game)

                Divider()

                if isLoadingEntries {

                    loadingView(
                        "Загрузка сохранений игры..."
                    )

                } else if let entriesError {

                    errorView(
                        title:
                            "Не удалось открыть сохранения",
                        message: entriesError
                    ) {
                        Task {
                            // Reload the complete DBI Saves tree.
                            // After a fresh MTP connection DBI may expose
                            // new object handles and full game folder names.
                            await loadGames()
                        }
                    }

                } else if saveEntries.isEmpty {

                    emptyEntriesView

                } else {

                    HSplitView {

                        saveEntriesList(
                            for: game
                        )
                        .frame(
                            minWidth: 180,
                            idealWidth: 220
                        )

                        saveFilesView
                            .frame(
                                minWidth: 300,
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                }
            }

        } else {

            noGameSelectedView
        }
    }

    // MARK: - Game Header

    private func gameHeader(
        _ game: InstallationCoordinator.SDCardItem
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 4
        ) {

            Text(
                displayName(game.name)
            )
            .font(.headline)

            if let titleID =
                titleID(game.name) {

                Text(titleID)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }

    // MARK: - No Game Selected

    private var noGameSelectedView: some View {
        VStack(spacing: 10) {

            Image(systemName: "gamecontroller")
                .font(
                    .system(
                        size: 30,
                        weight: .light
                    )
                )
                .foregroundStyle(.secondary)

            Text("Выберите игру")
                .font(.headline)

            Text(
                "Здесь появятся пользователи и типы сохранений."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Empty Entries

    private var emptyEntriesView: some View {
        VStack(spacing: 10) {

            Image(systemName: "archivebox")
                .font(
                    .system(
                        size: 28,
                        weight: .light
                    )
                )
                .foregroundStyle(.secondary)

            Text("Сохранения не найдены")
                .font(.headline)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Save Entries

    private func saveEntriesList(
        for game: InstallationCoordinator.SDCardItem
    ) -> some View {

        List(saveEntries) { entry in

            Button {

                selectedSaveEntry = entry
                saveFiles = []

                saveFilesError = nil
                backupStatus = nil
                backupError = nil

                restoreStatus = nil
                restoreError = nil

                guard entry.isDirectory else {
                    return
                }

                Task {
                    await loadSaveFiles(
                        for: entry,
                        game: game
                    )
                }

            } label: {

                HStack(spacing: 10) {

                    Image(
                        systemName:
                            entry.isDirectory
                            ? "person.crop.circle"
                            : "doc"
                    )
                    .foregroundStyle(.secondary)

                    Text(entry.name)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBackingUp)
            .listRowBackground(
                selectedSaveEntry?.id == entry.id
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Save Files

    @ViewBuilder
    private var saveFilesView: some View {

        if let entry = selectedSaveEntry {

            VStack(
                alignment: .leading,
                spacing: 0
            ) {

                HStack(spacing: 8) {

                    Image(
                        systemName:
                            entry.isDirectory
                            ? "person.crop.circle"
                            : "doc"
                    )

                    Text(entry.name)
                        .font(.headline)

                    Spacer()

                    Button {
                        chooseBackupDestination()
                    } label: {
                        if isBackingUp {
                            ProgressView()
                                .controlSize(.small)

                            Text("Копирование...")
                        } else {
                            Label(
                                "Создать резервную копию",
                                systemImage:
                                    "externaldrive.badge.plus"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isBackingUp ||
                        isRestoring ||
                        isLoadingSaveFiles ||
                        saveFiles.isEmpty
                    )

                    Button {
                        chooseRestoreSource()
                    } label: {
                        if isRestoring {
                            ProgressView()
                                .controlSize(.small)

                            Text("Восстановление...")
                        } else {
                            Label(
                                "Восстановить",
                                systemImage: "arrow.uturn.backward.circle"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isBackingUp ||
                        isRestoring ||
                        isLoadingSaveFiles ||
                        saveFiles.isEmpty
                    )
                }
                .padding()

                if let backupStatus {

                    Text(backupStatus)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)

                } else if let backupError {

                    Text(backupError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)
                }

                if let restoreStatus {
                    Text(restoreStatus)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)

                } else if let restoreError {
                    Text(restoreError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)
                }

                Divider()

                if isLoadingSaveFiles {

                    loadingView(
                        "Загрузка файлов сохранения..."
                    )

                } else if let saveFilesError {

                    errorView(
                        title:
                            "Не удалось открыть сохранение",
                        message: saveFilesError
                    ) {

                        guard
                            let game = selectedGame
                        else {
                            return
                        }

                        Task {
                            await loadSaveFiles(
                                for: entry,
                                game: game
                            )
                        }
                    }

                } else if saveFiles.isEmpty {

                    VStack(spacing: 10) {

                        Image(systemName: "doc")
                            .font(
                                .system(
                                    size: 28,
                                    weight: .light
                                )
                            )
                            .foregroundStyle(
                                .secondary
                            )

                        Text("Файлы не найдены")
                            .font(.headline)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                } else {

                    List(saveFiles) { file in

                        HStack(spacing: 10) {

                            Image(
                                systemName:
                                    file.isDirectory
                                    ? "folder"
                                    : "doc"
                            )
                            .foregroundStyle(
                                .secondary
                            )

                            Text(file.name)
                                .lineLimit(1)

                            Spacer()

                            if !file.isDirectory {

                                Text(
                                    ByteCountFormatter
                                        .string(
                                            fromByteCount:
                                                Int64(
                                                    file.size
                                                ),
                                            countStyle:
                                                .file
                                        )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }

        } else {

            VStack(spacing: 10) {

                Image(
                    systemName:
                        "person.crop.circle"
                )
                .font(
                    .system(
                        size: 28,
                        weight: .light
                    )
                )
                .foregroundStyle(.secondary)

                Text("Выберите сохранение")
                    .font(.headline)

                Text(
                    "Например, Amir или BCAT."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Restore Source

    @MainActor
    private func chooseRestoreSource() {

        guard
            !isRestoring,
            !isBackingUp,
            let game = selectedGame,
            let entry = selectedSaveEntry
        else {
            return
        }

        let panel = NSOpenPanel()

        panel.title =
            "Выберите резервную копию Sakura Saves"

        panel.prompt =
            "Выбрать копию"

        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard
            panel.runModal() == .OK,
            let source = panel.url
        else {
            return
        }

        do {
            let files =
                try validatedRestoreFiles(
                    at: source
                )

            let alert = NSAlert()

            alert.alertStyle = .warning

            alert.messageText =
                "Восстановить сохранение?"

            alert.informativeText =
                """
                Игра: \(displayName(game.name))
                Сохранение: \(entry.name)
                Файлов: \(files.count)

                Перед записью Sakura Switch автоматически создаст аварийную копию текущего сохранения.
                """

            alert.addButton(
                withTitle: "Восстановить"
            )

            alert.addButton(
                withTitle: "Отмена"
            )

            guard
                alert.runModal()
                    == .alertFirstButtonReturn
            else {
                return
            }

            Task {
                await restoreBackup(
                    sourceDirectory: source,
                    game: game,
                    entry: entry
                )
            }

        } catch {

            restoreError =
                error.localizedDescription
        }
    }

    // MARK: - Restore

    @MainActor
    private func restoreBackup(
        sourceDirectory: URL,
        game: InstallationCoordinator.SDCardItem,
        entry: InstallationCoordinator.SDCardItem
    ) async {

        guard
            !isRestoring,
            !isBackingUp
        else {
            return
        }

        isRestoring = true

        restoreStatus = nil
        restoreError = nil

        backupStatus = nil
        backupError = nil

        defer {
            isRestoring = false
        }

        do {

            let restoreFiles =
                try validatedRestoreFiles(
                    at: sourceDirectory
                )

            let storage =
                try await appState
                    .coordinator
                    .findSavesStorage()

            let remoteRoot =
                "/Installed games/\(game.name)/\(entry.name)"

            let remoteItems =
                try await appState
                    .coordinator
                    .browseMTPStorage(
                        storageId: storage.id,
                        path: remoteRoot
                    )

            guard
                remoteItems.allSatisfy({
                    !$0.isDirectory
                })
            else {
                throw RestoreError.unsupportedNestedDirectories
            }

            // ------------------------------------------------
            // Emergency backup BEFORE any write
            // ------------------------------------------------

            let emergencyRoot =
                sourceDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        "Emergency-before-restore_\(backupTimestamp())",
                        isDirectory: true
                    )

            try await createEmergencyBackup(
                storageId: storage.id,
                remotePath: remoteRoot,
                destination: emergencyRoot
            )

            try verifyLocalBackup(
                directory: emergencyRoot,
                expectedRemoteItems: remoteItems
            )

            appState.coordinator.log(
                "Sakura Saves Restore: аварийная копия создана — \(emergencyRoot.path)",
                level: .info
            )

            // ------------------------------------------------
            // Replace only files present in selected backup.
            // Extra remote files are deliberately left intact.
            // ------------------------------------------------

            do {

                for localFile in restoreFiles {

                    let fileName =
                        localFile.lastPathComponent

                    if remoteItems.contains(
                        where: {
                            $0.name == fileName
                        }
                    ) {
                        try await appState
                            .coordinator
                            .deleteMTPItem(
                                storageId: storage.id,
                                parentPath: remoteRoot,
                                itemName: fileName
                            )
                    }

                    try await appState
                        .coordinator
                        .uploadMTPFile(
                            storageId: storage.id,
                            sourceURL: localFile,
                            destinationPath: remoteRoot
                        )
                }

                // --------------------------------------------
                // Read back and verify filename + byte size
                // --------------------------------------------

                let restoredItems =
                    try await appState
                        .coordinator
                        .browseMTPStorage(
                            storageId: storage.id,
                            path: remoteRoot
                        )

                try verifyRestore(
                    localFiles: restoreFiles,
                    remoteItems: restoredItems
                )

                restoreStatus =
                    "Восстановление завершено. Аварийная копия: \(emergencyRoot.path)"

                appState.coordinator.log(
                    "Sakura Saves: восстановление завершено — \(displayName(game.name)) / \(entry.name)",
                    level: .info
                )

                await loadSaveFiles(
                    for: entry,
                    game: game
                )

            } catch {

                appState.coordinator.log(
                    "Sakura Saves Restore: ошибка записи, запускается откат",
                    level: .error
                )

                do {

                    try await rollbackFromEmergencyBackup(
                        emergencyDirectory: emergencyRoot,
                        storageId: storage.id,
                        remotePath: remoteRoot
                    )

                    throw RestoreError.restoreFailedButRolledBack(
                        error.localizedDescription
                    )

                } catch let rollbackError as RestoreError {

                    throw rollbackError

                } catch {

                    throw RestoreError.rollbackFailed(
                        error.localizedDescription
                    )
                }
            }

        } catch {

            restoreError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Saves Restore: \(error.localizedDescription)",
                level: .error
            )
        }
    }

    // MARK: - Restore Validation

    private func validatedRestoreFiles(
        at directory: URL
    ) throws -> [URL] {

        let fm = FileManager.default

        var isDirectory: ObjCBool = false

        guard
            fm.fileExists(
                atPath: directory.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw RestoreError.invalidBackupFolder
        }

        let items =
            try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .fileSizeKey
                ],
                options: [
                    .skipsHiddenFiles
                ]
            )

        if items.contains(
            where: {
                ((try? $0.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory) ?? false)
            }
        ) {
            throw RestoreError.unsupportedNestedDirectories
        }

        let files =
            try items.filter { url in

                let values =
                    try url.resourceValues(
                        forKeys: [
                            .isRegularFileKey
                        ]
                    )

                return values.isRegularFile == true
            }

        guard !files.isEmpty else {
            throw RestoreError.emptyBackup
        }

        return files.sorted {
            $0.lastPathComponent
                .localizedCaseInsensitiveCompare(
                    $1.lastPathComponent
                ) == .orderedAscending
        }
    }

    // MARK: - Emergency Backup

    private func createEmergencyBackup(
        storageId: UInt32,
        remotePath: String,
        destination: URL
    ) async throws {

        let fm = FileManager.default

        let stagingRoot = URL(
            fileURLWithPath:
                "/private/tmp/sakuraswitch_download_restore_\(UUID().uuidString)",
            isDirectory: true
        )

        defer {
            try? fm.removeItem(
                at: stagingRoot
            )
        }

        try fm.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )

        try await downloadSaveDirectory(
            storageId: storageId,
            remotePath: remotePath,
            localDirectory: stagingRoot
        )

        try fm.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        let items =
            try fm.contentsOfDirectory(
                at: stagingRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

        for item in items {

            let target =
                destination
                    .appendingPathComponent(
                        item.lastPathComponent
                    )

            try fm.copyItem(
                at: item,
                to: target
            )
        }
    }

    private func verifyLocalBackup(
        directory: URL,
        expectedRemoteItems:
            [InstallationCoordinator.SDCardItem]
    ) throws {

        let files =
            try validatedRestoreFiles(
                at: directory
            )

        let fm = FileManager.default

        let localMap =
            Dictionary(
                uniqueKeysWithValues:
                    try files.map { url in

                        let attrs =
                            try fm.attributesOfItem(
                                atPath: url.path
                            )

                        let size =
                            (attrs[.size] as? NSNumber)?
                                .uint64Value ?? 0

                        return (
                            url.lastPathComponent,
                            size
                        )
                    }
            )

        for remote in expectedRemoteItems {

            guard !remote.isDirectory else {
                throw RestoreError.unsupportedNestedDirectories
            }

            guard
                let localSize =
                    localMap[remote.name],
                localSize == remote.size
            else {
                throw RestoreError.emergencyBackupVerificationFailed(
                    remote.name
                )
            }
        }
    }

    // MARK: - Restore Verification

    private func verifyRestore(
        localFiles: [URL],
        remoteItems:
            [InstallationCoordinator.SDCardItem]
    ) throws {

        let fm = FileManager.default

        let remoteMap =
            Dictionary(
                uniqueKeysWithValues:
                    remoteItems
                        .filter {
                            !$0.isDirectory
                        }
                        .map {
                            ($0.name, $0.size)
                        }
            )

        for file in localFiles {

            let attrs =
                try fm.attributesOfItem(
                    atPath: file.path
                )

            let localSize =
                (attrs[.size] as? NSNumber)?
                    .uint64Value ?? 0

            guard
                let remoteSize =
                    remoteMap[
                        file.lastPathComponent
                    ]
            else {
                throw RestoreError.verificationMissingFile(
                    file.lastPathComponent
                )
            }

            guard remoteSize == localSize else {
                throw RestoreError.verificationSizeMismatch(
                    file.lastPathComponent
                )
            }
        }
    }

    // MARK: - Automatic Rollback

    private func rollbackFromEmergencyBackup(
        emergencyDirectory: URL,
        storageId: UInt32,
        remotePath: String
    ) async throws {

        let emergencyFiles =
            try validatedRestoreFiles(
                at: emergencyDirectory
            )

        let currentItems =
            try await appState
                .coordinator
                .browseMTPStorage(
                    storageId: storageId,
                    path: remotePath
                )

        for localFile in emergencyFiles {

            let name =
                localFile.lastPathComponent

            if currentItems.contains(
                where: {
                    $0.name == name
                }
            ) {
                try await appState
                    .coordinator
                    .deleteMTPItem(
                        storageId: storageId,
                        parentPath: remotePath,
                        itemName: name
                    )
            }

            try await appState
                .coordinator
                .uploadMTPFile(
                    storageId: storageId,
                    sourceURL: localFile,
                    destinationPath: remotePath
                )
        }

        let rolledBack =
            try await appState
                .coordinator
                .browseMTPStorage(
                    storageId: storageId,
                    path: remotePath
                )

        try verifyRestore(
            localFiles: emergencyFiles,
            remoteItems: rolledBack
        )
    }

    // MARK: - Restore Errors

    private enum RestoreError:
        LocalizedError {

        case invalidBackupFolder
        case emptyBackup
        case unsupportedNestedDirectories

        case emergencyBackupVerificationFailed(
            String
        )

        case verificationMissingFile(
            String
        )

        case verificationSizeMismatch(
            String
        )

        case restoreFailedButRolledBack(
            String
        )

        case rollbackFailed(
            String
        )

        var errorDescription: String? {

            switch self {

            case .invalidBackupFolder:
                return
                    "Выбрана некорректная папка резервной копии."

            case .emptyBackup:
                return
                    "В выбранной резервной копии нет файлов."

            case .unsupportedNestedDirectories:
                return
                    "Эта версия Restore пока поддерживает только сохранения без вложенных папок. Запись отменена."

            case .emergencyBackupVerificationFailed(
                let file
            ):
                return
                    "Аварийная резервная копия не прошла проверку: \(file). Восстановление отменено до записи на Switch."

            case .verificationMissingFile(
                let file
            ):
                return
                    "После восстановления на Switch не найден файл: \(file)."

            case .verificationSizeMismatch(
                let file
            ):
                return
                    "После восстановления размер файла не совпадает: \(file)."

            case .restoreFailedButRolledBack(
                let reason
            ):
                return
                    "Восстановление не удалось, но исходный сейв автоматически возвращён. Причина: \(reason)"

            case .rollbackFailed(
                let reason
            ):
                return
                    "Ошибка восстановления и автоматического отката. Аварийная копия сохранена на Mac. Причина: \(reason)"
            }
        }
    }

    // MARK: - Backup Destination

    @MainActor
    private func chooseBackupDestination() {

        guard !isBackingUp,
              let game = selectedGame,
              let entry = selectedSaveEntry
        else {
            return
        }

        let panel = NSOpenPanel()

        panel.title =
            "Выберите папку для резервной копии"

        panel.prompt =
            "Создать резервную копию"

        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let destination = panel.url
        else {
            return
        }

        Task {
            await createBackup(
                game: game,
                entry: entry,
                destinationRoot: destination
            )
        }
    }

    // MARK: - Backup

    @MainActor
    private func createBackup(
        game: InstallationCoordinator.SDCardItem,
        entry: InstallationCoordinator.SDCardItem,
        destinationRoot: URL
    ) async {

        guard !isBackingUp else {
            return
        }

        isBackingUp = true

        backupStatus = nil
        backupError = nil

        let fm = FileManager.default

        let stagingRoot = URL(
            fileURLWithPath:
                "/private/tmp/sakuraswitch_download_backup_\(UUID().uuidString)",
            isDirectory: true
        )

        defer {
            try? fm.removeItem(
                at: stagingRoot
            )

            isBackingUp = false
        }

        do {

            try fm.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: true
            )

            let storage =
                try await appState
                    .coordinator
                    .findSavesStorage()

            let remoteRoot =
                "/Installed games/\(game.name)/\(entry.name)"

            try await downloadSaveDirectory(
                storageId: storage.id,
                remotePath: remoteRoot,
                localDirectory: stagingRoot
            )

            let backupRoot =
                destinationRoot
                    .appendingPathComponent(
                        "Sakura Switch Backups",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        safeFileName(
                            displayName(game.name)
                        ),
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        safeFileName(entry.name),
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        backupTimestamp(),
                        isDirectory: true
                    )

            try fm.createDirectory(
                at: backupRoot,
                withIntermediateDirectories: true
            )

            let stagedItems =
                try fm.contentsOfDirectory(
                    at: stagingRoot,
                    includingPropertiesForKeys: nil
                )

            for item in stagedItems {

                let target =
                    backupRoot
                        .appendingPathComponent(
                            item.lastPathComponent,
                            isDirectory: false
                        )

                try fm.copyItem(
                    at: item,
                    to: target
                )
            }

            backupStatus =
                "Резервная копия создана: \(backupRoot.path)"

            appState.coordinator.log(
                "Sakura Saves: резервная копия создана — \(backupRoot.path)",
                level: .info
            )

        } catch {

            backupError =
                "Ошибка резервного копирования: \(error.localizedDescription)"

            appState.coordinator.log(
                "Ошибка Sakura Saves Backup: \(error.localizedDescription)",
                level: .error
            )
        }
    }

    // MARK: - Recursive Backup

    private func downloadSaveDirectory(
        storageId: UInt32,
        remotePath: String,
        localDirectory: URL
    ) async throws {

        let fm = FileManager.default

        let items =
            try await appState
                .coordinator
                .browseMTPStorage(
                    storageId: storageId,
                    path: remotePath
                )

        for item in items {

            let localURL =
                localDirectory
                    .appendingPathComponent(
                        safeFileName(item.name),
                        isDirectory:
                            item.isDirectory
                    )

            if item.isDirectory {

                try fm.createDirectory(
                    at: localURL,
                    withIntermediateDirectories: true
                )

                let childRemotePath =
                    "\(remotePath)/\(item.name)"

                try await downloadSaveDirectory(
                    storageId: storageId,
                    remotePath: childRemotePath,
                    localDirectory: localURL
                )

            } else {

                try await appState
                    .coordinator
                    .downloadMTPFile(
                        storageId: storageId,
                        directoryPath: remotePath,
                        fileName: item.name,
                        destinationURL: localURL
                    )
            }
        }
    }

    // MARK: - Backup Helpers

    private func backupTimestamp() -> String {

        let formatter =
            DateFormatter()

        formatter.locale =
            Locale(identifier: "en_US_POSIX")

        formatter.dateFormat =
            "yyyy-MM-dd_HH-mm-ss"

        return formatter.string(
            from: Date()
        )
    }

    private func safeFileName(
        _ value: String
    ) -> String {

        let forbidden =
            CharacterSet(
                charactersIn:
                    "/:\\"
            )

        let parts =
            value.components(
                separatedBy: forbidden
            )

        let result =
            parts
                .filter {
                    !$0.isEmpty
                }
                .joined(
                    separator: "_"
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return result.isEmpty
            ? "Save"
            : result
    }

    // MARK: - Loading / Error

    private func loadingView(
        _ text: String
    ) -> some View {

        VStack(spacing: 10) {

            ProgressView()

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private func errorView(
        title: String,
        message: String,
        retry: @escaping () -> Void
    ) -> some View {

        VStack(spacing: 10) {

            Image(
                systemName:
                    "exclamationmark.triangle"
            )
            .font(.system(size: 26))
            .foregroundStyle(.orange)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button(
                "Повторить",
                action: retry
            )
        }
        .padding(24)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Load Games

    @MainActor
    private func loadGames() async {

        guard !isLoadingGames else {
            return
        }

        isLoadingGames = true
        gamesError = nil

        selectedGame = nil

        saveEntries = []
        selectedSaveEntry = nil

        saveFiles = []

        entriesError = nil
        saveFilesError = nil

        backupStatus = nil
        backupError = nil

        do {

            saveGames =
                try await appState
                    .coordinator
                    .loadInstalledSaveGames()

            appState.coordinator.log(
                "Sakura Saves: найдено игр с сохранениями: \(saveGames.count)",
                level: .info
            )

        } catch {

            gamesError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Saves: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingGames = false
    }

    // MARK: - Load Save Entries

    @MainActor
    private func loadEntries(
        for game:
            InstallationCoordinator.SDCardItem
    ) async {

        guard !isLoadingEntries else {
            return
        }

        isLoadingEntries = true
        entriesError = nil

        saveEntries = []

        selectedSaveEntry = nil
        saveFiles = []
        saveFilesError = nil

        backupStatus = nil
        backupError = nil

        do {

            let storage =
                try await appState
                    .coordinator
                    .findSavesStorage()

            saveEntries =
                try await appState
                    .coordinator
                    .browseMTPStorage(
                        storageId: storage.id,
                        path:
                            "/Installed games/\(game.name)"
                    )

            appState.coordinator.log(
                "Sakura Saves: \(displayName(game.name)) — найдено сохранений: \(saveEntries.count)",
                level: .info
            )

        } catch {

            entriesError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Saves: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingEntries = false
    }

    // MARK: - Load Save Files

    @MainActor
    private func loadSaveFiles(
        for entry:
            InstallationCoordinator.SDCardItem,
        game:
            InstallationCoordinator.SDCardItem
    ) async {

        guard !isLoadingSaveFiles else {
            return
        }

        isLoadingSaveFiles = true
        saveFilesError = nil
        saveFiles = []

        backupStatus = nil
        backupError = nil

        do {

            let storage =
                try await appState
                    .coordinator
                    .findSavesStorage()

            saveFiles =
                try await appState
                    .coordinator
                    .browseMTPStorage(
                        storageId: storage.id,
                        path:
                            "/Installed games/\(game.name)/\(entry.name)"
                    )

            appState.coordinator.log(
                "Sakura Saves: \(displayName(game.name)) / \(entry.name) — файлов: \(saveFiles.count)",
                level: .info
            )

        } catch {

            saveFilesError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Saves: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingSaveFiles = false
    }

    // MARK: - Game Name

    private func titleID(
        _ rawName: String
    ) -> String? {

        guard
            let open =
                rawName.lastIndex(of: "["),
            let close =
                rawName.lastIndex(of: "]"),
            open < close
        else {
            return nil
        }

        let value =
            rawName[
                rawName.index(after: open)..<close
            ]

        guard value.count == 16 else {
            return nil
        }

        return String(value)
    }

    private func displayName(
        _ rawName: String
    ) -> String {

        guard
            let titleID =
                titleID(rawName)
        else {
            return rawName
        }

        return rawName
            .replacingOccurrences(
                of: " [\(titleID)]",
                with: ""
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }
}
