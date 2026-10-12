import Foundation
import SwiftUI
import StorageCore

/// Read-only external physical storage discovery. No mount, format or write operations.
struct StorageCenterView: View {
    @State private var disks: [SafeExternalDisk] = []
    @State private var selectedDiskID: String?
    @State private var loading = false
    @State private var hasScanned = false
    @State private var scanError: String?
    @State private var partitions: [StoragePartitionRow] = []
    @State private var partitionLoading = false
    @State private var partitionError: String?
    @State private var partitionRequestID = UUID()
    @State private var emummcReport: EmuMMCScanResult?
    @State private var emummcLoading = false
    @State private var inventoryLoading = false
    @State private var inventoryReport: StorageInventoryScanResult?
    @State private var showTechnicalDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sakura Storage Center")
                        .font(.title2.weight(.semibold))
                    Text("Информация о карте и файловой emuMMC")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Проверка без изменений") {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Здесь Sakura только считывает информацию: данные на карте не изменяются.", systemImage: "lock.shield")
                        Label("Подключите microSD к Mac через кардридер, а не через USB Nintendo Switch.", systemImage: "sdcard")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Внешние физические накопители")
                                .font(.headline)
                            Spacer()
                            Button {
                                Task { await refresh() }
                            } label: {
                                Label("Обновить", systemImage: "arrow.clockwise")
                            }
                            .disabled(loading)
                        }

                        if let scanError {
                            Label(scanError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if loading {
                            ProgressView("Проверяем подключённые диски…")
                        } else if disks.isEmpty && hasScanned && scanError == nil {
                            Label("Внешние физические накопители не обнаружены.",
                                  systemImage: "externaldrive")
                        } else if !hasScanned {
                            Text("Нажмите «Обновить», чтобы получить список дисков.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(disks) { disk in
                                Button {
                                    selectedDiskID = disk.id
                                    partitionRequestID = UUID()
                                    partitions = []
                                    partitionError = nil
                                    emummcReport = nil
                                    emummcLoading = true
                                    inventoryLoading = true
                                    inventoryReport = nil
                                    partitionLoading = true
                                    let requestID = partitionRequestID
                                    Task { await loadPartitions(for: disk, requestID: requestID) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "externaldrive")
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(disk.volumeName ?? "Без названия")
                                                .fontWeight(.semibold)
                                            Text("\(disk.id) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: disk.size), countStyle: .file)) · \(disk.partitionScheme)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedDiskID == disk.id {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                    }
                                    .padding(9)
                                    .contentShape(Rectangle())
                                    .background(selectedDiskID == disk.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Отображаются только диски, прошедшие дополнительную проверку diskutil info. Выбор диска ничего на нём не изменяет.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                } label: {
                    Text("Накопители")
                }

                GroupBox("Результат анализа") {
                    VStack(alignment: .leading, spacing: 10) {
                        if selectedDiskID == nil {
                            Label("Выберите карту выше — Sakura покажет результат проверки.", systemImage: "sdcard")
                                .foregroundStyle(.secondary)
                        } else if partitionLoading || emummcLoading || inventoryLoading {
                            ProgressView("Проверяем карту и её файлы…")
                        } else {
                            if let partitionError {
                                Label("Не удалось проверить разделы карты", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(partitionError).font(.caption).foregroundStyle(.secondary)
                            } else if let report = inventoryReport {
                                Label(report.complete ? "Список файлов составлен" : "Проверка файлов завершена с замечаниями",
                                      systemImage: report.complete ? "checkmark.circle" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(report.complete ? .green : .orange)
                                if let count = report.fileCount, let bytes = report.totalBytes {
                                    Text("Файлов: \(count) · Объём: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary))")
                                }
                            } else {
                                Label("Результат проверки файлов пока недоступен", systemImage: "info.circle")
                            }
                            if let emummcReport {
                                Label(emummcReport.title,
                                      systemImage: emummcReport.found ? "internaldrive" : "info.circle")
                                if let mode = emummcReport.mode {
                                    Text("Тип emuMMC: \(mode)").foregroundStyle(.secondary)
                                }
                            }
                            Text("Это проверка структуры и списка файлов, а не проверка исправности microSD или целостности NAND.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                DisclosureGroup("Технические сведения: разделы, emuMMC и файлы", isExpanded: $showTechnicalDetails) {
                    VStack(alignment: .leading, spacing: 14) {
                GroupBox("Разделы выбранного накопителя") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let selectedDiskID {
                            Text("Диск: \(selectedDiskID)").font(.subheadline.weight(.semibold))
                            if partitionLoading {
                                ProgressView("Читаем таблицу разделов…")
                            } else if let partitionError {
                                Label(partitionError, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            } else if partitions.isEmpty {
                                Text("Разделы не обнаружены или отсутствуют в таблице.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(partitions) { part in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(part.id).font(.subheadline.weight(.semibold))
                                        Text("Тип: \(part.content) · \(part.volumeName ?? "Без имени")")
                                        Text("Размер: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: part.size), countStyle: .file))")
                                        if let offset = part.offsetBytes, let block = part.blockSizeBytes {
                                            Text("Смещение: \(offset) байт · Блок: \(block) байт")
                                        } else {
                                            Text("Геометрия раздела не подтверждена")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        } else {
                            Text("Сначала выберите внешний физический накопитель.")
                                .foregroundStyle(.secondary)
                        }
                        Text("Тип раздела сообщается macOS. Он не подтверждает наличие RAW emuMMC.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                GroupBox("Диагностика emuMMC") {
                    VStack(alignment: .leading, spacing: 8) {
                        if selectedDiskID == nil {
                            Label("Выберите внешний накопитель.", systemImage: "waveform.path.ecg")
                        } else if emummcLoading {
                            ProgressView("Проверяем конфигурацию Hekate…")
                        } else if let report = emummcReport {
                            Label(report.title, systemImage: report.found ? "checkmark.shield" : "info.circle")
                            if let mode = report.mode {
                                Text("Режим: \(mode)")
                            }
                            if let status = report.status {
                                Text("Статус: \(status)")
                                    .fontWeight(.semibold)
                            }
                            ForEach(report.messages, id: \.self) { message in
                                Text("• \(message)")
                                    .font(.caption)
                            }
                        } else {
                            Text("Проверка пока не выполнялась.")
                        }
                        Text("Структура файлов не подтверждает целостность NAND или готовность к переносу.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                GroupBox("Инвентаризация microSD") {
                    VStack(alignment: .leading, spacing: 9) {
                        if selectedDiskID == nil {
                            Text("Выберите внешний накопитель.").foregroundStyle(.secondary)
                        } else if inventoryLoading {
                            ProgressView("Составляем манифест файлов…")
                        } else if let report = inventoryReport {
                            Label(report.summary,
                                  systemImage: report.complete ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(report.complete ? .green : .orange)
                            if let fileCount = report.fileCount,
                               let directoryCount = report.directoryCount,
                               let bytes = report.totalBytes {
                                Text("Файлы: \(fileCount) · Каталоги: \(directoryCount)")
                                Text("Размер файлов: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary))")
                            }
                            Text("Исключено служебных путей macOS: \(report.skippedPaths.count)")
                            ForEach(report.skippedPaths, id: \.self) { path in
                                Text("Исключено: \(path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(report.errors, id: \.self) { message in
                                Text("Ошибка: \(message)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            Text("Инвентаризация ещё не проводилась.")
                                .foregroundStyle(.secondary)
                        }
                        Text("Проверены метаданные, но не содержимое NAND. Исключения требуют отдельного подтверждения перед миграцией.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                    }
                    .padding(.top, 10)
                }

                GroupBox("Что дальше?") {
                    Label("На этой странице доступен только анализ. Для копирования или восстановления перейдите в соответствующую вкладку. Перед переносом на другую карту нужны отдельные проверки безопасности.",
                          systemImage: "lock.shield")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }

                Text("Обнаруженная структура не подтверждает целостность NAND или готовность к переносу.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if !hasScanned { await refresh() }
        }
    }

    @MainActor
    private func loadPartitions(for disk: SafeExternalDisk, requestID: UUID) async {
        let result = await Task.detached(priority: .userInitiated) {
            SafeExternalDiskScanner.inspectPartitions(on: disk)
        }.value
        guard partitionRequestID == requestID, selectedDiskID == disk.id else { return }
        partitionLoading = false
        partitions = result.partitions
        partitionError = result.error
        let report = await Task.detached(priority: .userInitiated) {
            SafeExternalDiskScanner.inspectEmuMMC(on: disk)
        }.value
        guard partitionRequestID == requestID, selectedDiskID == disk.id else { return }
        emummcLoading = false
        emummcReport = report
        let inventory = await Task.detached(priority: .userInitiated) {
            SafeExternalDiskScanner.inspectInventory(on: disk)
        }.value
        guard partitionRequestID == requestID, selectedDiskID == disk.id else { return }
        inventoryReport = inventory
        inventoryLoading = false
    }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        // Invalidate any prior partition task before rescanning detachable disks.
        partitionRequestID = UUID()
        selectedDiskID = nil
        partitions = []
        partitionError = nil
        partitionLoading = false
        emummcLoading = false
        emummcReport = nil
        inventoryReport = nil
        inventoryLoading = false
        loading = true
        scanError = nil
        let result = await Task.detached(priority: .userInitiated) {
            SafeExternalDiskScanner.scan()
        }.value
        disks = result.disks
        scanError = result.error
        hasScanned = true
        if !disks.contains(where: { $0.id == selectedDiskID }) {
            selectedDiskID = nil
        }
        loading = false
    }
}

private struct SafeExternalDisk: Identifiable, Sendable {
    let id: String
    let size: UInt64
    let partitionScheme: String
    let volumeName: String?
}

private struct DiskScanResult: Sendable {
    let disks: [SafeExternalDisk]
    let error: String?
}

private struct StoragePartitionRow: Identifiable, Sendable {
    let id: String
    let content: String
    let volumeName: String?
    let size: UInt64
    let offsetBytes: UInt64?
    let blockSizeBytes: UInt64?
}

private struct PartitionScanResult: Sendable {
    let partitions: [StoragePartitionRow]
    let error: String?
}

private struct EmuMMCScanResult: Sendable {
    let found: Bool
    let title: String
    let mode: String?
    let status: String?
    let messages: [String]
}

private struct StorageInventoryScanResult: Sendable {
    let complete: Bool
    let summary: String
    let fileCount: Int?
    let directoryCount: Int?
    let totalBytes: UInt64?
    let skippedPaths: [String]
    let errors: [String]
}

private enum SafeExternalDiskScanner {
    // User-facing names only. Keep StorageCore enum values unchanged.
    private static func displayMode(_ mode: SakuraEmuMMCDetector.Mode) -> String {
        switch mode {
        case .fileBased: return "Файловая emuMMC"
        case .partitionBased: return "Разделовая emuMMC (RAW)"
        case .disabled: return "emuMMC отключена"
        case .unknown: return "Тип emuMMC не определён"
        }
    }

    private static func displayStatus(_ status: SakuraStorageDiagnostic.Status) -> String {
        switch status {
        case .structurePresent: return "Структура обнаружена"
        case .incomplete: return "Неполная структура"
        case .invalid: return "Обнаружена ошибка"
        case .needsMoreInformation: return "Недостаточно данных"
        case .disabled: return "emuMMC отключена"
        }
    }

    static func scan() -> DiskScanResult {
        do {
            let candidates = try StorageInspector.externalDisks()
            var verified: [SafeExternalDisk] = []
            var rejectedCount = 0
            for disk in candidates {
                guard disk.id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
                    rejectedCount += 1
                    continue
                }
                let info = try readDiskInfo(id: disk.id)
                guard (info["DeviceIdentifier"] as? String) == disk.id,
                      StorageDiskSafety.assess(info) == .externalPhysicalCandidate,
                      let authoritativeSize = info["Size"] as? NSNumber,
                      authoritativeSize.uint64Value == disk.size else {
                    rejectedCount += 1
                    continue
                }
                let volumeName = (try? StoragePartitionInspector.partitions(for: disk.id))?
                    .compactMap { $0.volumeName }
                    .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                verified.append(SafeExternalDisk(
                    id: disk.id,
                    size: disk.size,
                    partitionScheme: disk.partitionScheme,
                    volumeName: volumeName
                ))
            }
            if rejectedCount > 0 {
                return DiskScanResult(disks: verified,
                                      error: "\(rejectedCount) накопитель(ей) не прошли проверку безопасности и скрыты.")
            }
            return DiskScanResult(disks: verified, error: nil)
        } catch {
            return DiskScanResult(disks: [], error: "Не удалось проверить диски: \(error.localizedDescription)")
        }
    }

    static func inspectPartitions(on disk: SafeExternalDisk) -> PartitionScanResult {
        do {
            // Re-check the same physical disk immediately before inspecting partitions.
            let info = try readDiskInfo(id: disk.id)
            guard (info["DeviceIdentifier"] as? String) == disk.id,
                  StorageDiskSafety.assess(info) == .externalPhysicalCandidate,
                  let size = info["Size"] as? NSNumber,
                  size.uint64Value == disk.size else {
                return PartitionScanResult(partitions: [], error: "Накопитель изменился или не прошёл повторную проверку")
            }
            let found = try StoragePartitionInspector.partitions(for: disk.id)
            let identifierPrefix = disk.id + "s"
            var result: [StoragePartitionRow] = []
            for part in found {
                guard part.id.hasPrefix(identifierPrefix),
                      part.id.dropFirst(identifierPrefix.count).allSatisfy({ $0.isNumber }),
                      !part.id.dropFirst(identifierPrefix.count).isEmpty else {
                    return PartitionScanResult(partitions: [], error: "Обнаружен неожиданный идентификатор раздела")
                }
                let geometry = try? StoragePartitionGeometryInspector.inspect(partition: part.id)
                result.append(StoragePartitionRow(
                    id: part.id, content: part.content, volumeName: part.volumeName,
                    size: part.size, offsetBytes: geometry?.offsetBytes,
                    blockSizeBytes: geometry?.blockSizeBytes
                ))
            }
            return PartitionScanResult(partitions: result, error: nil)
        } catch {
            return PartitionScanResult(partitions: [], error: "Не удалось получить разделы: \(error.localizedDescription)")
        }
    }

    static func inspectEmuMMC(on disk: SafeExternalDisk) -> EmuMMCScanResult {
        func info(_ text: String) -> EmuMMCScanResult {
            EmuMMCScanResult(found: false, title: text, mode: nil, status: nil, messages: [])
        }
        do {
            // Verify the whole disk again; disk identifiers can be reused after unplugging.
            let diskInfo = try readDiskInfo(id: disk.id)
            guard StorageDiskSafety.assess(diskInfo) == .externalPhysicalCandidate,
                  diskInfo["DeviceIdentifier"] as? String == disk.id,
                  let diskSize = diskInfo["Size"] as? NSNumber,
                  diskSize.uint64Value == disk.size else {
                return info("Накопитель изменился; обновите список")
            }
            let partitions = try StoragePartitionInspector.partitions(for: disk.id)
            var found: [(URL, SakuraEmuMMCDetector.Result)] = []
            for part in partitions {
                guard part.id.range(of: "^" + disk.id + "s[0-9]+$", options: .regularExpression) != nil else {
                    return info("Неподтверждённый идентификатор раздела")
                }
                let details = try readDiskInfo(id: part.id)
                guard details["DeviceIdentifier"] as? String == part.id,
                      details["ParentWholeDisk"] as? String == disk.id,
                      let mount = details["MountPoint"] as? String,
                      mount.hasPrefix("/Volumes/"),
                      mount != "/Volumes/" else { continue }
                let root = URL(fileURLWithPath: mount, isDirectory: true).standardizedFileURL
                let ini = root.appendingPathComponent("emuMMC/emummc.ini")
                guard FileManager.default.fileExists(atPath: ini.path) else { continue }
                // Re-check the partition-to-disk relationship immediately before reading.
                let second = try readDiskInfo(id: part.id)
                guard second["ParentWholeDisk"] as? String == disk.id,
                      second["MountPoint"] as? String == mount else {
                    return info("Раздел изменился во время проверки; обновите список")
                }
                let config = try SakuraEmuMMCDetector.inspect(fileAt: ini)
                found.append((root, config))
            }
            if found.isEmpty { return info("Конфигурация emuMMC на выбранном диске не обнаружена") }
            if found.count > 1 { return info("Найдено несколько конфигураций emuMMC; требуется ручная проверка") }
            let (root, config) = found[0]
            // RAW geometry/GPP size is not inferred. The diagnostic reports missing inputs.
            let report = SakuraStorageDiagnostic.inspect(configuration: config, sdRoot: root)
            var messages = report.messages
            if config.mode == .fileBased && report.status == .structurePresent {
                // Validate the relative Hekate path before inspecting file metadata.
                if let path = config.path {
                    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                    let rootResolved = root.standardizedFileURL.resolvingSymlinksInPath()
                    let directory = parts.reduce(rootResolved) {
                        $0.appendingPathComponent($1, isDirectory: true)
                    }.appendingPathComponent("eMMC", isDirectory: true)
                        .standardizedFileURL.resolvingSymlinksInPath()
                    let prefix = rootResolved.path.hasSuffix("/") ? rootResolved.path : rootResolved.path + "/"
                    if parts.count >= 2 && parts.first?.lowercased() == "emummc" &&
                       !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\\") }) &&
                       !path.hasPrefix("/") && directory.path.hasPrefix(prefix) {
                        let nand = SakuraNANDStructureValidator.inspect(eMMCDirectory: directory)
                        if nand.status.rawValue == "consistentMetadata" {
                            messages.append("Структура NAND: метаданные согласованы")
                        } else {
                            messages.append("Структура NAND: выявлены проблемы или недостаточно данных")
                        }
                        messages.append("Фрагменты GPP: \(nand.chunkCount)")
                        if let bytes = nand.gppBytes {
                            messages.append("Размер GPP: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary))")
                        }
                        if let bytes = nand.totalBytes {
                            messages.append("Общий размер emuMMC: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary))")
                        }
                        messages.append(contentsOf: nand.messages)
                        messages.append("Целостность содержимого NAND не проверена")
                    } else {
                        messages.append("Расширенная проверка NAND пропущена: небезопасный путь")
                    }
                } else {
                    messages.append("Расширенная проверка NAND пропущена: путь не задан")
                }
            }
            return EmuMMCScanResult(found: true, title: "Конфигурация Hekate обнаружена",
                                    mode: displayMode(config.mode), status: displayStatus(report.status),
                                    messages: messages)
        } catch {
            return info("Диагностика недоступна: \(error.localizedDescription)")
        }
    }

    // Read-only scan. The chosen whole disk and partition identity are checked again.
    // Never assumes a mounted partition belongs to a disk based on its name alone.
    static func inspectInventory(on disk: SafeExternalDisk) -> StorageInventoryScanResult {
        func failed(_ message: String) -> StorageInventoryScanResult {
            StorageInventoryScanResult(complete: false, summary: "Инвентаризация не завершена",
                                       fileCount: nil, directoryCount: nil, totalBytes: nil,
                                       skippedPaths: [], errors: [message])
        }
        do {
            let info = try readDiskInfo(id: disk.id)
            guard StorageDiskSafety.assess(info) == .externalPhysicalCandidate,
                  info["DeviceIdentifier"] as? String == disk.id,
                  (info["Size"] as? NSNumber)?.uint64Value == disk.size else {
                return failed("Физический накопитель изменился или не прошёл проверку")
            }
            let parts = try StoragePartitionInspector.partitions(for: disk.id)
            var roots: [(String, String)] = []
            for part in parts {
                guard part.id.range(of: "^" + disk.id + "s[0-9]+$", options: .regularExpression) != nil else {
                    return failed("Некорректный раздел выбранного диска")
                }
                let details = try readDiskInfo(id: part.id)
                guard details["DeviceIdentifier"] as? String == part.id,
                      details["ParentWholeDisk"] as? String == disk.id else {
                    return failed("Не удалось подтвердить принадлежность раздела физическому диску")
                }
                guard let mount = details["MountPoint"] as? String,
                      mount.hasPrefix("/Volumes/"), mount.count > "/Volumes/".count else { continue }
                let root = URL(fileURLWithPath: mount, isDirectory: true)
                if FileManager.default.fileExists(atPath: root.appendingPathComponent("emuMMC/emummc.ini").path) {
                    roots.append((part.id, mount))
                }
            }
            guard roots.count == 1, let chosen = roots.first else {
                return failed(roots.isEmpty ? "Не найден том с конфигурацией emuMMC" : "Обнаружено несколько томов с emuMMC")
            }
            let again = try readDiskInfo(id: chosen.0)
            guard again["DeviceIdentifier"] as? String == chosen.0,
                  again["ParentWholeDisk"] as? String == disk.id,
                  again["MountPoint"] as? String == chosen.1 else {
                return failed("Том изменился во время проверки")
            }
            let root = URL(fileURLWithPath: chosen.1, isDirectory: true)
            let policy = SakuraMigrationInventory.Policy.excludeKnownMacOSMetadata
            let inventory = SakuraMigrationInventory.inspect(root: root, policy: policy)
            let manifest = SakuraMigrationManifest.inspect(root: root, policy: policy)
            let matching = inventory.complete && manifest.complete &&
                UInt64(manifest.fileCount) == inventory.fileCount &&
                UInt64(manifest.directoryCount + 1) == inventory.directoryCount &&
                manifest.totalLogicalBytes == inventory.totalLogicalBytes &&
                manifest.skippedPaths == inventory.skippedPaths
            let errors = inventory.errors + manifest.errors +
                (matching ? [] : ["Inventory и Manifest не согласованы"])
            return StorageInventoryScanResult(
                complete: matching, summary: matching ? "Inventory и Manifest совпали" : "Инвентаризация не завершена",
                fileCount: matching ? manifest.fileCount : nil,
                directoryCount: matching ? manifest.directoryCount + 1 : nil,
                totalBytes: matching ? manifest.totalLogicalBytes : nil,
                skippedPaths: manifest.skippedPaths, errors: errors)
        } catch {
            return failed(error.localizedDescription)
        }
    }

    private static func readDiskInfo(id: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", id]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw NSError(domain: "SakuraStorage", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать сведения о \(id)"])
        }
        return info
    }
}
