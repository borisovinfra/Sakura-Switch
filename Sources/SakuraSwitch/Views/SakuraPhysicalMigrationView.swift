import Foundation
import SwiftUI
import StorageCore

@MainActor
enum SakuraMigrationActivity {
    static var active = false
}

private enum SakuraPhysicalMigrationPhase: Equatable {
    case idle, preparing, ready, running, verifying, completed, stopped, failed

    var title: String {
        switch self {
        case .idle: return NSLocalizedString("Ожидание", comment: "Migration state")
        case .preparing: return NSLocalizedString("Подготовка", comment: "Migration state")
        case .ready: return NSLocalizedString("Готово к переносу", comment: "Migration state")
        case .running: return NSLocalizedString("Копирование файлов", comment: "Migration state")
        case .verifying: return NSLocalizedString("Финальная проверка SHA-256", comment: "Migration state")
        case .completed: return NSLocalizedString("ГОТОВО", comment: "Migration state")
        case .stopped: return NSLocalizedString("ОСТАНОВЛЕНО", comment: "Migration state")
        case .failed: return NSLocalizedString("ОШИБКА", comment: "Migration state")
        }
    }

    var symbol: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .stopped: return "pause.circle.fill"
        case .running, .verifying, .preparing: return "arrow.triangle.2.circlepath"
        case .idle, .ready: return "externaldrive"
        }
    }

    var color: Color {
        switch self {
        case .completed: return .green
        case .failed: return .red
        case .stopped: return .orange
        case .running, .verifying, .preparing: return .blue
        case .idle, .ready: return .secondary
        }
    }
}

@MainActor
final class SakuraPhysicalMigrationDisplayState: ObservableObject {
    @Published var running = false
    @Published fileprivate var phase: SakuraPhysicalMigrationPhase = .idle
    var runID = UUID()
    @Published var finalVerifiedFiles = 0
    @Published var finalTotalFiles = 0
    @Published var verifiedFiles = 0
    @Published var totalFiles = 0
    @Published var verifiedBytes: UInt64 = 0
    @Published var totalBytes: UInt64 = 0
    @Published var status = NSLocalizedString("Ожидание проверки исходной microSD.", comment: "Migration status")
    var job: Task<Void, Never>?
}

struct SakuraPhysicalMigrationView: View {
    let sourceDiskID: String
    let targetDiskID: String
    let sourceName: String
    let targetName: String
    @StateObject private var transfer = SakuraPhysicalMigrationDisplayState()

    @State private var fileCount = 0
    @State private var requiredBytes: UInt64 = 0
    @State private var excludedPaths: [String] = []
    @State private var scanning = false
    @State private var prepared = false
    @State private var approved = false
    @State private var confirmStart = false
    @State private var confirmStop = false

    private var fileFraction: Double {
        guard transfer.totalFiles > 0 else { return 0 }
        return min(1, Double(transfer.verifiedFiles) / Double(transfer.totalFiles))
    }

    private var fraction: Double {
        guard transfer.totalBytes > 0 else { return 0 }
        return min(1, Double(transfer.verifiedBytes) /
                   Double(transfer.totalBytes))
    }

    private var confirmationText: String {
        "Источник: \(sourceName) (\(sourceDiskID)) — только чтение. " +
        "Назначение: \(targetName) (\(targetDiskID)). " +
        "Новые файлы будут записаны на целевую карту; существующие не перезаписываются."
    }

    private var transferBox: some View {
        GroupBox("Перенос выбранных microSD · SD File") {
            VStack(alignment: .leading, spacing: 12) {
                sourceSummary
                operationStatus
                if prepared { manifestDetails }
                if transfer.running || transfer.totalFiles > 0 { transferProgress }
                if transfer.phase == .verifying {
                    finalVerificationProgress
                }

                transferControls
                if scanning { ProgressView("Сканирование исходной карты…") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    var body: some View {
        transferBox
            .confirmationDialog(
                "Остановить незавершённый перенос?",
                isPresented: $confirmStop
            ) {
                Button("Да, остановить", role: .destructive) {
                    transfer.status = NSLocalizedString("Ожидаем безопасной остановки…", comment: "Migration status")
                    transfer.job?.cancel()
                }
                Button("Продолжить проверку", role: .cancel) {}
            } message: {
                Text(stopConfirmationMessage)
            }
            .confirmationDialog(
                "Подтвердить запись на выбранную microSD?",
                isPresented: $confirmStart
            ) {
                Button("Начать копирование файлов") { start() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(confirmationText)
            }
    }

    private var stopConfirmationMessage: String {
        transfer.phase == .verifying
            ? "Финальная проверка SHA-256 ещё выполняется. Прерывание не подтвердит целостность переноса. Не извлекайте накопители до завершения операции."
            : "Перенос ещё выполняется. Уже подтверждённые файлы сохранятся, но операция останется незавершённой."
    }

    @ViewBuilder private var sourceSummary: some View {
HStack {
    Label(sourceName, systemImage: "sdcard")
    Image(systemName: "arrow.right")
    Label(targetName, systemImage: "externaldrive")
}
.font(.subheadline)

Text("Источник: только чтение. Назначение: выбранная внешняя FAT32 microSD.")
    .font(.caption)
    .foregroundStyle(.secondary)
    }

    private var operationStatus: some View {
HStack(alignment: .top, spacing: 14) {
    Image(systemName: transfer.phase.symbol)
        .font(.system(size: 32))
        .foregroundStyle(transfer.phase.color)

    VStack(alignment: .leading, spacing: 5) {
        Text(transfer.phase.title)
            .font(.title2.bold())
            .foregroundStyle(transfer.phase.color)
        Text(transfer.status)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
    Spacer()
}
.padding(16)
.frame(maxWidth: .infinity, alignment: .leading)
.background(
    transfer.phase.color.opacity(0.08),
    in: RoundedRectangle(cornerRadius: 12)
)
    }

    @ViewBuilder private var manifestDetails: some View {
        Text("Файлов: \(fileCount)")
        Text("Размер: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: requiredBytes), countStyle: .file))")

        DisclosureGroup("Исключения macOS: \(excludedPaths.count)") {
            ForEach(excludedPaths, id: \.self) { path in
                Text(path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }

        Toggle(
            "Подтверждаю исключение перечисленных файлов macOS",
            isOn: $approved
        )
        .disabled(transfer.running)
    }

    @ViewBuilder private var transferProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Прогресс по файлам")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(fileFraction * 100))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: fileFraction)
                .tint(transfer.phase == .completed ? .green : .blue)

            Text("\(transfer.verifiedFiles) / \(transfer.totalFiles) файлов")
                .font(.caption.monospacedDigit())

            HStack {
                Text("Прогресс по объёму")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: fraction)
                .tint(transfer.phase == .completed ? .green : .blue)

            Text(
                "\(ByteCountFormatter.string(fromByteCount: Int64(clamping: transfer.verifiedBytes), countStyle: .file)) / " +
                ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: transfer.totalBytes),
                    countStyle: .file
                )
            )
            .font(.caption)
        }
    }

    private var finalVerificationProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Финальная проверка SHA-256")
                .font(.headline)

            ProgressView(
                value: Double(transfer.finalVerifiedFiles),
                total: Double(max(transfer.finalTotalFiles, 1))
            )

            Text("Проверено \(transfer.finalVerifiedFiles) из \(transfer.finalTotalFiles) файлов")
                .font(.caption.monospacedDigit())

            Label(
                "Проверка ещё выполняется. Не извлекайте накопители.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }

    private var transferControls: some View {
HStack {
    Button("Проверить исходную карту") {
        Task { await prepare() }
    }
    .disabled(scanning || transfer.running)

    Button("Начать / продолжить перенос") {
        confirmStart = true
    }
    .disabled(!prepared || !approved ||
              scanning || transfer.running)

    if transfer.running {
        Button("Остановить") {
            confirmStop = true
        }
    }
}
    }

    @MainActor
    private func prepare() async {
        guard !scanning && !transfer.running else { return }
        scanning = true
        prepared = false
        approved = false
        transfer.phase = .preparing
        transfer.status = NSLocalizedString("Составляем манифест…", comment: "Migration status")

        let chosenSourceDiskID = sourceDiskID
        let result = await Task.detached(priority: .userInitiated) {
            // Resolve the selected disk's mounted FAT32 partition afresh.
            let root: URL
            do {
                root = try SakuraPhysicalMigrationEngine.sourceRoot(for: chosenSourceDiskID)
            } catch {
                return (false, 0, UInt64(0), [String](),
                        "Ошибка проверки исходной карты: " + String(describing: error))
            }
            let manifest = SakuraMigrationManifest.inspect(
                root: root, policy: .excludeKnownMacOSMetadata
            )

            guard manifest.complete,
                  let bytes = manifest.totalLogicalBytes else {
                return (
                    false, 0, UInt64(0), [String](),
                    "Ошибка: " + manifest.errors.prefix(3)
                        .joined(separator: "; ")
                )
            }

            return (
                true, manifest.fileCount, bytes,
                manifest.skippedPaths.sorted(),
                "Манифест готов. Проверь исключения перед запуском."
            )
        }.value

        scanning = false
        prepared = result.0
        fileCount = result.1
        requiredBytes = result.2
        excludedPaths = result.3
        transfer.status = result.4
        transfer.phase = result.0 ? .ready : .failed
    }

    @MainActor
    private func start() {
        guard prepared && approved && !transfer.running else { return }

        let paths = Set(excludedPaths)
        let display = transfer
        let runID = UUID()
        display.runID = runID

        display.running = true
        SakuraMigrationActivity.active = true
        display.phase = .running
        display.status = NSLocalizedString("Проверяем тома, паспорт и журнал…", comment: "Migration status")

        let chosenSourceDiskID = sourceDiskID
        let chosenTargetDiskID = targetDiskID
        display.job = Task.detached(priority: .userInitiated) {
            do {
                let result = try SakuraPhysicalMigrationEngine.run(
                    sourceDiskID: chosenSourceDiskID,
                    targetDiskID: chosenTargetDiskID,
                    approvedSkippedPaths: paths,
                    shouldStop: { Task<Never, Never>.isCancelled },
                    onProgress: { progress in
                        Task { @MainActor in
                            guard display.running, display.runID == runID else { return }
                            display.verifiedFiles = progress.verifiedFiles
                            display.totalFiles = progress.totalFiles
                            display.verifiedBytes = progress.verifiedBytes
                            display.totalBytes = progress.totalBytes
                            display.status =
                                NSLocalizedString("Копирование и проверка SHA-256…", comment: "Migration status")
                        }
                    },
                    onFinalVerification: { checked, total in
                        Task { @MainActor in
                            guard display.running, display.runID == runID else { return }
                            display.phase = .verifying
                            display.finalVerifiedFiles = checked
                            display.finalTotalFiles = total
                            display.status = NSLocalizedString("Проверка SHA-256. Не извлекайте накопители.", comment: "Migration status")
                        }
                    }
                )

                await MainActor.run {
                    guard display.runID == runID else { return }
                    display.verifiedFiles = result.checkpoint.files.count
                    display.verifiedBytes = result.verifiedBytes
                    display.status =
                        NSLocalizedString("Перенос завершён. Все файлы проверены SHA-256.", comment: "Migration status")
                    display.phase = .completed
                    display.running = false
                    SakuraMigrationActivity.active = false
                    display.job = nil
                }
            } catch {
                let message = String(reflecting: error)
                await MainActor.run {
                    let cancelled = display.job?.isCancelled ?? false
                    display.phase = cancelled ? .stopped : .failed
                    display.status = cancelled
                        ? NSLocalizedString("Остановлено пользователем. Завершённые файлы сохранены.", comment: "Migration stopped")
                        : "Ошибка переноса: \(message)"
                    display.running = false
                    SakuraMigrationActivity.active = false
                    display.job = nil
                }
            }
        }
    }
}
