import Foundation
import SwiftUI
import StorageCore
import Darwin
import CryptoKit

/// Storage Center shell. All disk operations in this view are metadata reads only.
/// Existing StorageCenterView remains the analysis engine and is not modified.
struct StorageCenterDashboard: View {
    private enum Page: String, CaseIterable, Identifiable {
        case overview = "Обзор"
        case analysis = "Анализ"
        case migration = "Перенос"
        case backup = "Копия"
        case restore = "Восстановить"
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

    private func storageText(_ key: String) -> String {
        NSLocalizedString(key, comment: "Sakura Storage Center")
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
    private struct CapacityScan: Sendable {
        let sourceID: String
        let destinationID: String
        let bytes: UInt64?
        let free: UInt64?
        let files: Int
        let excluded: Int
        let warning: String?
        let emummcStatus: String
        let emummcDetails: [String]
        let conflictStatus: String
        let conflictDetails: [String]
        let readiness: SakuraMigrationReadiness.Report?
    }

    // Explicit semantic levels, not inferred from message wording.
    private enum EventLevel {
        case success, error, warning, info

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    private struct LogEvent: Identifiable {
        let id = UUID()
        let time = Date()
        let message: String
        let level: EventLevel
    }

    @State private var page: Page = .overview
    @State private var disks: [DiskCard] = []
    @State private var selectedSource: String?
    @State private var selectedDestination: String?
    @State private var capacityScan: CapacityScan?
    @State private var capacityBusy = false
    @State private var diskRevision = 0

    // Fixed-path test transfer only. Never transfers a selected user disk.
    private enum TrialOutcome: Sendable {
        case completed, stopped, failed(String)
    }
    @State private var trialBusy = false
    @State private var trialCompleted = 0
    @State private var trialStatus = "Тестовый перенос ещё не запускался."
    @State private var trialLevel: EventLevel = .info
    @State private var trialTask: Task<TrialOutcome, Never>?
    @State private var showTrialConfirmation = false

    @State private var migrationScanBusy = false
    @State private var migrationScanStatus = "Полный перенос ещё не подготовлен."
    @State private var migrationScanLevel: EventLevel = .info

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
                    case .backup: SakuraBackupView()
                    case .restore: SakuraRestoreView()
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
        .onChange(of: selectedSource) { _, _ in
            diskRevision += 1
            capacityScan = nil
            Task { await inspectTransferCapacity() }
        }
        .onChange(of: selectedDestination) { _, _ in
            diskRevision += 1
            capacityScan = nil
            Task { await inspectTransferCapacity() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(storageText("storage.title"))
                .font(.system(size: 27, weight: .bold))
            Text(storageText("storage.subtitle"))
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
                    events.insert(LogEvent(message: String(format: storageText("storage.event.tab"), storageText("storage.tab.\(item.rawValue)")), level: .info), at: 0)
                } label: {
                    Label(storageText("storage.tab.\(item.rawValue)"), systemImage: item.icon)
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
                    Text(storageText("storage.connected")).font(.headline)
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
                Text(storageText("storage.quick_actions")).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 12), count: 4), spacing: 12) {
                    quickAction(storageText("storage.action.analysis"), description: storageText("storage.action.analysis_detail"), icon: "magnifyingglass", tint: .blue, enabled: true) {
                        page = .analysis
                    }
                    quickAction(storageText("storage.action.migrate"), description: storageText("storage.action.migrate_detail"), icon: "arrow.left.arrow.right", tint: .pink, enabled: true) { page = .migration }
                    quickAction(storageText("storage.action.backup"), description: storageText("storage.action.backup_detail"), icon: "externaldrive", tint: .green, enabled: true) { page = .backup }
                    quickAction(storageText("storage.action.restore"), description: storageText("storage.action.restore_detail"), icon: "arrow.counterclockwise", tint: .purple, enabled: true) { page = .restore }
                }
                GroupBox(storageText("storage.before")) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(storageText("storage.note.shutdown"), systemImage: "sdcard")
                        Label(storageText("storage.note.reader"), systemImage: "cable.connector")
                        Label(storageText("storage.note.operations"), systemImage: "lock.shield")
                        Label(storageText("storage.note.raw"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(storageText("storage.recent")).font(.headline)
                    Label(storageText("storage.note.history"), systemImage: "info.circle")
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
                        Text(storageText(selectedSource == disk.id ? "storage.disk.current" : "storage.disk.connected"))
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
                    Text(String(format: storageText("storage.disk.device"), disk.id))
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
                    Text(String(format: storageText("storage.disk.used"), sizeText(used)))
                    Spacer()
                    Text(String(format: storageText("storage.disk.free"), sizeText(free)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(storageText("storage.disk.capacityUnknown"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(storageText(selectedSource == disk.id ? "storage.disk.selected" : "storage.disk.choose")) {
                selectedSource = disk.id
                events.insert(LogEvent(message: String(format: storageText("storage.event.source"), disk.id), level: .info), at: 0)
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
    // The verified file-based migration view is the only visible transfer workflow.
    // Legacy diagnostic and synthetic-copy controls are preserved in git history.
    private var transferPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Перенос microSD", systemImage: "arrow.left.arrow.right")
                    .font(.title3.weight(.semibold))

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
                        Button("Проверить объём файлов · только чтение") {
                            Task { await inspectTransferCapacity() }
                        }
                        .disabled(busy || capacityBusy || selectedSource == nil ||
                                  selectedDestination == nil || selectedSource == selectedDestination)
                        if capacityBusy { ProgressView("Читаем инвентаризацию файлов…") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                if let sourceID = selectedSource,
                   let targetID = selectedDestination,
                   sourceID != targetID,
                   let source = disks.first(where: { $0.id == sourceID }),
                   let target = disks.first(where: { $0.id == targetID }) {
                    if capacityBusy {
                        ProgressView("Проверяем объём и целевую карту…")
                    } else if let check = capacityScan,
                              check.sourceID == sourceID,
                              check.destinationID == targetID,
                              let bytes = check.bytes,
                              let free = check.free,
                              check.warning == nil {
                        // Reserve 1 GiB, as in the transfer engine.
                        let reserve: UInt64 = 1_073_741_824
                        if bytes > free || free - bytes < reserve {
                            Label("Недостаточно места на целевой microSD. Данные: \(sizeText(bytes)), свободно: \(sizeText(free)). Нужно ещё минимум 1 ГиБ резерва.",
                                  systemImage: "externaldrive.badge.exclamationmark")
                                .foregroundStyle(.red)
                        } else {
                            SakuraPhysicalMigrationView(
                                sourceDiskID: sourceID,
                                targetDiskID: targetID,
                                sourceName: source.volumeName ?? sourceID,
                                targetName: target.volumeName ?? targetID
                            )
                            .id(sourceID + "|" + targetID)
                        }
                    } else {
                        Label("Сначала требуется успешная проверка объёма и накопителей. Копирование заблокировано.",
                              systemImage: "lock.shield")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("Выберите исходную и целевую microSD выше.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Подробная диагностика накопителей") {
                    VStack(alignment: .leading, spacing: 12) {
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

                if let result = capacityScan,
                   result.sourceID == selectedSource,
                   result.destinationID == selectedDestination {
                    GroupBox("Предварительная оценка вместимости") {
                        VStack(alignment: .leading, spacing: 7) {
                            if let bytes = result.bytes, let free = result.free {
                                Text("Файлов для переноса: \(result.files)")
                                Text("Логический объём файлов: \(sizeText(bytes))")
                                Text("Свободно на выбранном томе: \(sizeText(free))")
                                if bytes > free {
                                    Label("Недостаточно места · не хватает \(sizeText(bytes - free))",
                                          systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                } else {
                                    Label("Логический объём помещается без учёта резерва и накладных расходов файловой системы. Перенос не разрешён.",
                                          systemImage: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if result.excluded > 0 {
                                Text("Исключено служебных путей macOS: \(result.excluded). Требуется отдельная проверка.")
                                    .foregroundStyle(.orange)
                            }
                            if let warning = result.warning {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            Text("Только файловая оценка; RAW emuMMC, FAT32-кластеры, резерв и конфликты не подтверждены.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                }

                if let result = capacityScan,
                   result.sourceID == selectedSource,
                   result.destinationID == selectedDestination {
                    GroupBox("Структура emuMMC · только чтение") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(result.emummcStatus).fontWeight(.medium)
                                    .foregroundStyle(result.emummcStatus.contains("основные элементы найдены") ? Color.green : Color.orange)
                            ForEach(result.emummcDetails, id: \.self) { line in
                                Text(line).foregroundStyle(.secondary)
                            }
                            Text("Проверяется только структура файлов; здоровье NAND и загрузка консоли не подтверждаются.")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                    GroupBox("Конфликты назначения · только чтение") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(result.conflictStatus).fontWeight(.medium)
                                    .foregroundStyle(result.conflictStatus.contains("конфликтов не найдено") ? Color.green : Color.orange)
                            ForEach(result.conflictDetails, id: \.self) { line in
                                Text(line).foregroundStyle(.secondary)
                            }
                            Text("Сравнение по файловым манифестам. Исключения и изменения после сканирования требуют отдельной проверки.")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                }

                if let result = capacityScan,
                   result.sourceID == selectedSource,
                   result.destinationID == selectedDestination {
                    GroupBox("Итог предварительной проверки") {
                        VStack(alignment: .leading, spacing: 9) {
                            if let readiness = result.readiness {
                                Label(storageText(readiness.status == .blocked ? "Перенос заблокирован" : "Требуются дополнительные проверки"),
                                      systemImage: readiness.status == .blocked ?
                                      "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(readiness.status == .blocked ? Color.red : Color.orange)
                                    .fontWeight(.semibold)
                                ForEach(readiness.messages, id: \.self) { message in
                                    Text(message.contains("не хватает минимум") &&
     message.contains("байт без учёта резерва")
     ? "Недостаточно свободного места для переноса файлов."
     : message)
                                }
                                if let bytes = result.bytes, let free = result.free, bytes > free {
                                    Text("Не хватает минимум \(sizeText(bytes - free)) без учёта резерва и FAT32.")
                                }
                            } else {
                                Label("Готовность не определена: диагностика неполная",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                if let warning = result.warning { Text(warning) }
                            }
                            Text("Структура emuMMC: \(result.emummcStatus)")
                            Text("Конфликты назначения: \(result.conflictStatus)")
                            if result.excluded > 0 {
                                Text("Исключённые служебные пути: \(result.excluded). Необходимо проверить отдельно.")
                                    .foregroundStyle(.orange)
                            }
                            Text("Не подтверждены: резерв и накладные расходы FAT32, исключения, неизменность данных и повторная проверка дисков перед записью.")
                                .foregroundStyle(.secondary)
                            Text("Перенос выбранных физических дисков отключён при любом результате диагностики.")
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                }

                    }
                }

            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(storageText("storage.log"))
                .font(.headline)
                .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if events.isEmpty {
                        Text(storageText("storage.no_events"))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.time, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: event.level.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(event.level.color)
                                .padding(.top, 4)
                            Text(event.message)
                                .font(.caption)
                                .foregroundStyle(event.level.color)
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

    /// Freshly verifies selected physical disks and their single mounted volumes.
    /// No write operations; inspection only, never authorizes migration.
    @MainActor
    private func inspectTransferCapacity() async {
        guard !capacityBusy, !busy,
              let sourceID = selectedSource, let targetID = selectedDestination,
              sourceID != targetID,
              disks.contains(where: { $0.id == sourceID }),
              disks.contains(where: { $0.id == targetID }) else { return }
        capacityBusy = true
        capacityScan = nil
        let revision = diskRevision
        let result = await Task.detached(priority: .userInitiated) { () -> CapacityScan in
            func plist(_ id: String) throws -> [String: Any] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                p.arguments = ["info", "-plist", id]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0,
                      let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                    throw NSError(domain: "SakuraCapacity", code: 1)
                }
                return info
            }
            func mountedVolume(_ id: String) throws -> (URL, UInt64, SakuraDiskIdentityGuard.Snapshot) {
                let disk = try plist(id)
                guard disk["DeviceIdentifier"] as? String == id,
                      StorageDiskSafety.assess(disk) == .externalPhysicalCandidate else {
                    throw NSError(domain: "SakuraCapacity", code: 2)
                }
                let parts = try StoragePartitionInspector.partitions(for: id)
                var matches: [(URL, UInt64, SakuraDiskIdentityGuard.Snapshot)] = []
                for part in parts where part.id.range(of: "^" + id + "s[0-9]+$", options: .regularExpression) != nil {
                    let p = try plist(part.id)
                    guard p["DeviceIdentifier"] as? String == part.id,
                          p["ParentWholeDisk"] as? String == id,
                          let mount = p["MountPoint"] as? String,
                          mount.hasPrefix("/Volumes/"),
                          let free = p["FreeSpace"] as? NSNumber else { continue }
                    let url = URL(fileURLWithPath: mount, isDirectory: true)
                    guard url.path == mount,
                          FileManager.default.fileExists(atPath: mount) else { continue }
                    // No identity metadata means the scan must fail closed.
                    let identity = try SakuraDiskIdentityGuard.capture(disk: disk, partition: p)
                    matches.append((url, free.uint64Value, identity))
                }
                guard matches.count == 1 else {
                    throw NSError(domain: "SakuraCapacity", code: 3)
                }
                return matches[0]
            }
            do {
                let (sourceURL, _, sourceBefore) = try mountedVolume(sourceID)
                let (targetURL, free, targetBefore) = try mountedVolume(targetID)
                let report = SakuraMigrationInventory.inspect(root: sourceURL,
                    policy: .excludeKnownMacOSMetadata)

                // Independent structural check; no NAND contents are read.
                let configURL = sourceURL.appendingPathComponent("emuMMC/emummc.ini")
                let emummcStatus: String
                var emummcDetails: [String] = []
                if let configuration = try? SakuraEmuMMCDetector.inspect(fileAt: configURL) {
                    switch configuration.mode {
                    case .fileBased:
                        let structure = SakuraStorageValidator.inspectFileBased(sdRoot: sourceURL,
                            configuration: configuration)
                        emummcStatus = structure.status == .structurePresent
                            ? "Файловая emuMMC: основные элементы найдены"
                            : "Файловая emuMMC: структура не подтверждена (\(structure.status.rawValue))"
                        emummcDetails = structure.messages
                    case .partitionBased:
                        emummcStatus = "Разделовая emuMMC: файловая проверка неприменима"
                        emummcDetails = ["Расположение RAW-раздела и его содержимое не проверялись."]
                    case .disabled:
                        emummcStatus = "emuMMC отключена в конфигурации"
                    case .unknown:
                        emummcStatus = "Режим emuMMC не определён"
                    }
                    emummcDetails.append(contentsOf: configuration.warnings)
                } else {
                    emummcStatus = "emummc.ini не прочитан: режим emuMMC неизвестен"
                    emummcDetails = ["Отсутствие конфигурации не означает отсутствия emuMMC."]
                }

                // These are separate metadata-only scans of both mounted trees.
                // Neither manifest includes a content checksum or disk snapshot.
                let sourceManifest = SakuraMigrationManifest.inspect(root: sourceURL,
                    policy: .excludeKnownMacOSMetadata)
                let targetManifest = SakuraMigrationManifest.inspect(root: targetURL,
                    policy: .excludeKnownMacOSMetadata)
                let conflicts = SakuraMigrationConflictInspector.assess(
                    source: sourceManifest, target: targetManifest)
                let conflictStatus: String
                switch conflicts.status {
                case .blocked:
                    conflictStatus = "Обнаружены конфликты или ограничения FAT32: \(conflicts.conflicts.count)"
                case .needsMoreInformation:
                    conflictStatus = "Конфликты не удалось надёжно оценить"
                case .noDetectedConflicts:
                    conflictStatus = "В проверенных манифестах конфликтов не найдено"
                }
                var conflictDetails = Array(conflicts.conflicts.prefix(5))
                if conflicts.conflicts.count > 5 {
                    conflictDetails.append("И ещё \(conflicts.conflicts.count - 5) конфликтов")
                }
                conflictDetails.append(contentsOf: conflicts.messages)
                let excludedCount = sourceManifest.skippedPaths.count + targetManifest.skippedPaths.count
                if excludedCount > 0 {
                    conflictDetails.append("Исключено путей из двух манифестов: \(excludedCount). Требуется проверка.")
                }
                // Assessment uses only facts established by this read-only scan.
                // Reserve remains unknown, and excluded paths are not automatically approved.
                let structureConfirmed = emummcStatus == "Файловая emuMMC: основные элементы найдены"
                let conflictsAbsent: Bool?
                switch conflicts.status {
                case .noDetectedConflicts: conflictsAbsent = true
                case .blocked: conflictsAbsent = false
                case .needsMoreInformation: conflictsAbsent = nil
                }
                let plannerInput = SakuraMigrationPlanner.Input(
                    sourceDiskID: sourceID,
                    targetDiskID: targetID,
                    sourceVerifiedExternalPhysical: true,
                    targetVerifiedExternalPhysical: true,
                    sourceAndTargetVolumesVerified: true,
                    sourceFileBasedStructureVerified: structureConfirmed,
                    requiredBytes: report.complete ? report.totalLogicalBytes : nil,
                    targetAvailableBytes: free,
                    reserveBytes: nil,
                    targetConflictsAbsent: conflictsAbsent)
                let readiness = SakuraMigrationReadiness.assess(.init(
                    planner: plannerInput,
                    excludedPathsReviewed: report.skippedPaths.isEmpty &&
                        sourceManifest.skippedPaths.isEmpty && targetManifest.skippedPaths.isEmpty,
                    inventoryComplete: report.complete && sourceManifest.complete && targetManifest.complete))

                // Detect a changed/replaced or remounted disk during this scan.
                // Equal metadata is not proof of physical identity and never permits writing.
                let (sourceAgain, _, sourceAfter) = try mountedVolume(sourceID)
                let (targetAgain, _, targetAfter) = try mountedVolume(targetID)
                guard sourceAgain.path == sourceURL.path,
                      targetAgain.path == targetURL.path,
                      SakuraDiskIdentityGuard.assess(previous: sourceBefore, current: sourceAfter) == .metadataConsistentIdentityUnproven,
                      SakuraDiskIdentityGuard.assess(previous: targetBefore, current: targetAfter) == .metadataConsistentIdentityUnproven else {
                    throw NSError(domain: "SakuraIdentity", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "Метаданные накопителя изменились во время анализа. Повторите диагностику."])
                }
                return CapacityScan(sourceID: sourceID, destinationID: targetID,
                    bytes: report.complete ? report.totalLogicalBytes : nil,
                    free: free, files: Int(report.fileCount), excluded: report.skippedPaths.count,
                    warning: report.complete ? nil : "Инвентаризация неполная: перенос заблокирован",
                    emummcStatus: emummcStatus, emummcDetails: emummcDetails,
                    conflictStatus: conflictStatus, conflictDetails: conflictDetails,
                    readiness: readiness)
            } catch {
                return CapacityScan(sourceID: sourceID, destinationID: targetID,
                    bytes: nil, free: nil, files: 0, excluded: 0,
                    warning: "Не удалось независимо подтвердить диски и тома: \(error.localizedDescription)",
                    emummcStatus: "Проверка структуры не выполнена", emummcDetails: [],
                    conflictStatus: "Проверка конфликтов не выполнена", conflictDetails: [],
                    readiness: nil)
            }
        }.value
        capacityBusy = false
        guard revision == diskRevision,
              selectedSource == result.sourceID,
              selectedDestination == result.destinationID else { return }
        capacityScan = result
        events.insert(LogEvent(message: "Проверка вместимости: \(result.warning ?? "оценка файлов завершена")", level: result.warning != nil ? .warning : .info), at: 0)
    }

    // Read-only preparation of the actual Nintendo file manifest.
    @MainActor
    private func prepareFullMigration() async {
        guard !migrationScanBusy else { return }

        migrationScanBusy = true
        migrationScanLevel = .info
        migrationScanStatus = "Проверяем файловую структуру NINTENDO…"

        let result = await Task.detached(priority: .userInitiated) {
            let root = URL(fileURLWithPath: "/Volumes/NINTENDO", isDirectory: true)
            let manifest = SakuraMigrationManifest.inspect(
                root: root,
                policy: .excludeKnownMacOSMetadata
            )

            guard manifest.complete, let bytes = manifest.totalLogicalBytes else {
                return (
                    false,
                    "Манифест неполный: " + manifest.errors.prefix(3).joined(separator: "; ")
                )
            }

            do {
                let folders = manifest.entries
                    .filter { $0.kind == .directory }
                    .map(\.relativePath)
                let files = manifest.entries
                    .filter { $0.kind == .file }
                    .map(\.relativePath)

                _ = try SakuraDestinationDirectoryPlan.make(
                    directories: folders, files: files
                )

                let description = ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: bytes),
                    countStyle: .file
                )

                return (
                    true,
                    "Манифест: \(files.count) файлов, \(description). " +
                    "Исключений macOS: \(manifest.skippedPaths.count). " +
                    "Перенос ожидает подтверждения."
                )
            } catch {
                return (false, "Проверка путей: \(error)")
            }
        }.value

        migrationScanBusy = false
        migrationScanStatus = result.1
        migrationScanLevel = result.0 ? .success : .error
        events.insert(
            LogEvent(message: result.1, level: migrationScanLevel),
            at: 0
        )
    }

    // Test-only fixed-path transfer; never use the selected disk values for writes.
    @MainActor
    private func startTrialTransfer() {
        guard !trialBusy else { return }
        trialBusy = true
        trialCompleted = 0
        trialStatus = "Проверяем тестовый том…"
        trialLevel = .info
        let job = Task.detached(priority: .userInitiated) { () -> TrialOutcome in
            let destination = "/Volumes/SAKURATEST/SakuraStorageTest/SakuraPreparerFAT32Test/Nintendo/save"
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/SakuraSwitch-StorageCenter/.storage-tests/sakura-verified-copy-source.bin")
            let names = ["sakura-ui-test-01.bin", "sakura-ui-test-02.bin"]
            func validate() throws {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                process.arguments = ["info", "-plist", "disk3s2"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      info["DeviceIdentifier"] as? String == "disk3s2",
                      info["ParentWholeDisk"] as? String == "disk3",
                      info["MountPoint"] as? String == "/Volumes/SAKURATEST",
                      info["FilesystemName"] as? String == "MS-DOS FAT32",
                      (info["VolumeUUID"] as? String)?.uppercased() == "3AA79100-9818-33B6-AEDC-19D2A8D50019"
                else { throw NSError(domain: "SakuraTrial", code: 1, userInfo: [NSLocalizedDescriptionKey: "Тестовый FAT32-том не подтверждён"]) }
                var fs = statfs()
                guard statfs(destination, &fs) == 0 else {
                    throw NSError(domain: "SakuraTrial", code: 2, userInfo: [NSLocalizedDescriptionKey: "Каталог тестового назначения недоступен"])
                }
                let device = withUnsafeBytes(of: fs.f_mntfromname) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                let mount = withUnsafeBytes(of: fs.f_mntonname) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                guard device == "/dev/disk3s2", mount == "/Volumes/SAKURATEST" else {
                    throw NSError(domain: "SakuraTrial", code: 3, userInfo: [NSLocalizedDescriptionKey: "Подмена точки монтирования"])
                }
            }
            do {
                let data = try Data(contentsOf: file)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard data.count == 135168,
                      digest == "56f11bf1b3189a1c7730049b58405566ca7be547f9dbaf01c6c86e5b75e1fdb0" else {
                    throw NSError(domain: "SakuraTrial", code: 4, userInfo: [NSLocalizedDescriptionKey: "Искусственный источник не совпадает с проверенным образцом"])
                }
                try validate()
                for (index, name) in names.enumerated() {
                    if Task.isCancelled { return .stopped }
                    try validate()
                    let receipt = try SakuraVerifiedCopy.copy(source: file,
                        toDirectory: URL(fileURLWithPath: destination, isDirectory: true), name: name)
                    guard receipt.bytes == 135168, receipt.sha256 == digest else {
                        throw NSError(domain: "SakuraTrial", code: 5, userInfo: [NSLocalizedDescriptionKey: "Не совпала контрольная сумма копии"])
                    }
                    await MainActor.run {
                        trialCompleted = index + 1
                        trialStatus = "Файл \(index + 1) из 2 проверен (SHA-256)."
                        trialLevel = .success
                    }
                }
                return .completed
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        trialTask = job
        Task { @MainActor in
            let outcome = await job.value
            trialBusy = false
            trialTask = nil
            switch outcome {
            case .completed:
                trialStatus = "Тестовый перенос завершён: оба файла проверены."
                trialLevel = .success
                events.insert(LogEvent(message: "Тестовый перенос: 2 искусственных файла проверены", level: .success), at: 0)
            case .stopped:
                trialStatus = "Остановлено между файлами. Уже записанные тестовые файлы остаются на месте."
                trialLevel = .warning
                events.insert(LogEvent(message: "Тестовый перенос остановлен", level: .warning), at: 0)
            case .failed(let message):
                if message == "alreadyExists" {
                    trialStatus = "Тестовые файлы уже существуют. Повторная запись запрещена."
                    trialLevel = .warning
                    events.insert(LogEvent(message: trialStatus, level: .warning), at: 0)
                } else {
                    trialStatus = "Ошибка тестового переноса: \(message)"
                    trialLevel = .error
                    events.insert(LogEvent(message: trialStatus, level: .error), at: 0)
                }
            }
        }
    }

    @MainActor
    private func refreshDisks() async {
        guard !busy else { return }
        busy = true
        diskRevision += 1
        capacityScan = nil
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
        capacityScan = nil
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
            ?? String(format: storageText("storage.event.drives"), result.disks.count)
        events.insert(LogEvent(message: text, level: result.error != nil ? .error : .info), at: 0)
    }
}
