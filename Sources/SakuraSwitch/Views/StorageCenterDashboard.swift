import Foundation
import SwiftUI
import StorageCore

/// Storage Center shell. All disk operations in this view are metadata reads only.
/// Existing StorageCenterView remains the analysis engine and is not modified.
struct StorageCenterDashboard: View {
    private enum Page: String, CaseIterable, Identifiable {
        case overview = "Обзор"
        case analysis = "Анализ"
        case migration = "Перенос"
        case backup = "Резервирование"
        case restore = "Восстановление"
        var id: Self { self }
        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .analysis: return "magnifyingglass.circle"
            case .migration: return "arrow.left.arrow.right"
            case .backup: return "externaldrive.badge.plus"
            case .restore: return "arrow.counterclockwise"
            }
        }
    }

    private struct DiskCard: Identifiable, Sendable {
        let id: String
        let size: UInt64
        let scheme: String
        let volumeName: String?
        let filesystem: String?
        let volumeTotalBytes: UInt64?
        let volumeFreeBytes: UInt64?
    }
    private struct Scan: Sendable {
        let disks: [DiskCard]
        let error: String?
    }
    private struct LogEvent: Identifiable {
        let id = UUID()
        let time = Date()
        let message: String
        let isWarning: Bool
    }

    @State private var page: Page = .overview
    @State private var disks: [DiskCard] = []
    @State private var selectedSource: String?
    @State private var selectedDestination: String?
    @State private var events: [LogEvent] = []
    @State private var busy = false
    @State private var scanned = false
    @State private var error: String?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header
                tabs
                Divider()
                Group {
                    switch page {
                    case .overview: overview
                    case .analysis: StorageCenterView()
                    case .migration: transferPreview
                    case .backup: unavailable("Резервирование", "Создание образа и запись резервных копий пока недоступны.")
                    case .restore: unavailable("Восстановление", "Запись образов на накопители пока недоступна.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

            journal
                .frame(minWidth: 260, idealWidth: 310, maxWidth: 365, maxHeight: .infinity)
        }
        .task {
            if !scanned { await refreshDisks() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Хранилище")
                .font(.system(size: 27, weight: .bold))
            Text("Резервирование, анализ и перенос microSD для Nintendo Switch")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 15)
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            ForEach(Page.allCases) { item in
                Button {
                    page = item
                    events.insert(LogEvent(message: "Открыта вкладка «\(item.rawValue)»", isWarning: false), at: 0)
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(page == item ? Color.accentColor.opacity(0.23) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Подключённые устройства").font(.headline)
                    Spacer()
                    Button { Task { await refreshDisks() } } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .disabled(busy)
                }
                if busy { ProgressView("Проверяем внешние накопители…") }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if disks.isEmpty && scanned && error == nil {
                    Label("Внешние физические накопители не обнаружены.", systemImage: "externaldrive")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(minimum: 220), spacing: 14), GridItem(.flexible(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(disks) { disk in
                        diskView(disk)
                    }
                    if disks.count < 2 {
                        destinationPlaceholder
                    }
                }
                Text("Быстрые действия").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 12), count: 4), spacing: 12) {
                    quickAction("Анализ карты", description: "Разделы, emuMMC и файлы", icon: "magnifyingglass", tint: .blue, enabled: true) {
                        page = .analysis
                    }
                    quickAction("Перенос карты", description: "Предпросмотр без записи", icon: "arrow.left.arrow.right", tint: .pink, enabled: true) { page = .migration }
                    quickAction("Резервирование", description: "Пока недоступно", icon: "externaldrive", tint: .green, enabled: false) {}
                    quickAction("Восстановление", description: "Пока недоступно", icon: "arrow.counterclockwise", tint: .purple, enabled: false) {}
                }
                GroupBox("О Sakura Storage Center") {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Проверка внешних дисков и файловой emuMMC выполняется только для чтения.", systemImage: "lock.shield")
                        Label("Для работы с RAW emuMMC требуется карта в кардридере Mac; MTP не даёт доступа к физическим разделам.", systemImage: "info.circle")
                            .foregroundStyle(.orange)
                        Text("Операции записи, переноса, создания и восстановления образов отключены.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Последние операции").font(.headline)
                    Label("Операций переноса или резервирования пока нет", systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70)
                }
            }
            .padding(20)
        }
    }

    private func diskView(_ disk: DiskCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sdcard.fill")
                    .font(.system(size: 43))
                    .foregroundStyle(.blue)
                    .frame(width: 59)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text(selectedSource == disk.id ? "Текущая карта (источник)" : "Подключённая microSD")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(disk.volumeName ?? disk.id)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(sizeText(disk.size))
                        Text(disk.filesystem ?? disk.scheme)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Устройство: \(disk.id)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            if let total = disk.volumeTotalBytes, let free = disk.volumeFreeBytes,
               total > 0, free <= total {
                let used = total - free
                ProgressView(value: Double(used), total: Double(total))
                    .tint(.blue)
                HStack {
                    Text("Занято: \(sizeText(used))")
                    Spacer()
                    Text("Свободно: \(sizeText(free))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Заполнение тома: сведения не подтверждены")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(selectedSource == disk.id ? "Выбран как источник" : "Выбрать источник") {
                selectedSource = disk.id
                events.insert(LogEvent(message: "Выбран источник \(disk.id). Данные не изменены.", isWarning: false), at: 0)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(selectedSource == disk.id)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
        .background(Color.secondary.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.17)))
    }

    // Selection-only preview. NEVER invokes write/format/transfer APIs.
    private var transferPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Предпросмотр переноса", systemImage: "arrow.left.arrow.right")
                    .font(.title3.weight(.semibold))
                Label("Только чтение. Копирование, форматирование и запись на диск отключены.",
                      systemImage: "lock.shield")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GroupBox("Выбор физических накопителей") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Источник", selection: $selectedSource) {
                            Text("Не выбран").tag(Optional<String>.none)
                            ForEach(disks) { disk in
                                Text("\(disk.volumeName ?? disk.id) (\(disk.id))")
                                    .tag(Optional(disk.id))
                            }
                        }
                        Picker("Назначение", selection: $selectedDestination) {
                            Text("Не выбрано").tag(Optional<String>.none)
                            ForEach(disks.filter { $0.id != selectedSource }) { disk in
                                Text("\(disk.volumeName ?? disk.id) (\(disk.id))")
                                    .tag(Optional(disk.id))
                            }
                        }
                        Button("Обновить накопители") { Task { await refreshDisks() } }
                            .disabled(busy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                if let source = disks.first(where: { $0.id == selectedSource }) {
                    transferDiskSummary("Источник · только чтение", disk: source)
                } else {
                    Label("Выберите исходный физический диск.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                if let destination = disks.first(where: { $0.id == selectedDestination }),
                   destination.id != selectedSource {
                    transferDiskSummary("Назначение · только просмотр", disk: destination)
                    if destination.filesystem != "MS-DOS FAT32" {
                        Label("Файловая система назначения не подтверждена как FAT32.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("Выберите другой физический диск в качестве назначения.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Безопасность") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Источник и назначение должны быть разными физическими дисками.",
                              systemImage: "checkmark.shield")
                        Label("Сведения о томе предварительные: это первый распознанный смонтированный раздел.",
                              systemImage: "info.circle")
                        Label("Для переноса нужны отдельные проверки структуры, конфликтов, места и повторная идентификация дисков.",
                              systemImage: "exclamationmark.triangle")
                        Text("Запуск переноса пока недоступен независимо от выбранных дисков.")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func transferDiskSummary(_ heading: String, disk: DiskCard) -> some View {
        GroupBox(heading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(disk.volumeName ?? "Без имени") · \(disk.id)")
                    .font(.subheadline.weight(.medium))
                Text("Физическая ёмкость: \(sizeText(disk.size))")
                Text("Файловая система: \(disk.filesystem ?? "не установлена")")
                if let total = disk.volumeTotalBytes, let free = disk.volumeFreeBytes {
                    Text("Том: \(sizeText(total)) · свободно \(sizeText(free))")
                } else {
                    Text("Свободное место не подтверждено")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
        }
    }

    private var destinationPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sdcard")
                    .font(.system(size: 43))
                    .foregroundStyle(.secondary)
                    .frame(width: 59)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Новая карта (назначение)")
                        .font(.subheadline.weight(.semibold))
                    Text("Не выбрана")
                        .font(.system(size: 17, weight: .medium))
                    Text("Подключите вторую microSD")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Label("Операции записи отключены", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Назначение пока недоступно") {}
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(true)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.17), style: StrokeStyle(dash: [5, 4])))
    }

    private func quickAction(_ title: String, description: String, icon: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .padding(12)
            .background(tint.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func unavailable(_ title: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "lock.shield")
                .font(.title3.weight(.semibold))
            Text(explanation).foregroundStyle(.secondary)
            Button("Открыть анализ") { page = .analysis }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Журнал событий")
                .font(.headline)
                .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if events.isEmpty {
                        Text("Событий пока нет")
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.time, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(event.isWarning ? Color.orange : Color.blue)
                                .padding(.top, 4)
                            Text(event.message)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color.secondary.opacity(0.04))
    }

    private func sizeText(_ size: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)
    }

    @MainActor
    private func refreshDisks() async {
        guard !busy else { return }
        busy = true
        error = nil
        let result = await Task.detached(priority: .userInitiated) { () -> Scan in
            do {
                let candidates = try StorageInspector.externalDisks()
                var accepted: [DiskCard] = []
                for disk in candidates {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    process.arguments = ["info", "-plist", disk.id]
                    let output = Pipe()
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                          info["DeviceIdentifier"] as? String == disk.id,
                          StorageDiskSafety.assess(info) == .externalPhysicalCandidate,
                          let reportedSize = info["Size"] as? NSNumber,
                          reportedSize.uint64Value == disk.size else { continue }
                    var volumeName: String?
                    var filesystem: String?
                    var volumeTotalBytes: UInt64?
                    var volumeFreeBytes: UInt64?
                    let partitions = try StoragePartitionInspector.partitions(for: disk.id)
                    for part in partitions where part.id.range(of: "^" + disk.id + "s[0-9]+$", options: .regularExpression) != nil {
                        let partProcess = Process()
                        partProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                        partProcess.arguments = ["info", "-plist", part.id]
                        let partOutput = Pipe()
                        partProcess.standardOutput = partOutput
                        partProcess.standardError = FileHandle.nullDevice
                        try partProcess.run()
                        let partData = partOutput.fileHandleForReading.readDataToEndOfFile()
                        partProcess.waitUntilExit()
                        guard partProcess.terminationStatus == 0,
                              let p = try? PropertyListSerialization.propertyList(from: partData, format: nil) as? [String: Any],
                              p["DeviceIdentifier"] as? String == part.id,
                              p["ParentWholeDisk"] as? String == disk.id,
                              let mount = p["MountPoint"] as? String,
                              mount.hasPrefix("/Volumes/"),
                              let total = p["TotalSize"] as? NSNumber,
                              let free = p["FreeSpace"] as? NSNumber,
                              total.uint64Value > 0,
                              free.uint64Value <= total.uint64Value else { continue }
                        volumeName = p["VolumeName"] as? String
                        filesystem = p["FilesystemName"] as? String
                        volumeTotalBytes = total.uint64Value
                        volumeFreeBytes = free.uint64Value
                        break
                    }
                    accepted.append(DiskCard(id: disk.id, size: disk.size,
                                             scheme: disk.partitionScheme,
                                             volumeName: volumeName, filesystem: filesystem,
                                             volumeTotalBytes: volumeTotalBytes,
                                             volumeFreeBytes: volumeFreeBytes))
                }
                return Scan(disks: accepted, error: nil)
            } catch {
                return Scan(disks: [], error: error.localizedDescription)
            }
        }.value
        disks = result.disks
        error = result.error
        scanned = true
        busy = false
        if let selectedSource, !disks.contains(where: { $0.id == selectedSource }) {
            self.selectedSource = nil
        }
        if let selectedDestination, !disks.contains(where: { $0.id == selectedDestination }) {
            self.selectedDestination = nil
        }
        let text = result.error.map { "Ошибка поиска накопителей: \($0)" }
            ?? "Проверено внешних физических накопителей: \(result.disks.count)"
        events.insert(LogEvent(message: text, isWarning: result.error != nil), at: 0)
    }
}
