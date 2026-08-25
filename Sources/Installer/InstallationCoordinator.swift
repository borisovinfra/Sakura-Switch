import Foundation
import DBIProtocol
import USBTransport
import MTPTransport
import NativeMTPTransport
import NetworkTransport

/// Mediator: orchestrates USB connection, DBI protocol, and file serving.
/// MainActor-isolated to safely drive @Observable state for SwiftUI.
@Observable
@MainActor
public final class InstallationCoordinator {
    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case transferring
        case reconnecting(attempt: Int)
        case complete
        case error(String)
    }

    public enum TransportMode: String, Sendable, CaseIterable {
        case dbiBackend = "DBI Backend"
        case mtp = "MTP"
        case sdCard = "SD-карта"
        case network = "Network"
    }

    public private(set) var state: State = .idle
    public var transportMode: TransportMode = .mtp
    public var mtpInstallDestination: MTPInstallDestination?
    public let progress = TransferProgress()
    public private(set) var logs: [LogEntry] = []

    private let transport: any TransportProtocol
    private let mtpDevice: any MTPDeviceProtocol
    private let mtpSession: any MTPSessionProtocol
    private let fileServer = FileServer()
    private let session: DBISession
    private let sessionDelegateAdapter: SessionDelegateAdapter
    private let reconnectPolicy: ReconnectPolicy
    private let ftpClient: any FTPUploadClientProtocol
    private var installTask: Task<Void, Never>?
    private var queuedURLs: [URL] = []
    public var ftpAddress: String = ""
    public private(set) var networkInfo: String?

    public init(
        transport: (any TransportProtocol)? = nil,
        mtpDevice: (any MTPDeviceProtocol)? = nil,
        mtpSession: (any MTPSessionProtocol)? = nil,
        ftpClient: (any FTPUploadClientProtocol)? = nil,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.transport = transport ?? USBTransport().withRetry()
        self.mtpDevice = mtpDevice ?? MTPDevice()
        self.mtpSession = mtpSession ?? PrivilegedMTPSession()
        self.ftpClient = ftpClient ?? FTPUploadClient()
        self.reconnectPolicy = reconnectPolicy
        let adapter = SessionDelegateAdapter()
        self.sessionDelegateAdapter = adapter
        self.session = DBISession()
        self.session.delegate = adapter
    }

    public func queueFiles(_ urls: [URL]) {
        queuedURLs.append(contentsOf: urls)
        fileServer.register(files: urls)
        for url in urls {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            progress.register(name: url.lastPathComponent, totalBytes: size)
        }
        log("Queued \(urls.count) file(s)")
    }

    public func startInstallation() {
        guard case .idle = state else { return }
        guard fileServer.fileCount > 0 else {
            log("No files queued")
            return
        }

        sessionDelegateAdapter.onLog = { [weak self] message, level in
            Task { @MainActor in self?.log(message, level: level) }
        }
        sessionDelegateAdapter.onFileChunk = { [weak self] fileName, bytesInChunk, _ in
            Task { @MainActor in
                self?.progress.applyChunk(fileName: fileName, bytesInChunk: bytesInChunk)
            }
        }

        installTask = Task { [weak self] in
            await self?.runInstallation()
        }
    }

    public func cancel() {
        installTask?.cancel()
        installTask = nil
        // FTP client uses curl Process which is killed when task is cancelled
        networkInfo = nil
        log("Cancellation requested")
    }

    public func reset() {
        cancel()
        // FTP client uses curl Process which is killed when task is cancelled
        state = .idle
        progress.clear()
        logs.removeAll()
        queuedURLs.removeAll()
        networkInfo = nil
    }

    // MARK: - SD Card Browser

    public struct SDCardItem: Identifiable, Sendable, Equatable {
        public let id: UInt32
        public let name: String
        public let size: UInt64
        public let isDirectory: Bool

        public init(
            id: UInt32,
            name: String,
            size: UInt64,
            isDirectory: Bool
        ) {
            self.id = id
            self.name = name
            self.size = size
            self.isDirectory = isDirectory
        }
    }

    /// Uploads one regular file into an existing SD-card directory.
    ///
    /// Compatibility wrapper for the existing SD-card browser.
    public func uploadSDCardFile(
        _ sourceURL: URL,
        destinationPath: String
    ) async throws {
        try await uploadMTPFile(
            storageId: 65537,
            sourceURL: sourceURL,
            destinationPath: destinationPath
        )
    }

    /// Uploads one regular file into an existing directory
    /// of any DBI MTP storage.
    public func uploadMTPFile(
        storageId: UInt32,
        sourceURL: URL,
        destinationPath: String
    ) async throws {

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in

            DispatchQueue.global(qos: .userInitiated).async {

                let fm = FileManager.default

                guard sourceURL.isFileURL else {
                    continuation.resume(
                        throwing: MTPError.transferFailed(
                            "Источник не является локальным файлом"
                        )
                    )
                    return
                }

                var isDirectory: ObjCBool = false

                guard fm.fileExists(
                    atPath: sourceURL.path,
                    isDirectory: &isDirectory
                ),
                !isDirectory.boolValue else {

                    continuation.resume(
                        throwing: MTPError.transferFailed(
                            "Источник должен быть обычным файлом"
                        )
                    )
                    return
                }

                let safeName = sourceURL.lastPathComponent
                    .replacingOccurrences(
                        of: "/",
                        with: "_"
                    )

                let stagingDirectory = URL(
                    fileURLWithPath:
                        "/private/tmp/sakuraswitch_upload_\(UUID().uuidString)",
                    isDirectory: true
                )

                let stagedURL =
                    stagingDirectory.appendingPathComponent(
                        safeName,
                        isDirectory: false
                    )

                do {

                    try fm.createDirectory(
                        at: stagingDirectory,
                        withIntermediateDirectories: true
                    )

                    try fm.copyItem(
                        at: sourceURL,
                        to: stagedURL
                    )

                    defer {
                        try? fm.removeItem(
                            at: stagingDirectory
                        )
                    }

                    let process = Process()

                    process.executableURL =
                        URL(fileURLWithPath: "/usr/bin/sudo")

                    process.arguments = [
                        "-n",
                        "/usr/local/libexec/sakuraswitch-mtp-helper",
                        "--upload-path",
                        String(storageId),
                        destinationPath,
                        stagedURL.path
                    ]

                    let pipe = Pipe()

                    process.standardOutput = pipe
                    process.standardError = pipe

                    try process.run()
                    process.waitUntilExit()

                    let data =
                        pipe.fileHandleForReading.readDataToEndOfFile()

                    let output =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? ""

                    guard
                        process.terminationStatus == 0,
                        output.components(
                            separatedBy: .newlines
                        ).contains("OK")
                    else {
                        throw MTPError.transferFailed(
                            output.isEmpty
                                ? "Не удалось передать файл на Switch"
                                : output
                        )
                    }

                    continuation.resume()

                } catch {
                    continuation.resume(
                        throwing: error
                    )
                }
            }
        }
    }

    /// Downloads one file from the Switch SD card.
    ///
    /// Compatibility wrapper for the existing SD-card browser.
    public func downloadSDCardFile(
        directoryPath: String,
        fileName: String,
        destinationURL: URL
    ) async throws {
        try await downloadMTPFile(
            storageId: 65537,
            directoryPath: directoryPath,
            fileName: fileName,
            destinationURL: destinationURL
        )
    }

    /// Downloads one file from any DBI MTP storage.
    public func downloadMTPFile(
        storageId: UInt32,
        directoryPath: String,
        fileName: String,
        destinationURL: URL
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in

            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()

                process.executableURL =
                    URL(fileURLWithPath: "/usr/bin/sudo")

                process.arguments = [
                    "-n",
                    "/usr/local/libexec/sakuraswitch-mtp-helper",
                    "--download-path",
                    String(storageId),
                    directoryPath,
                    fileName,
                    destinationURL.path
                ]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data =
                        pipe.fileHandleForReading.readDataToEndOfFile()

                    let output =
                        String(data: data, encoding: .utf8) ?? ""

                    guard process.terminationStatus == 0,
                          output.components(separatedBy: .newlines)
                              .contains("OK") else {

                        throw MTPError.transferFailed(
                            output.isEmpty
                                ? "Не удалось скачать файл со Switch"
                                : output
                        )
                    }

                    continuation.resume()

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Materializes a Switch file or an entire directory tree locally.
    /// Used when dragging objects from Sakura Switch into Finder.
    public func materializeSDCardItem(
        _ item: SDCardItem,
        parentPath: String
    ) async throws -> URL {

        let fm = FileManager.default

        let root = URL(
            fileURLWithPath:
                "/private/tmp/sakuraswitch_download_\(UUID().uuidString)",
            isDirectory: true
        )

        try fm.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let destination = root.appendingPathComponent(
            item.name,
            isDirectory: item.isDirectory
        )

        if item.isDirectory {
            try fm.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )

            let remotePath: String

            if parentPath == "/" {
                remotePath = "/\(item.name)"
            } else {
                remotePath = "\(parentPath)/\(item.name)"
            }

            try await materializeSDCardDirectory(
                remotePath: remotePath,
                localURL: destination
            )

        } else {
            /*
             * Helper deliberately accepts only paths beginning with
             * /private/tmp/sakuraswitch_download_
             */
            try await downloadSDCardFile(
                directoryPath: parentPath,
                fileName: item.name,
                destinationURL: destination
            )
        }

        return destination
    }

    private func materializeSDCardDirectory(
        remotePath: String,
        localURL: URL
    ) async throws {
        let fm = FileManager.default

        let children = try await browseSDCard(path: remotePath)

        for child in children {
            let localChild = localURL.appendingPathComponent(
                child.name,
                isDirectory: child.isDirectory
            )

            if child.isDirectory {
                try fm.createDirectory(
                    at: localChild,
                    withIntermediateDirectories: true
                )

                let childRemote =
                    remotePath == "/"
                    ? "/\(child.name)"
                    : "\(remotePath)/\(child.name)"

                try await materializeSDCardDirectory(
                    remotePath: childRemote,
                    localURL: localChild
                )

            } else {
                try await downloadSDCardFile(
                    directoryPath: remotePath,
                    fileName: child.name,
                    destinationURL: localChild
                )
            }
        }
    }

    /// Deletes one file or directory from the Switch SD card.
    ///
    /// Compatibility wrapper for the existing SD-card browser.
    public func deleteSDCardItem(
        parentPath: String,
        itemName: String
    ) async throws {
        try await deleteMTPItem(
            storageId: 65537,
            parentPath: parentPath,
            itemName: itemName
        )
    }

    /// Deletes one object from any DBI MTP storage.
    public func deleteMTPItem(
        storageId: UInt32,
        parentPath: String,
        itemName: String
    ) async throws {

        try await runSDCardHelper(
            arguments: [
                "--delete-path",
                String(storageId),
                parentPath,
                itemName
            ],
            fallbackError:
                "Не удалось удалить объект с Switch"
        )
    }


    // MARK: - Recursive SD Upload

    /// Recursively uploads the CONTENTS of a local directory into
    /// an existing directory on the Switch SD card.
    ///
    /// Safety:
    /// - existing directories are reused;
    /// - existing files are NEVER overwritten;
    /// - a conflict aborts the operation.
    public func uploadSDCardDirectoryContents(
        _ sourceDirectory: URL,
        destinationPath: String
    ) async throws {

        NSLog("🌸 SD DIRECTORY UPLOAD START \(sourceDirectory.path) -> \(destinationPath)")

        let fm = FileManager.default

        var isDirectory: ObjCBool = false

        guard
            sourceDirectory.isFileURL,
            fm.fileExists(
                atPath: sourceDirectory.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw MTPError.transferFailed(
                "Источник должен быть локальной папкой"
            )
        }

        try await uploadLocalDirectoryTree(
            sourceDirectory,
            remotePath: destinationPath
        )
    }


    private func uploadLocalDirectoryTree(
        _ localDirectory: URL,
        remotePath: String
    ) async throws {

        let fm = FileManager.default

        let localItems =
            try fm.contentsOfDirectory(
                at: localDirectory,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [
                    .skipsHiddenFiles
                ]
            )

        NSLog("🌸 SD LOCAL ITEMS READY \(localItems.count)")

        let remoteItems =
            (try? await browseSDCard(
                path: remotePath
            )) ?? []

        NSLog("🌸 SD REMOTE ITEMS READY \(remoteItems.count)")

        for localItem in localItems {

            let values =
                try localItem.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey
                    ]
                )

            if values.isSymbolicLink == true {
                continue
            }

            let name =
                localItem.lastPathComponent

            /*
             Ignore macOS metadata even if it escaped
             .skipsHiddenFiles.
             */
            if name == ".DS_Store" ||
               name.hasPrefix("._") {
                continue
            }

            let existing =
                remoteItems.first {
                    $0.name.caseInsensitiveCompare(
                        name
                    ) == .orderedSame
                }

            if values.isDirectory == true {

                if let existing {

                    guard existing.isDirectory else {
                        throw MTPError.transferFailed(
                            "Конфликт: \(remotePath)/\(name) уже существует как файл"
                        )
                    }

                } else {

                    NSLog("🌸 SD CREATE FOLDER START \(name)")

                    try await createSDCardFolder(
                        parentPath: remotePath,
                        folderName: name
                    )

                    NSLog("🌸 SD CREATE FOLDER DONE \(name)")
                }

                let childRemotePath =
                    remotePath == "/"
                    ? "/\(name)"
                    : "\(remotePath)/\(name)"

                try await uploadLocalDirectoryTree(
                    localItem,
                    remotePath: childRemotePath
                )

                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            if existing != nil {
                throw MTPError.transferFailed(
                    "Конфликт: файл \(remotePath)/\(name) уже существует"
                )
            }

            try await uploadSDCardFile(
                localItem,
                destinationPath: remotePath
            )
        }
    }


    public func createSDCardFolder(
        parentPath: String,
        folderName: String
    ) async throws {
        try await runSDCardHelper(
            arguments: [
                "--mkdir-path",
                "65537",
                parentPath,
                folderName
            ],
            fallbackError: "Не удалось создать папку"
        )
    }

    public func renameSDCardItem(
        parentPath: String,
        oldName: String,
        newName: String
    ) async throws {
        try await runSDCardHelper(
            arguments: [
                "--rename-path",
                "65537",
                parentPath,
                oldName,
                newName
            ],
            fallbackError: "Не удалось переименовать объект"
        )
    }

    private func runSDCardHelper(
        arguments: [String],
        fallbackError: String
    ) async throws {

        NSLog("🌸 HELPER CALL \(arguments)")

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in

            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()

                process.executableURL =
                    URL(fileURLWithPath: "/usr/bin/sudo")

                process.arguments = [
                    "-n",
                    "/usr/local/libexec/sakuraswitch-mtp-helper"
                ] + arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data =
                        pipe.fileHandleForReading.readDataToEndOfFile()

                    let output =
                        String(data: data, encoding: .utf8) ?? ""

                    guard process.terminationStatus == 0,
                          output.components(separatedBy: .newlines)
                                .contains("OK") else {
                        throw MTPError.transferFailed(
                            output.isEmpty
                                ? fallbackError
                                : output
                        )
                    }

                    continuation.resume()

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Reads one directory from the Switch SD card.
    ///
    /// Compatibility wrapper for the existing SD-card browser.
    public func browseSDCard(
        path: String
    ) async throws -> [SDCardItem] {
        try await browseMTPStorage(
            storageId: 65537,
            path: path
        )
    }

    /// Reads one directory from any DBI MTP storage.
    public func browseMTPStorage(
        storageId: UInt32,
        path: String
    ) async throws -> [SDCardItem] {

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {

                let process = Process()

                process.executableURL =
                    URL(fileURLWithPath: "/usr/bin/sudo")

                process.arguments = [
                    "-n",
                    "/usr/local/libexec/sakuraswitch-mtp-helper",
                    "--browse-path",
                    String(storageId),
                    path
                ]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data =
                        pipe.fileHandleForReading.readDataToEndOfFile()

                    let output =
                        String(data: data, encoding: .utf8) ?? ""

                    guard process.terminationStatus == 0,
                          output.components(separatedBy: .newlines)
                              .contains("OK") else {

                        throw MTPError.connectionFailed(
                            output.isEmpty
                                ? "Не удалось прочитать MTP-хранилище"
                                : output
                        )
                    }

                    var items: [SDCardItem] = []

                    for line in output.components(
                        separatedBy: .newlines
                    ) {
                        guard line.hasPrefix("ITEM:") else {
                            continue
                        }

                        let parts = line.split(
                            separator: ":",
                            maxSplits: 4,
                            omittingEmptySubsequences: false
                        )

                        guard parts.count == 5,
                              let handle = UInt32(parts[1]),
                              let size = UInt64(parts[3]) else {
                            continue
                        }

                        let formatText = String(parts[2])
                        let name = String(parts[4])

                        items.append(
                            SDCardItem(
                                id: handle,
                                name: name,
                                size: size,
                                isDirectory: formatText == "0x3001"
                            )
                        )
                    }

                    // Служебный мусор macOS не показываем.
                    items = items.filter {
                        !$0.name.hasPrefix("._") &&
                        $0.name != ".DS_Store" &&
                        $0.name != ".Spotlight-V100" &&
                        $0.name != ".Trashes" &&
                        $0.name != ".fseventsd"
                    }

                    // Папки сверху, затем файлы.
                    items.sort {
                        if $0.isDirectory != $1.isDirectory {
                            return $0.isDirectory && !$1.isDirectory
                        }

                        return $0.name.localizedCaseInsensitiveCompare(
                            $1.name
                        ) == .orderedAscending
                    }

                    continuation.resume(returning: items)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Opens the Nintendo Switch DBI MTP device for browsing.
    /// Returns all MTP storage areas exposed by DBI.
    public func connectMTPBrowser() async throws -> [MTPStorage] {
        // Make sure an old libmtp session is not still open.
        await mtpDevice.close()

        // Release macOS USB ownership through our privileged helper.
        try await PrivilegedUSBClaim.claimDevice(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID
        )

        let devices = try await mtpDevice.detectDevices()

        guard let switchDevice = devices.first(where: {
            $0.vendorId == NintendoSwitchUSB.vendorID &&
            $0.productId == NintendoSwitchUSB.mtpProductID
        }) else {
            throw MTPError.deviceNotFound
        }

        try await mtpDevice.open(device: switchDevice)

        return try await mtpDevice.getStorages()
    }

    /// Returns the complete flattened folder tree for one DBI storage.
    public func loadMTPFolders(storageId: UInt32) async throws -> [MTPFolder] {
        try await mtpDevice.getFolders(storageId: storageId)
    }

    /// Reads DBI MTP storages through the privileged helper.
    ///
    /// Unlike connectMTPBrowser(), this does not keep a libmtp session
    /// around and is safe to use before raw-MTP browsing.
    public func loadMTPStoragesViaHelper() async throws -> [MTPStorage] {

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[MTPStorage], any Error>) in

            DispatchQueue.global(qos: .userInitiated).async {

                let process = Process()

                process.executableURL =
                    URL(fileURLWithPath: "/usr/bin/sudo")

                process.arguments = [
                    "-n",
                    "/usr/local/libexec/sakuraswitch-mtp-helper",
                    "--storages"
                ]

                let pipe = Pipe()

                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data =
                        pipe.fileHandleForReading.readDataToEndOfFile()

                    let output =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? ""

                    guard
                        process.terminationStatus == 0,
                        output.components(
                            separatedBy: .newlines
                        ).contains("OK")
                    else {
                        throw MTPError.connectionFailed(
                            output.isEmpty
                                ? "Не удалось получить список MTP-хранилищ"
                                : output
                        )
                    }

                    var storages: [MTPStorage] = []

                    for line in output.components(
                        separatedBy: .newlines
                    ) {

                        guard line.hasPrefix("STORAGE:") else {
                            continue
                        }

                        let parts = line.split(
                            separator: ":",
                            maxSplits: 4,
                            omittingEmptySubsequences: false
                        )

                        guard
                            parts.count == 5,
                            let id = UInt32(parts[1]),
                            let free = UInt64(parts[2]),
                            let capacity = UInt64(parts[3])
                        else {
                            continue
                        }

                        let description =
                            String(parts[4])
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )

                        storages.append(
                            MTPStorage(
                                id: id,
                                description: description,
                                freeSpaceInBytes: free,
                                maxCapacity: capacity
                            )
                        )
                    }

                    continuation.resume(
                        returning: storages
                    )

                } catch {
                    continuation.resume(
                        throwing: error
                    )
                }
            }
        }
    }

    /// Finds one DBI storage through the helper without opening
    /// a second long-lived libmtp session.
    public func findMTPStorageViaHelper(
        named name: String
    ) async throws -> MTPStorage? {

        let storages =
            try await loadMTPStoragesViaHelper()

        let needle =
            name
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        return storages.first { storage in

            let description =
                storage.description
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .lowercased()

            return
                description == needle ||
                description.hasSuffix(
                    ": \(needle)"
                )
        }
    }

    /// Finds one DBI MTP storage by its human-readable description.
    /// Matches both "Saves" and prefixed names such as "7: Saves".
    public func findMTPStorage(
        named name: String
    ) async throws -> MTPStorage? {

        let storages: [MTPStorage]

        do {
            storages = try await connectMTPBrowser()
            await disconnectMTPBrowser()
        } catch {
            await disconnectMTPBrowser()
            throw error
        }

        let needle = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return storages.first { storage in
            let description = storage.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            return description == needle ||
                   description.hasSuffix(": \(needle)")
        }
    }

    // MARK: - Sakura Saves

    /// Finds DBI's Saves storage.
    public func findSavesStorage() async throws -> MTPStorage {
        guard let storage = try await findMTPStorageViaHelper(named: "Saves") else {
            throw MTPError.connectionFailed(
                "Хранилище Saves не найдено. Убедитесь, что на Switch запущен DBI MTP responder."
            )
        }

        return storage
    }

    /// Returns installed games exposed by DBI in the Saves storage.
    public func loadInstalledSaveGames() async throws -> [SDCardItem] {
        let storage = try await findSavesStorage()

        return try await browseMTPStorage(
            storageId: storage.id,
            path: "/Installed games"
        )
    }

    public func disconnectMTPBrowser() async {
        await mtpDevice.close()
    }

    // MARK: - Private

    private func runInstallation() async {
        switch transportMode {
        case .dbiBackend:
            await runDBIBackendInstallation()
        case .mtp:
            await runMTPInstallation()
        case .sdCard:
            break
        case .network:
            await runNetworkInstallation()
        }
        installTask = nil
    }

    // MARK: - DBI Backend Path

    private func runDBIBackendInstallation() async {
        state = .connecting
        log("Connecting to Switch (DBI Backend)...", level: .info)

        do {
            try await transport.connect()
            state = .connected
            log("Connected to Switch", level: .info)

            try await runSessionWithReconnect()

            state = .complete
            log("Installation complete!", level: .info)
        } catch is CancellationError {
            state = .idle
            log("Installation cancelled", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("Error: \(error.localizedDescription)", level: .error)
        }

        try? await transport.disconnect()
    }

    private func runSessionWithReconnect() async throws {
        var reconnectAttempts = 0

        while true {
            do {
                state = .transferring
                try await session.run(transport: transport, fileServer: fileServer)
                return
            } catch let error as USBError where error == .disconnected {
                guard reconnectAttempts < reconnectPolicy.maxAttempts else {
                    throw error
                }

                reconnectAttempts += 1
                state = .reconnecting(attempt: reconnectAttempts)
                log("Connection lost. Reconnecting (\(reconnectAttempts)/\(reconnectPolicy.maxAttempts))...", level: .warning)

                try? await transport.disconnect()

                if reconnectPolicy.baseDelay > 0 {
                    try await Task.sleep(for: .seconds(reconnectPolicy.baseDelay))
                }

                try await transport.connect()
                log("Reconnected to Switch", level: .info)
            }
        }
    }

    // MARK: - MTP Path

    private func runMTPInstallation() async {
        state = .connecting
        log("Connecting to Switch (MTP)...", level: .info)

        let files = queuedURLs.map { url -> PrivilegedMTPSession.FileToInstall in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return PrivilegedMTPSession.FileToInstall(path: url.path, name: url.lastPathComponent, size: size)
        }

        let mtpSess = mtpSession

        do {
            try await mtpSess.install(
                files: files,
                targetStorageID: mtpInstallDestination?.storageID,
                onProgress: { [weak self] fileName, sent, total in
                    Task { @MainActor in
                        if self?.state == .connecting { self?.state = .transferring }
                        self?.progress.updateProgress(fileName: fileName, transferredBytes: sent)
                    }
                },
                onLog: { [weak self] (message: String) in
                    Task { @MainActor in
                        self?.log("[MTP] \(message)", level: .debug)
                    }
                }
            )

            state = .complete
            log("Installation complete!", level: .info)
        } catch is CancellationError {
            state = .idle
            log("Installation cancelled", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("Error: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Network Path

    private func runNetworkInstallation() async {
        state = .connecting

        guard let connection = FTPConnectionInfo.parse(ftpAddress) else {
            state = .error("Invalid FTP address. Enter Switch IP:port (e.g., 192.168.0.96:5000)")
            log("Invalid FTP address: \(ftpAddress)", level: .error)
            return
        }

        log("Connecting to Switch FTP at \(connection.displayString)...", level: .info)

        do {
            state = .transferring

            for url in queuedURLs {
                let fileName = url.lastPathComponent
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

                try await ftpClient.upload(
                    file: url,
                    to: connection,
                    onProgress: { [weak self] percentage in
                        Task { @MainActor in
                            let bytes = UInt64(Double(fileSize) * percentage / 100.0)
                            self?.progress.updateProgress(fileName: fileName, transferredBytes: bytes)
                        }
                    },
                    onLog: { [weak self] (message: String) in
                        Task { @MainActor in
                            self?.log("[FTP] \(message)", level: .debug)
                        }
                    }
                )

                log("\(fileName) installed via FTP", level: .info)
            }

            state = .complete
            log("All files installed via FTP!", level: .info)
        } catch is CancellationError {
            state = .idle
            log("FTP transfer cancelled", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("FTP error: \(error.localizedDescription)", level: .error)
        }
    }

    public func log(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(message: message, level: level))
    }
}
