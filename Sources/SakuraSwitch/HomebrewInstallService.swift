import Foundation
import Installer

enum HomebrewInstallService {

    private enum InstallError: LocalizedError {
        case invalidAsset
        case invalidResponse
        case sizeMismatch(expected: Int64, actual: Int64)
        case unsafeArchiveEntry(String)
        case archiveExtractionFailed(String)
        case sphairaPayloadMissing
        case staleBackup
        case rollbackFailed(String)
        case unsupportedNROAsset(String)
        case invalidNROFile
        case unsupportedOVLAsset(String)
        case invalidOVLFile
        case destinationIsFile(String)
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .invalidAsset:
                return "Unexpected Sphaira release asset"

            case .invalidResponse:
                return "Download server returned an invalid response"

            case let .sizeMismatch(expected, actual):
                return "Downloaded size mismatch: expected \(expected), got \(actual)"

            case let .unsafeArchiveEntry(path):
                return "Unsafe ZIP path: \(path)"

            case let .archiveExtractionFailed(message):
                return "ZIP extraction failed: \(message)"

            case .sphairaPayloadMissing:
                return "switch/sphaira/sphaira.nro was not found in sphaira.zip"

            case .staleBackup:
                return "A previous installation backup already exists"

            case let .rollbackFailed(message):
                return "Installation failed and rollback also failed: \(message)"

            case let .unsupportedNROAsset(name):
                return "Unsupported NRO asset: \(name)"

            case .invalidNROFile:
                return "Downloaded NRO is not a regular file"

            case let .unsupportedOVLAsset(name):
                return "Unsupported OVL asset: \(name)"
            case .invalidOVLFile:
                return "Downloaded OVL is not a regular file"
            case let .destinationIsFile(path):
                return "Installation destination is not a directory: \(path)"

            case .verificationFailed:
                return "Uploaded file could not be verified on the Switch"
            }
        }
    }

    static func installSphaira(
        release: HomebrewRelease,
        coordinator: InstallationCoordinator
    ) async throws {

        guard release.assetName.caseInsensitiveCompare("sphaira.zip")
                == .orderedSame else {
            throw InstallError.invalidAsset
        }

        let fm = FileManager.default

        let work =
            fm.temporaryDirectory
                .appendingPathComponent(
                    "SakuraSwitch-Sphaira-\(UUID().uuidString)",
                    isDirectory: true
                )

        let archive =
            work.appendingPathComponent("sphaira.zip")

        let extracted =
            work.appendingPathComponent(
                "extracted",
                isDirectory: true
            )

        try fm.createDirectory(
            at: work,
            withIntermediateDirectories: true
        )

        try fm.createDirectory(
            at: extracted,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: work)
        }

        // MARK: Download

        let (temporaryDownload, response) =
            try await URLSession.shared.download(
                from: release.downloadURL
            )

        guard
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw InstallError.invalidResponse
        }

        try fm.moveItem(
            at: temporaryDownload,
            to: archive
        )

        let attributes =
            try fm.attributesOfItem(
                atPath: archive.path
            )

        let actualSize =
            (attributes[.size] as? NSNumber)?
                .int64Value ?? -1

        guard actualSize == release.size else {
            throw InstallError.sizeMismatch(
                expected: release.size,
                actual: actualSize
            )
        }

        // MARK: Validate ZIP paths before extraction

        let listing =
            try runProcess(
                executable: "/usr/bin/unzip",
                arguments: [
                    "-Z1",
                    archive.path
                ]
            )

        for raw in listing.components(separatedBy: .newlines) {
            let entry =
                raw.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard !entry.isEmpty else { continue }

            let normalized =
                entry.replacingOccurrences(
                    of: "\\",
                    with: "/"
                )

            let components =
                normalized.split(
                    separator: "/",
                    omittingEmptySubsequences: false
                )

            if normalized.hasPrefix("/") ||
                components.contains(where: { $0 == ".." }) {
                throw InstallError.unsafeArchiveEntry(entry)
            }
        }

        // MARK: Extract

        do {
            _ = try runProcess(
                executable: "/usr/bin/ditto",
                arguments: [
                    "-x",
                    "-k",
                    archive.path,
                    extracted.path
                ]
            )
        } catch {
            throw InstallError.archiveExtractionFailed(
                error.localizedDescription
            )
        }

        let nro =
            extracted
                .appendingPathComponent("switch")
                .appendingPathComponent("sphaira")
                .appendingPathComponent("sphaira.nro")

        var isDirectory: ObjCBool = false

        guard
            fm.fileExists(
                atPath: nro.path,
                isDirectory: &isDirectory
            ),
            !isDirectory.boolValue
        else {
            throw InstallError.sphairaPayloadMissing
        }

        let values =
            try nro.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ]
            )

        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw InstallError.sphairaPayloadMissing
        }

        // MARK: Prepare /switch/sphaira

        let switchItems =
            try await coordinator.browseSDCard(
                path: "/switch"
            )

        let sphairaFolder =
            switchItems.first {
                $0.name.caseInsensitiveCompare("sphaira")
                    == .orderedSame
            }

        if let sphairaFolder {
            guard sphairaFolder.isDirectory else {
                throw InstallError.staleBackup
            }
        } else {
            try await coordinator.createSDCardFolder(
                parentPath: "/switch",
                folderName: "sphaira"
            )
        }

        var remoteItems =
            try await coordinator.browseSDCard(
                path: "/switch/sphaira"
            )

        let originalName = "sphaira.nro"
        let backupName = "sphaira.nro.sakura-backup"

        var originalExists =
            remoteItems.contains {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(originalName)
                    == .orderedSame
            }

        var backupExists =
            remoteItems.contains {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(backupName)
                    == .orderedSame
            }

        // Если прошлый запуск упал ПОСЛЕ rename,
        // но ДО восстановления — сначала восстанавливаем.
        if backupExists && !originalExists {
            try await coordinator.renameSDCardItem(
                parentPath: "/switch/sphaira",
                oldName: backupName,
                newName: originalName
            )

            remoteItems =
                try await coordinator.browseSDCard(
                    path: "/switch/sphaira"
                )

            originalExists =
                remoteItems.contains {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(originalName)
                        == .orderedSame
                }

            backupExists =
                remoteItems.contains {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(backupName)
                        == .orderedSame
                }
        }

        // Если есть И оригинал, И старый backup —
        // ничего автоматически не удаляем.
        guard !backupExists else {
            throw InstallError.staleBackup
        }

        var didBackup = false

        if originalExists {
            try await coordinator.renameSDCardItem(
                parentPath: "/switch/sphaira",
                oldName: originalName,
                newName: backupName
            )

            didBackup = true
        }

        // MARK: Transactional upload

        do {
            try await coordinator.uploadSDCardFile(
                nro,
                destinationPath: "/switch/sphaira"
            )

            if didBackup {
                try await coordinator.deleteSDCardItem(
                    parentPath: "/switch/sphaira",
                    itemName: backupName
                )
            }

        } catch {
            let originalError = error

            guard didBackup else {
                throw originalError
            }

            do {
                let current =
                    try await coordinator.browseSDCard(
                        path: "/switch/sphaira"
                    )

                let partialExists =
                    current.contains {
                        !$0.isDirectory &&
                        $0.name.caseInsensitiveCompare(originalName)
                            == .orderedSame
                    }

                if partialExists {
                    try await coordinator.deleteSDCardItem(
                        parentPath: "/switch/sphaira",
                        itemName: originalName
                    )
                }

                try await coordinator.renameSDCardItem(
                    parentPath: "/switch/sphaira",
                    oldName: backupName,
                    newName: originalName
                )

            } catch {
                throw InstallError.rollbackFailed(
                    error.localizedDescription
                )
            }

            throw originalError
        }
    }


    // MARK: - Universal Standalone NRO Installation

    private struct NRORecipe {
        let destinationPath: String
        let destinationName: String
    }

    private static func nroRecipe(
        for assetName: String
    ) -> NRORecipe? {

        switch assetName.lowercased() {

        // Canonical standalone NRO paths.
        // DBI: update only DBI.nro. Existing dbi.config is never touched.
        case "dbi.nro":
            return NRORecipe(
                destinationPath: "/switch/DBI",
                destinationName: "DBI.nro"
            )

        case "switch_newpipe.nro":
            return NRORecipe(
                destinationPath: "/switch",
                destinationName: "switch_newpipe.nro"
            )

        case "ftpd.nro":
            return NRORecipe(
                destinationPath: "/switch",
                destinationName: "ftpd.nro"
            )

        case "simplemodmanager.nro":
            return NRORecipe(
                destinationPath: "/switch",
                destinationName: "SimpleModManager.nro"
            )

        case "moonlight-switch.nro":
            return NRORecipe(
                destinationPath: "/switch/Moonlight-Switch",
                destinationName: "Moonlight-Switch.nro"
            )

        case "checkpoint.nro":
            return NRORecipe(
                destinationPath: "/switch/Checkpoint",
                destinationName: "Checkpoint.nro"
            )

        case "goldleaf.nro":
            return NRORecipe(
                destinationPath: "/switch/Goldleaf",
                destinationName: "Goldleaf.nro"
            )

        case "appstore.nro":
            return NRORecipe(
                destinationPath: "/switch/appstore",
                destinationName: "appstore.nro"
            )

        case "themezer-nx.nro":
            return NRORecipe(
                destinationPath: "/switch/ThemezerNX",
                destinationName: "themezer-nx.nro"
            )

        default:
            guard assetName.lowercased().hasSuffix(".nro") else {
                return nil
            }

            let stem = String(assetName.dropLast(4))

            let safeStem = String(
                stem.map { character in
                    if character.isLetter ||
                        character.isNumber ||
                        character == "-" ||
                        character == "_" ||
                        character == "." {
                        return character
                    }

                    return "_"
                }
            )

            guard !safeStem.isEmpty else {
                return nil
            }

            return NRORecipe(
                destinationPath: "/switch/\(safeStem)",
                destinationName: assetName
            )
        }
    }


    // MARK: - Universal Standalone OVL Installation

    private static func isStandaloneOVL(
        _ release: HomebrewRelease
    ) -> Bool {
        release.assetName.lowercased().hasSuffix(".ovl")
    }

    static func installOVL(
        release: HomebrewRelease,
        coordinator: InstallationCoordinator
    ) async throws {

        guard release.downloadURL.scheme?.lowercased() == "https" else {
            throw InstallError.invalidResponse
        }

        guard isStandaloneOVL(release) else {
            throw InstallError.unsupportedOVLAsset(
                release.assetName
            )
        }

        let fm = FileManager.default
        let destinationPath = "/switch/.overlays"
        let originalName = release.assetName
        let backupName = "\(originalName).sakura-backup"

        let work =
            fm.temporaryDirectory.appendingPathComponent(
                "SakuraSwitch-OVL-\(UUID().uuidString)",
                isDirectory: true
            )

        try fm.createDirectory(
            at: work,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: work)
        }

        let localFile =
            work.appendingPathComponent(originalName)

        // Download
        let (temporaryDownload, response) =
            try await URLSession.shared.download(
                from: release.downloadURL
            )

        guard
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw InstallError.invalidResponse
        }

        try fm.moveItem(
            at: temporaryDownload,
            to: localFile
        )

        let attributes =
            try fm.attributesOfItem(
                atPath: localFile.path
            )

        let actualSize =
            (attributes[.size] as? NSNumber)?
                .int64Value ?? -1

        guard
            release.size <= 0 ||
            actualSize == release.size
        else {
            throw InstallError.sizeMismatch(
                expected: release.size,
                actual: actualSize
            )
        }

        let values =
            try localFile.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ]
            )

        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw InstallError.invalidOVLFile
        }

        // Ensure /switch/.overlays
        let switchItems =
            try await coordinator.browseSDCard(
                path: "/switch"
            )

        if let overlays =
            switchItems.first(where: {
                $0.name.caseInsensitiveCompare(
                    ".overlays"
                ) == .orderedSame
            }) {

            guard overlays.isDirectory else {
                throw InstallError.destinationIsFile(
                    destinationPath
                )
            }

        } else {

            try await coordinator.createSDCardFolder(
                parentPath: "/switch",
                folderName: ".overlays"
            )
        }

        // Current state
        var remoteItems =
            try await coordinator.browseSDCard(
                path: destinationPath
            )

        var originalItem =
            remoteItems.first(where: {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(
                    originalName
                ) == .orderedSame
            })

        var backupItem =
            remoteItems.first(where: {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(
                    backupName
                ) == .orderedSame
            })

        // Recover interrupted previous transaction.
        if backupItem != nil && originalItem == nil {

            try await coordinator.renameSDCardItem(
                parentPath: destinationPath,
                oldName: backupItem!.name,
                newName: originalName
            )

            remoteItems =
                try await coordinator.browseSDCard(
                    path: destinationPath
                )

            originalItem =
                remoteItems.first(where: {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(
                        originalName
                    ) == .orderedSame
                })

            backupItem =
                remoteItems.first(where: {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(
                        backupName
                    ) == .orderedSame
                })
        }

        // Ambiguous state: do not destroy anything.
        guard backupItem == nil else {
            throw InstallError.staleBackup
        }

        var didBackup = false

        if let originalItem {

            try await coordinator.renameSDCardItem(
                parentPath: destinationPath,
                oldName: originalItem.name,
                newName: backupName
            )

            didBackup = true
        }

        // Upload + verify + commit.
        do {

            try await coordinator.uploadSDCardFile(
                localFile,
                destinationPath: destinationPath
            )

            let afterUpload =
                try await coordinator.browseSDCard(
                    path: destinationPath
                )

            let uploadedExists =
                afterUpload.contains(where: {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(
                        originalName
                    ) == .orderedSame
                })

            guard uploadedExists else {
                throw InstallError.verificationFailed
            }

            if didBackup {

                try await coordinator.deleteSDCardItem(
                    parentPath: destinationPath,
                    itemName: backupName
                )
            }

        } catch {

            let originalError = error

            do {

                let current =
                    try await coordinator.browseSDCard(
                        path: destinationPath
                    )

                if let currentOriginal =
                    current.first(where: {
                        !$0.isDirectory &&
                        $0.name.caseInsensitiveCompare(
                            originalName
                        ) == .orderedSame
                    }) {

                    try await coordinator.deleteSDCardItem(
                        parentPath: destinationPath,
                        itemName: currentOriginal.name
                    )
                }

                if didBackup {

                    let rollbackState =
                        try await coordinator.browseSDCard(
                            path: destinationPath
                        )

                    guard let backup =
                        rollbackState.first(where: {
                            !$0.isDirectory &&
                            $0.name.caseInsensitiveCompare(
                                backupName
                            ) == .orderedSame
                        })
                    else {
                        throw InstallError.rollbackFailed(
                            "Backup disappeared before restore"
                        )
                    }

                    try await coordinator.renameSDCardItem(
                        parentPath: destinationPath,
                        oldName: backup.name,
                        newName: originalName
                    )
                }

            } catch {

                throw InstallError.rollbackFailed(
                    error.localizedDescription
                )
            }

            throw originalError
        }
    }


    static func canInstall(
        release: HomebrewRelease
    ) -> Bool {

        let lower = release.assetName.lowercased()

        return
            lower.hasSuffix(".nro") ||
            lower.hasSuffix(".ovl") ||
            lower.hasSuffix(".zip") ||
            lower.hasSuffix(".7z") ||
            lower.hasSuffix(".bin")
    }

    static func installNRO(
        release: HomebrewRelease,
        coordinator: InstallationCoordinator
    ) async throws {

        guard release.downloadURL.scheme?.lowercased() == "https" else {
            throw InstallError.invalidResponse
        }

        guard let recipe = nroRecipe(for: release.assetName) else {
            throw InstallError.unsupportedNROAsset(
                release.assetName
            )
        }

        let fm = FileManager.default

        let work = fm.temporaryDirectory.appendingPathComponent(
            "SakuraSwitch-NRO-\(UUID().uuidString)",
            isDirectory: true
        )

        try fm.createDirectory(
            at: work,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: work)
        }

        let localFile = work.appendingPathComponent(
            recipe.destinationName
        )

        // Download

        let (temporaryDownload, response) =
            try await URLSession.shared.download(
                from: release.downloadURL
            )

        guard
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw InstallError.invalidResponse
        }

        try fm.moveItem(
            at: temporaryDownload,
            to: localFile
        )

        let attributes = try fm.attributesOfItem(
            atPath: localFile.path
        )

        let actualSize =
            (attributes[.size] as? NSNumber)?.int64Value ?? -1

        guard
            release.size <= 0 ||
            actualSize == release.size
        else {
            throw InstallError.sizeMismatch(
                expected: release.size,
                actual: actualSize
            )
        }

        let values = try localFile.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        )

        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw InstallError.invalidNROFile
        }

        // Prepare destination folder

        if recipe.destinationPath != "/switch" {

            let prefix = "/switch/"

            guard recipe.destinationPath.hasPrefix(prefix) else {
                throw InstallError.destinationIsFile(
                    recipe.destinationPath
                )
            }

            let folderName = String(
                recipe.destinationPath.dropFirst(prefix.count)
            )

            guard
                !folderName.isEmpty,
                !folderName.contains("/")
            else {
                throw InstallError.destinationIsFile(
                    recipe.destinationPath
                )
            }

            let switchItems = try await coordinator.browseSDCard(
                path: "/switch"
            )

            if let existing = switchItems.first(where: {
                $0.name.caseInsensitiveCompare(folderName)
                    == .orderedSame
            }) {

                guard existing.isDirectory else {
                    throw InstallError.destinationIsFile(
                        recipe.destinationPath
                    )
                }

            } else {

                try await coordinator.createSDCardFolder(
                    parentPath: "/switch",
                    folderName: folderName
                )
            }
        }

        // Inspect existing state

        var remoteItems = try await coordinator.browseSDCard(
            path: recipe.destinationPath
        )

        let originalName = recipe.destinationName
        let backupName =
            "\(recipe.destinationName).sakura-backup"

        var originalItem = remoteItems.first(where: {
            !$0.isDirectory &&
            $0.name.caseInsensitiveCompare(originalName)
                == .orderedSame
        })

        var backupItem = remoteItems.first(where: {
            !$0.isDirectory &&
            $0.name.caseInsensitiveCompare(backupName)
                == .orderedSame
        })

        // Recover interrupted previous transaction

        if backupItem != nil && originalItem == nil {

            try await coordinator.renameSDCardItem(
                parentPath: recipe.destinationPath,
                oldName: backupItem!.name,
                newName: originalName
            )

            remoteItems = try await coordinator.browseSDCard(
                path: recipe.destinationPath
            )

            originalItem = remoteItems.first(where: {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(originalName)
                    == .orderedSame
            })

            backupItem = remoteItems.first(where: {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(backupName)
                    == .orderedSame
            })
        }

        // If backup still exists, state is ambiguous.
        // Destroy nothing.

        guard backupItem == nil else {
            throw InstallError.staleBackup
        }

        // Backup current NRO

        var didBackup = false

        if let originalItem {

            try await coordinator.renameSDCardItem(
                parentPath: recipe.destinationPath,
                oldName: originalItem.name,
                newName: backupName
            )

            didBackup = true
        }

        // Upload + verification + commit

        do {

            try await coordinator.uploadSDCardFile(
                localFile,
                destinationPath: recipe.destinationPath
            )

            let afterUpload = try await coordinator.browseSDCard(
                path: recipe.destinationPath
            )

            let uploadedExists = afterUpload.contains(where: {
                !$0.isDirectory &&
                $0.name.caseInsensitiveCompare(originalName)
                    == .orderedSame
            })

            guard uploadedExists else {
                throw InstallError.verificationFailed
            }

            if didBackup {
                try await coordinator.deleteSDCardItem(
                    parentPath: recipe.destinationPath,
                    itemName: backupName
                )
            }

        } catch {

            let originalError = error

            do {

                let current = try await coordinator.browseSDCard(
                    path: recipe.destinationPath
                )

                if let currentOriginal = current.first(where: {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(originalName)
                        == .orderedSame
                }) {

                    try await coordinator.deleteSDCardItem(
                        parentPath: recipe.destinationPath,
                        itemName: currentOriginal.name
                    )
                }

                if didBackup {

                    let rollbackState =
                        try await coordinator.browseSDCard(
                            path: recipe.destinationPath
                        )

                    guard let backup = rollbackState.first(where: {
                        !$0.isDirectory &&
                        $0.name.caseInsensitiveCompare(backupName)
                            == .orderedSame
                    }) else {
                        throw InstallError.rollbackFailed(
                            "Backup disappeared before restore"
                        )
                    }

                    try await coordinator.renameSDCardItem(
                        parentPath: recipe.destinationPath,
                        oldName: backup.name,
                        newName: originalName
                    )
                }

            } catch {
                throw InstallError.rollbackFailed(
                    error.localizedDescription
                )
            }

            throw originalError
        }
    }


    // MARK: - Universal Package Installation

    private struct PackageFile {
        let localURL: URL
        let remotePath: String
    }

    private struct PackageTransaction {
        let parentPath: String
        let name: String
        let backupName: String
        let hadOriginal: Bool
    }

    static func installRelease(
        release: HomebrewRelease,
        coordinator: InstallationCoordinator
    ) async throws {

        let lower = release.assetName.lowercased()

        if lower == "sphaira.zip" {
            try await installSphaira(
                release: release,
                coordinator: coordinator
            )
            return
        }

        if lower.hasSuffix(".nro") {
            try await installNRO(
                release: release,
                coordinator: coordinator
            )
            return
        }

        if lower.hasSuffix(".ovl") {
            try await installOVL(
                release: release,
                coordinator: coordinator
            )
            return
        }

        if lower.hasSuffix(".bin") {
            try await installPayload(
                release: release,
                coordinator: coordinator
            )
            return
        }

        if lower.hasSuffix(".zip") ||
            lower.hasSuffix(".7z") {

            try await installArchivePackage(
                release: release,
                coordinator: coordinator
            )
            return
        }

        throw InstallError.unsupportedNROAsset(
            release.assetName
        )
    }


    private static func installPayload(
        release: HomebrewRelease,
        coordinator: InstallationCoordinator
    ) async throws {

        guard release.downloadURL.scheme?.lowercased() == "https" else {
            throw InstallError.invalidResponse
        }

        let fm = FileManager.default

        let work = fm.temporaryDirectory.appendingPathComponent(
            "SakuraSwitch-Payload-\(UUID().uuidString)",
            isDirectory: true
        )

        try fm.createDirectory(
            at: work,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: work)
        }

        let local = work.appendingPathComponent(
            release.assetName
        )

        let (download, response) =
            try await URLSession.shared.download(
                from: release.downloadURL
            )

        guard
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw InstallError.invalidResponse
        }

        try fm.moveItem(
            at: download,
            to: local
        )

        try validateDownloadedPackageFile(
            local,
            expectedSize: release.size
        )

        try await installPackageFiles(
            [
                PackageFile(
                    localURL: local,
                    remotePath:
                        "/bootloader/payloads/\(release.assetName)"
                )
            ],
            coordinator: coordinator
        )
    }


    private static func installArchivePackage(
        release: HomebrewRelease,
        coordinator: InstallationCoordinator
    ) async throws {

        guard release.downloadURL.scheme?.lowercased() == "https" else {
            throw InstallError.invalidResponse
        }

        let fm = FileManager.default

        let work = fm.temporaryDirectory.appendingPathComponent(
            "SakuraSwitch-Package-\(UUID().uuidString)",
            isDirectory: true
        )

        let archive = work.appendingPathComponent(
            release.assetName
        )

        let extracted = work.appendingPathComponent(
            "extracted",
            isDirectory: true
        )

        try fm.createDirectory(
            at: extracted,
            withIntermediateDirectories: true
        )

        defer {
            try? fm.removeItem(at: work)
        }

        let (download, response) =
            try await URLSession.shared.download(
                from: release.downloadURL
            )

        guard
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw InstallError.invalidResponse
        }

        try fm.moveItem(
            at: download,
            to: archive
        )

        try validateDownloadedPackageFile(
            archive,
            expectedSize: release.size
        )

        let lower = release.assetName.lowercased()
        let listing: String

        do {
            if lower.hasSuffix(".zip") {
                listing = try runProcess(
                    executable: "/usr/bin/unzip",
                    arguments: [
                        "-Z1",
                        archive.path
                    ]
                )
            } else {
                listing = try runProcess(
                    executable: "/usr/bin/tar",
                    arguments: [
                        "-tf",
                        archive.path
                    ]
                )
            }
        } catch {
            throw InstallError.archiveExtractionFailed(
                "Archive listing failed: \(error.localizedDescription)"
            )
        }

        try validateArchiveListing(listing)

        do {
            if lower.hasSuffix(".zip") {
                _ = try runProcess(
                    executable: "/usr/bin/ditto",
                    arguments: [
                        "-x",
                        "-k",
                        archive.path,
                        extracted.path
                    ]
                )
            } else {
                _ = try runProcess(
                    executable: "/usr/bin/tar",
                    arguments: [
                        "-xf",
                        archive.path,
                        "-C",
                        extracted.path
                    ]
                )
            }
        } catch {
            throw InstallError.archiveExtractionFailed(
                error.localizedDescription
            )
        }

        try removeArchiveMetadata(
            from: extracted
        )

        try validateExtractedTree(
            extracted
        )

        let files = try makePackagePlan(
            extractedRoot: extracted,
            assetName: release.assetName
        )

        guard !files.isEmpty else {
            throw InstallError.archiveExtractionFailed(
                "Archive contains no installable files"
            )
        }

        try await installPackageFiles(
            files,
            coordinator: coordinator
        )
    }


    private static func validateDownloadedPackageFile(
        _ url: URL,
        expectedSize: Int64
    ) throws {

        let fm = FileManager.default

        let values = try url.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        )

        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw InstallError.invalidNROFile
        }

        let attributes = try fm.attributesOfItem(
            atPath: url.path
        )

        let actual =
            (attributes[.size] as? NSNumber)?
                .int64Value ?? -1

        guard
            expectedSize <= 0 ||
            actual == expectedSize
        else {
            throw InstallError.sizeMismatch(
                expected: expectedSize,
                actual: actual
            )
        }
    }


    private static func validateArchiveListing(
        _ listing: String
    ) throws {

        for rawLine in listing.split(
            whereSeparator: \.isNewline
        ) {

            let raw = String(rawLine)

            let normalized =
                raw.replacingOccurrences(
                    of: "\\",
                    with: "/"
                )

            if normalized.hasPrefix("/") {
                throw InstallError.unsafeArchiveEntry(
                    raw
                )
            }

            let parts = normalized.split(
                separator: "/",
                omittingEmptySubsequences: true
            )

            if parts.contains(where: { $0 == ".." }) {
                throw InstallError.unsafeArchiveEntry(
                    raw
                )
            }

            if normalized.contains("\0") {
                throw InstallError.unsafeArchiveEntry(
                    raw
                )
            }
        }
    }


    private static func removeArchiveMetadata(
        from root: URL
    ) throws {

        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: [],
            errorHandler: nil
        ) else {
            return
        }

        var removals: [URL] = []

        for case let url as URL in enumerator {

            let name = url.lastPathComponent

            if name == ".DS_Store" ||
                name.hasPrefix("._") ||
                name == "__MACOSX" {

                removals.append(url)
            }
        }

        removals.sort {
            $0.pathComponents.count >
                $1.pathComponents.count
        }

        for url in removals {
            try? fm.removeItem(at: url)
        }
    }


    private static func validateExtractedTree(
        _ root: URL
    ) throws {

        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isSymbolicLinkKey
            ],
            options: [],
            errorHandler: nil
        ) else {
            return
        }

        for case let url as URL in enumerator {

            let values = try url.resourceValues(
                forKeys: [
                    .isSymbolicLinkKey
                ]
            )

            if values.isSymbolicLink == true {
                throw InstallError.unsafeArchiveEntry(
                    url.lastPathComponent
                )
            }
        }
    }


    private static let knownSDRootDirectories:
        Set<String> = [
            "switch",
            "atmosphere",
            "config",
            "bootloader",
            "saltysd",
            "emuiibo",
            "sept"
        ]


    private static func makePackagePlan(
        extractedRoot: URL,
        assetName: String
    ) throws -> [PackageFile] {

        let fm = FileManager.default

        let initialEntries = try fm.contentsOfDirectory(
            at: extractedRoot,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: []
        )
        .filter {
            !isMetadataURL($0)
        }

        var packageRoot = extractedRoot

        if initialEntries.count == 1 {

            let only = initialEntries[0]

            let values = try only.resourceValues(
                forKeys: [
                    .isDirectoryKey
                ]
            )

            if values.isDirectory == true {

                let children = try fm.contentsOfDirectory(
                    at: only,
                    includingPropertiesForKeys: [
                        .isDirectoryKey
                    ],
                    options: []
                )

                if containsKnownSDRoot(children) {
                    packageRoot = only
                }
            }
        }

        let entries = try fm.contentsOfDirectory(
            at: packageRoot,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: []
        )
        .filter {
            !isMetadataURL($0)
        }

        if containsKnownSDRoot(entries) {
            return try enumeratePackageFiles(
                under: packageRoot,
                remoteBase: "/"
            )
        }

        var appRoot = packageRoot
        var folder = preferredSwitchFolder(
            for: assetName
        )

        if entries.count == 1 {

            let only = entries[0]

            let values = try only.resourceValues(
                forKeys: [
                    .isDirectoryKey
                ]
            )

            if values.isDirectory == true {

                appRoot = only

                if folder.isEmpty {
                    folder = sanitizedFolderName(
                        only.lastPathComponent
                    )
                }
            }
        }

        if folder.isEmpty {
            folder = "Homebrew"
        }

        return try enumeratePackageFiles(
            under: appRoot,
            remoteBase:
                "/switch/\(folder)"
        )
    }


    private static func containsKnownSDRoot(
        _ urls: [URL]
    ) -> Bool {

        for url in urls {

            if knownSDRootDirectories.contains(
                url.lastPathComponent.lowercased()
            ) {
                return true
            }
        }

        return false
    }


    private static func preferredSwitchFolder(
        for assetName: String
    ) -> String {

        let lower = assetName.lowercased()

        if lower.contains("aio-switch-updater") {
            return "aio-switch-updater"
        }

        if lower.contains("wiliwili") {
            return "wiliwili"
        }

        if lower.contains("breeze") {
            return "Breeze"
        }

        if lower.contains("cyberfoil") {
            return "CyberFoil"
        }

        if lower.contains("linkalho") {
            return "linkalho"
        }

        if lower.contains("nssu-updater") {
            return "nssu-updater"
        }

        if lower.contains("nxmp") {
            return "nxmp"
        }

        if lower.contains("mgba") {
            return "mgba"
        }

        var stem = assetName

        if let dot = stem.lastIndex(of: ".") {
            stem = String(
                stem[..<dot]
            )
        }

        return sanitizedFolderName(stem)
    }


    private static func sanitizedFolderName(
        _ value: String
    ) -> String {

        return String(
            value.map { character in

                if character.isLetter ||
                    character.isNumber ||
                    character == "-" ||
                    character == "_" ||
                    character == "." {

                    return character
                }

                return "_"
            }
        )
    }


    private static func isMetadataURL(
        _ url: URL
    ) -> Bool {

        let name = url.lastPathComponent

        return
            name == ".DS_Store" ||
            name.hasPrefix("._") ||
            name == "__MACOSX"
    }


    private static func enumeratePackageFiles(
        under root: URL,
        remoteBase: String
    ) throws -> [PackageFile] {

        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ],
            options: [],
            errorHandler: nil
        ) else {
            return []
        }

        var result: [PackageFile] = []

        let prefix =
            root.path.hasSuffix("/")
            ? root.path
            : root.path + "/"

        for case let url as URL in enumerator {

            if isMetadataURL(url) {
                continue
            }

            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ]
            )

            if values.isSymbolicLink == true {
                throw InstallError.unsafeArchiveEntry(
                    url.lastPathComponent
                )
            }

            guard values.isRegularFile == true else {
                continue
            }

            guard url.path.hasPrefix(prefix) else {
                throw InstallError.unsafeArchiveEntry(
                    url.path
                )
            }

            let relative = String(
                url.path.dropFirst(prefix.count)
            )

            guard !relative.isEmpty else {
                continue
            }

            let remotePath =
                remoteBase == "/"
                ? "/" + relative
                : remoteBase + "/" + relative

            result.append(
                PackageFile(
                    localURL: url,
                    remotePath: remotePath
                )
            )
        }

        result.sort {
            $0.remotePath.localizedStandardCompare(
                $1.remotePath
            ) == .orderedAscending
        }

        return result
    }


    private static func installPackageFiles(
        _ files: [PackageFile],
        coordinator: InstallationCoordinator
    ) async throws {

        var transactions: [PackageTransaction] = []

        do {

            for file in files {

                let nsPath =
                    file.remotePath as NSString

                var parentPath =
                    nsPath.deletingLastPathComponent

                if parentPath.isEmpty {
                    parentPath = "/"
                }

                let name =
                    nsPath.lastPathComponent

                guard
                    !name.isEmpty,
                    name != ".",
                    name != ".."
                else {
                    throw InstallError.unsafeArchiveEntry(
                        file.remotePath
                    )
                }

                try await ensureRemoteDirectory(
                    parentPath,
                    coordinator: coordinator
                )

                var items =
                    try await coordinator.browseSDCard(
                        path: parentPath
                    )

                var original =
                    items.first(where: {
                        !$0.isDirectory &&
                        $0.name.caseInsensitiveCompare(
                            name
                        ) == .orderedSame
                    })

                let backupName =
                    "\(name).sakura-backup"

                var backup =
                    items.first(where: {
                        !$0.isDirectory &&
                        $0.name.caseInsensitiveCompare(
                            backupName
                        ) == .orderedSame
                    })

                if backup != nil &&
                    original == nil {

                    try await coordinator.renameSDCardItem(
                        parentPath: parentPath,
                        oldName: backup!.name,
                        newName: name
                    )

                    items =
                        try await coordinator.browseSDCard(
                            path: parentPath
                        )

                    original =
                        items.first(where: {
                            !$0.isDirectory &&
                            $0.name.caseInsensitiveCompare(
                                name
                            ) == .orderedSame
                        })

                    backup =
                        items.first(where: {
                            !$0.isDirectory &&
                            $0.name.caseInsensitiveCompare(
                                backupName
                            ) == .orderedSame
                        })
                }

                guard backup == nil else {
                    throw InstallError.staleBackup
                }

                if original != nil &&
                    shouldPreserveExisting(
                        file.remotePath
                    ) {

                    continue
                }

                var hadOriginal = false

                if let original {

                    try await coordinator.renameSDCardItem(
                        parentPath: parentPath,
                        oldName: original.name,
                        newName: backupName
                    )

                    hadOriginal = true
                }

                transactions.append(
                    PackageTransaction(
                        parentPath: parentPath,
                        name: name,
                        backupName: backupName,
                        hadOriginal: hadOriginal
                    )
                )

                try await coordinator.uploadSDCardFile(
                    file.localURL,
                    destinationPath: parentPath
                )

                let after =
                    try await coordinator.browseSDCard(
                        path: parentPath
                    )

                guard after.contains(where: {
                    !$0.isDirectory &&
                    $0.name.caseInsensitiveCompare(
                        name
                    ) == .orderedSame
                }) else {
                    throw InstallError.verificationFailed
                }
            }

        } catch {

            let originalError = error

            do {

                for transaction in
                    transactions.reversed() {

                    let current =
                        try await coordinator.browseSDCard(
                            path:
                                transaction.parentPath
                        )

                    if let installed =
                        current.first(where: {
                            !$0.isDirectory &&
                            $0.name.caseInsensitiveCompare(
                                transaction.name
                            ) == .orderedSame
                        }) {

                        try await coordinator.deleteSDCardItem(
                            parentPath:
                                transaction.parentPath,
                            itemName:
                                installed.name
                        )
                    }

                    if transaction.hadOriginal {

                        let state =
                            try await coordinator.browseSDCard(
                                path:
                                    transaction.parentPath
                            )

                        guard let backup =
                            state.first(where: {
                                !$0.isDirectory &&
                                $0.name.caseInsensitiveCompare(
                                    transaction.backupName
                                ) == .orderedSame
                            })
                        else {
                            throw InstallError.rollbackFailed(
                                "Backup disappeared: \(transaction.name)"
                            )
                        }

                        try await coordinator.renameSDCardItem(
                            parentPath:
                                transaction.parentPath,
                            oldName:
                                backup.name,
                            newName:
                                transaction.name
                        )
                    }
                }

            } catch {
                throw InstallError.rollbackFailed(
                    error.localizedDescription
                )
            }

            throw originalError
        }

        for transaction in transactions {

            guard transaction.hadOriginal else {
                continue
            }

            try? await coordinator.deleteSDCardItem(
                parentPath:
                    transaction.parentPath,
                itemName:
                    transaction.backupName
            )
        }
    }


    private static func ensureRemoteDirectory(
        _ requestedPath: String,
        coordinator: InstallationCoordinator
    ) async throws {

        let normalized =
            requestedPath.hasPrefix("/")
            ? requestedPath
            : "/" + requestedPath

        if normalized == "/" {
            return
        }

        let components =
            normalized.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            .map(String.init)

        var parent = "/"

        for component in components {

            let items =
                try await coordinator.browseSDCard(
                    path: parent
                )

            if let existing =
                items.first(where: {
                    $0.name.caseInsensitiveCompare(
                        component
                    ) == .orderedSame
                }) {

                guard existing.isDirectory else {
                    throw InstallError.destinationIsFile(
                        parent + "/" + component
                    )
                }

            } else {

                try await coordinator.createSDCardFolder(
                    parentPath: parent,
                    folderName: component
                )
            }

            parent =
                parent == "/"
                ? "/" + component
                : parent + "/" + component
        }
    }


    private static func shouldPreserveExisting(
        _ remotePath: String
    ) -> Bool {

        let lower =
            remotePath.lowercased()

        let name =
            (lower as NSString)
                .lastPathComponent

        if name == "config.ini" ||
            name == "config.json" ||
            name == "settings.ini" ||
            name == "settings.json" {

            return true
        }

        if lower.hasPrefix(
            "/config/sys-clk/"
        ) {
            return true
        }

        if lower ==
            "/switch/dbi/dbi.config" {

            return true
        }

        return false
    }


    private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> String {

        let process = Process()
        let pipe = Pipe()

        process.executableURL =
            URL(fileURLWithPath: executable)

        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data =
            pipe.fileHandleForReading
                .readDataToEndOfFile()

        let output =
            String(
                data: data,
                encoding: .utf8
            ) ?? ""

        guard process.terminationStatus == 0 else {
            throw InstallError.archiveExtractionFailed(
                output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }

        return output
    }
}
