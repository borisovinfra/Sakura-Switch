import SwiftUI
import AppKit
import Installer

struct SDCardBrowserView: View {
    @Bindable var coordinator: InstallationCoordinator

    @State private var currentPath = "/"
    @State private var items: [InstallationCoordinator.SDCardItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isDropTarget = false
    @State private var isUploading = false
    @State private var uploadFileName: String?
    @State private var itemPendingDeletion: InstallationCoordinator.SDCardItem?
    @State private var isDeleting = false

    @State private var showCreateFolderDialog = false
    @State private var newFolderName = ""

    @State private var itemPendingRename: InstallationCoordinator.SDCardItem?
    @State private var renameText = ""

    private struct UploadConflict {
        let sourceURL: URL
        let existingItem: InstallationCoordinator.SDCardItem
    }

    @State private var uploadConflict: UploadConflict?

    @State private var editingFileName: String?
    @State private var editingStatus: String?
    @State private var editWatcher: Task<Void, Never>?

    private struct PendingEdit {
        let localURL: URL
        let remoteName: String
        let parentPath: String
        let modificationDate: Date?
    }

    @State private var pendingEdit: PendingEdit?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Navigation

            HStack(spacing: 8) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(currentPath == "/" || isLoading)
                .help("Назад")

                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.secondary)

                    Text(currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    showCreateFolderDialog = true
                    newFolderName = ""
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || isUploading || isDeleting)
                .help("Новая папка")

                Button {
                    Task {
                        await reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .help("Обновить")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // MARK: - Contents

            if isLoading && items.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Чтение SD-карты...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Button("Повторить") {
                        Task {
                            await reload()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                List(items) { item in
                    HStack(spacing: 10) {
                        Image(
                            systemName: item.isDirectory
                                ? "folder.fill"
                                : "doc.fill"
                        )
                        .foregroundStyle(
                            item.isDirectory
                                ? Color.accentColor
                                : Color.secondary
                        )
                        .frame(width: 20)

                        Text(item.name)
                            .lineLimit(1)

                        Spacer()

                        if !item.isDirectory {
                            Text(formatSize(item.size))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .overlay {
                        SDCardDragSourceView(
                            item: item,
                            parentPath: currentPath,
                            coordinator: coordinator,
                            onDoubleClick: {
                                if item.isDirectory {
                                    openDirectory(item.name)
                                } else {
                                    Task {
                                        await openFileForEditing(item)
                                    }
                                }
                            }
                        )
                    }
                    .contextMenu {
                        Button {
                            if item.isDirectory {
                                openDirectory(item.name)
                            } else {
                                Task {
                                    await openFileForEditing(item)
                                }
                            }
                        } label: {
                            Label(
                                item.isDirectory ? "Открыть папку" : "Открыть",
                                systemImage: item.isDirectory ? "folder" : "doc"
                            )
                        }

                        Button {
                            itemPendingRename = item
                            renameText = item.name
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            itemPendingDeletion = item
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // MARK: - Status

            HStack {
                if isLoading || isUploading || isDeleting {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(items.count) объектов")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(
                            lineWidth: 3,
                            dash: [8, 5]
                        )
                    )
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [.fileURL],
            isTargeted: $isDropTarget
        ) { providers in
            handleDrop(providers)
        }
        .alert(
            "Удалить объект?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            presenting: itemPendingDeletion
        ) { item in
            Button("Отмена", role: .cancel) {
                itemPendingDeletion = nil
            }

            Button("Удалить", role: .destructive) {
                Task {
                    await deleteItem(item)
                }
            }
        } message: { item in
            Text(
                item.isDirectory
                    ? "Удалить папку «\(item.name)» со всем содержимым?"
                    : "Удалить файл «\(item.name)»?"
            )
        }
        .alert(
            "Объект уже существует",
            isPresented: Binding(
                get: { uploadConflict != nil },
                set: { if !$0 { uploadConflict = nil } }
            ),
            presenting: uploadConflict
        ) { conflict in
            Button("Отмена", role: .cancel) {
                uploadConflict = nil
            }

            Button("Сохранить оба") {
                Task {
                    await resolveConflictKeepBoth(conflict)
                }
            }

            Button("Заменить", role: .destructive) {
                Task {
                    await resolveConflictReplace(conflict)
                }
            }
        } message: { conflict in
            Text(
                "В папке уже есть объект «\(conflict.existingItem.name)»."
            )
        }
        .alert(
            "Файл изменён",
            isPresented: Binding(
                get: { pendingEdit != nil },
                set: { if !$0 { pendingEdit = nil } }
            ),
            presenting: pendingEdit
        ) { edit in
            Button("Не сохранять", role: .destructive) {
                editingStatus = "Изменения не отправлены на Switch"
                pendingEdit = nil
            }

            Button("Сохранить") {
                Task {
                    await savePendingEdit(edit)
                }
            }

            Button("Отмена", role: .cancel) {
                pendingEdit = nil
            }
        } message: { edit in
            Text(
                "Файл «\(edit.remoteName)» был изменён на Mac. Сохранить изменения обратно на Switch?"
            )
        }
        .sheet(isPresented: $showCreateFolderDialog) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Новая папка")
                    .font(.headline)

                TextField("Имя папки", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await createFolder()
                        }
                    }

                HStack {
                    Spacer()

                    Button("Отмена") {
                        showCreateFolderDialog = false
                    }

                    Button("Создать") {
                        Task {
                            await createFolder()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        newFolderName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        .sheet(
            isPresented: Binding(
                get: { itemPendingRename != nil },
                set: { if !$0 { itemPendingRename = nil } }
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Переименовать")
                    .font(.headline)

                TextField("Новое имя", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await renamePendingItem()
                        }
                    }

                HStack {
                    Spacer()

                    Button("Отмена") {
                        itemPendingRename = nil
                    }

                    Button("Переименовать") {
                        Task {
                            await renamePendingItem()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        renameText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        .task {
            await reload()
        }
    }

    // MARK: - Navigation

    private func openDirectory(_ name: String) {
        if currentPath == "/" {
            currentPath = "/\(name)"
        } else {
            currentPath += "/\(name)"
        }

        items = []

        Task {
            await reload()
        }
    }

    private func goBack() {
        guard currentPath != "/" else { return }

        var components = currentPath
            .split(separator: "/")
            .map(String.init)

        if !components.isEmpty {
            components.removeLast()
        }

        currentPath = components.isEmpty
            ? "/"
            : "/" + components.joined(separator: "/")

        items = []

        Task {
            await reload()
        }
    }

    // MARK: - Loading

    @MainActor
    private func reload() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            items = try await coordinator.browseSDCard(path: currentPath)
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Open / Edit / Sync

    @MainActor
    private func openFileForEditing(
        _ item: InstallationCoordinator.SDCardItem
    ) async {
        guard !item.isDirectory else { return }

        editWatcher?.cancel()
        errorMessage = nil
        editingFileName = item.name
        editingStatus = "Открытие \(item.name)..."

        let parentPath = currentPath

        let editDirectory = URL(
            fileURLWithPath:
                "/private/tmp/sakuraswitch_download_edit_\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: editDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            editingFileName = nil
            editingStatus = nil
            errorMessage =
                "Не удалось создать временную папку: \(error.localizedDescription)"
            return
        }

        let localURL = editDirectory.appendingPathComponent(
            item.name,
            isDirectory: false
        )

        do {
            try await coordinator.downloadSDCardFile(
                directoryPath: parentPath,
                fileName: item.name,
                destinationURL: localURL
            )

            guard NSWorkspace.shared.open(localURL) else {
                throw NSError(
                    domain: "SakuraSwitch",
                    code: 2001,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "macOS не смогла открыть файл «\(item.name)»"
                    ]
                )
            }

            editingStatus = "Открыт \(item.name)"

            let initialDate = modificationDate(localURL)

            editWatcher = Task {
                await watchEditedFile(
                    localURL: localURL,
                    remoteName: item.name,
                    parentPath: parentPath,
                    initialDate: initialDate
                )
            }

        } catch {
            editingFileName = nil
            editingStatus = nil
            errorMessage =
                "Ошибка открытия: \(error.localizedDescription)"
        }
    }

    private func modificationDate(_ url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )

        return attrs?[.modificationDate] as? Date
    }

    @MainActor
    private func watchEditedFile(
        localURL: URL,
        remoteName: String,
        parentPath: String,
        initialDate: Date?
    ) async {
        let lastDate = initialDate

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))

            guard !Task.isCancelled else { return }

            guard FileManager.default.fileExists(
                atPath: localURL.path
            ) else {
                return
            }

            let newDate = modificationDate(localURL)

            guard newDate != nil, newDate != lastDate else {
                continue
            }

            /*
             * Даём редактору закончить атомарное сохранение файла.
             */
            try? await Task.sleep(for: .milliseconds(800))

            guard !Task.isCancelled else { return }

            pendingEdit = PendingEdit(
                localURL: localURL,
                remoteName: remoteName,
                parentPath: parentPath,
                modificationDate: newDate
            )

            editingStatus =
                "Файл \(remoteName) изменён — ожидается подтверждение"

            return
        }
    }

    @MainActor
    private func savePendingEdit(
        _ edit: PendingEdit
    ) async {
        editingStatus =
            "Синхронизация \(edit.remoteName) → Switch..."

        do {
            try await coordinator.deleteSDCardItem(
                parentPath: edit.parentPath,
                itemName: edit.remoteName
            )

            try await coordinator.uploadSDCardFile(
                edit.localURL,
                destinationPath: edit.parentPath
            )

            editingStatus =
                "Изменения \(edit.remoteName) сохранены на Switch"

            pendingEdit = nil

            if currentPath == edit.parentPath {
                await reload()
            }

        } catch {
            editingStatus = "Ошибка синхронизации"
            errorMessage =
                "Не удалось сохранить изменения на Switch: \(error.localizedDescription)"
        }
    }

    // MARK: - Create / Rename

    @MainActor
    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !name.isEmpty else { return }

        do {
            try await coordinator.createSDCardFolder(
                parentPath: currentPath,
                folderName: name
            )

            showCreateFolderDialog = false
            newFolderName = ""

            await reload()

        } catch {
            errorMessage =
                "Ошибка создания папки: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func renamePendingItem() async {
        guard let item = itemPendingRename else { return }

        let newName = renameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !newName.isEmpty else { return }

        do {
            try await coordinator.renameSDCardItem(
                parentPath: currentPath,
                oldName: item.name,
                newName: newName
            )

            itemPendingRename = nil
            renameText = ""

            await reload()

        } catch {
            errorMessage =
                "Ошибка переименования: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete

    @MainActor
    private func deleteItem(
        _ item: InstallationCoordinator.SDCardItem
    ) async {
        guard !isDeleting else { return }

        isDeleting = true
        errorMessage = nil

        defer {
            isDeleting = false
            itemPendingDeletion = nil
        }

        do {
            try await coordinator.deleteSDCardItem(
                parentPath: currentPath,
                itemName: item.name
            )

            await reload()

        } catch {
            errorMessage =
                "Ошибка удаления: \(error.localizedDescription)"
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isUploading else { return false }

        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier("public.file-url")
        }

        guard !fileProviders.isEmpty else {
            return false
        }

        Task {
            await uploadDroppedFiles(fileProviders)
        }

        return true
    }

    @MainActor
    private func uploadDroppedFiles(_ providers: [NSItemProvider]) async {
        guard !isUploading else { return }

        isUploading = true
        errorMessage = nil

        defer {
            isUploading = false
            uploadFileName = nil
        }

        do {
            for provider in providers {
                let url: URL = try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<URL, any Error>) in

                    provider.loadItem(
                        forTypeIdentifier: "public.file-url",
                        options: nil
                    ) { item, error in

                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        if let data = item as? Data,
                           let url = URL(
                               dataRepresentation: data,
                               relativeTo: nil
                           ) {
                            continuation.resume(returning: url)
                            return
                        }

                        if let url = item as? URL {
                            continuation.resume(returning: url)
                            return
                        }

                        continuation.resume(
                            throwing: NSError(
                                domain: "SakuraSwitch",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Не удалось получить путь к файлу"
                                ]
                            )
                        )
                    }
                }

                uploadFileName = url.lastPathComponent

                if let existing = items.first(where: {
                    $0.name.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame
                }) {
                    uploadConflict = UploadConflict(
                        sourceURL: url,
                        existingItem: existing
                    )
                    return
                }

                try await coordinator.uploadSDCardFile(
                    url,
                    destinationPath: currentPath
                )
            }

            await reload()

        } catch {
            errorMessage =
                "Ошибка копирования: \(error.localizedDescription)"
        }
    }

    // MARK: - Upload Conflict

    @MainActor
    private func resolveConflictReplace(
        _ conflict: UploadConflict
    ) async {
        uploadConflict = nil
        isUploading = true
        uploadFileName = conflict.sourceURL.lastPathComponent
        errorMessage = nil

        defer {
            isUploading = false
            uploadFileName = nil
        }

        do {
            try await coordinator.deleteSDCardItem(
                parentPath: currentPath,
                itemName: conflict.existingItem.name
            )

            try await coordinator.uploadSDCardFile(
                conflict.sourceURL,
                destinationPath: currentPath
            )

            await reload()

        } catch {
            errorMessage =
                "Ошибка замены: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func resolveConflictKeepBoth(
        _ conflict: UploadConflict
    ) async {
        uploadConflict = nil
        isUploading = true
        errorMessage = nil

        defer {
            isUploading = false
            uploadFileName = nil
        }

        do {
            let fm = FileManager.default

            let originalURL = conflict.sourceURL
            let ext = originalURL.pathExtension
            let base = originalURL.deletingPathExtension().lastPathComponent

            var index = 1
            var candidateName: String

            while true {
                candidateName = ext.isEmpty
                    ? "\(base) (\(index))"
                    : "\(base) (\(index)).\(ext)"

                if !items.contains(where: {
                    $0.name.caseInsensitiveCompare(candidateName) == .orderedSame
                }) {
                    break
                }

                index += 1
            }

            uploadFileName = candidateName

            let stagingDirectory = URL(
                fileURLWithPath:
                    "/private/tmp/sakuraswitch_upload_\(UUID().uuidString)",
                isDirectory: true
            )

            try fm.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )

            let tempURL = stagingDirectory.appendingPathComponent(
                candidateName,
                isDirectory: false
            )

            try fm.copyItem(
                at: originalURL,
                to: tempURL
            )

            defer {
                try? fm.removeItem(at: stagingDirectory)
            }

            try await coordinator.uploadSDCardFile(
                tempURL,
                destinationPath: currentPath
            )

            await reload()

        } catch {
            errorMessage =
                "Ошибка сохранения копии: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting

    private var statusText: String {
        if let editingStatus {
            return editingStatus
        }

        if isDeleting {
            return "Удаление..."
        }

        if isUploading {
            return uploadFileName.map {
                "Копирование \($0) → \(currentPath)"
            } ?? "Копирование файла..."
        }

        if isLoading {
            return "Чтение \(currentPath)"
        }

        return currentPath == "/"
            ? "Корень SD-карты"
            : currentPath
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }
}
