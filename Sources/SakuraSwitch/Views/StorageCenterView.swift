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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sakura Storage Center")
                        .font(.title2.weight(.semibold))
                    Text("Диагностика microSD и emuMMC")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Безопасный режим") {
                    Label("Только чтение. Запись, форматирование и перенос данных отключены.",
                          systemImage: "lock.shield")
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
                                    partitionLoading = true
                                    let requestID = partitionRequestID
                                    Task { await loadPartitions(for: disk, requestID: requestID) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "externaldrive")
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(disk.id)
                                                .fontWeight(.semibold)
                                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: disk.size), countStyle: .file)) · \(disk.partitionScheme)")
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
                        if let selectedDiskID, disks.contains(where: { $0.id == selectedDiskID }) {
                            Label("Выбран \(selectedDiskID). Проверка разделов и emuMMC будет подключена следующим этапом.",
                                  systemImage: "externaldrive.badge.questionmark")
                        } else {
                            Label("Выберите внешний накопитель для дальнейшей диагностики.",
                                  systemImage: "waveform.path.ecg")
                        }
                        Text("Никакая проверка целостности NAND сейчас не выполняется.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

private enum SafeExternalDiskScanner {
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
                verified.append(SafeExternalDisk(id: disk.id, size: disk.size,
                                                 partitionScheme: disk.partitionScheme))
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
