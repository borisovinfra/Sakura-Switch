import Foundation
import SwiftUI
import StorageCore

private enum SakuraMigrationPhase: Equatable {
    case idle, preparing, ready, running, completed, stopped, failed

    var title: String {
        switch self {
        case .idle: return NSLocalizedString("Ожидание", comment: "Migration state")
        case .preparing: return NSLocalizedString("Подготовка", comment: "Migration state")
        case .ready: return NSLocalizedString("Готово к переносу", comment: "Migration state")
        case .running: return NSLocalizedString("Перенос выполняется", comment: "Migration state")
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
        case .running, .preparing: return "arrow.triangle.2.circlepath"
        case .idle, .ready: return "externaldrive"
        }
    }

    var color: Color {
        switch self {
        case .completed: return .green
        case .failed: return .red
        case .stopped: return .orange
        case .running, .preparing: return .blue
        case .idle, .ready: return .secondary
        }
    }
}

@MainActor
final class SakuraMigrationDisplayState: ObservableObject {
    @Published var running = false
    @Published fileprivate var phase: SakuraMigrationPhase = .idle
    var runID = UUID()
    @Published var verifiedFiles = 0
    @Published var totalFiles = 0
    @Published var verifiedBytes: UInt64 = 0
    @Published var totalBytes: UInt64 = 0
    @Published var status = NSLocalizedString("Ожидание проверки исходной microSD.", comment: "Migration status")
    var job: Task<Void, Never>?
}

struct SakuraFullMigrationView: View {
    @StateObject private var transfer = SakuraMigrationDisplayState()

    @State private var fileCount = 0
    @State private var requiredBytes: UInt64 = 0
    @State private var excludedPaths: [String] = []
    @State private var scanning = false
    @State private var prepared = false
    @State private var approved = false
    @State private var confirmStart = false

    private var fraction: Double {
        guard transfer.totalBytes > 0 else { return 0 }
        return min(1, Double(transfer.verifiedBytes) /
                   Double(transfer.totalBytes))
    }

    var body: some View {
        GroupBox("Sakura Migration · файловая microSD") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("NINTENDO", systemImage: "sdcard")
                    Image(systemName: "arrow.right")
                    Label("SAKURASD", systemImage: "externaldrive")
                }
                .font(.subheadline)

                Text("Назначение: только лабораторный виртуальный FAT32-образ.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                if prepared {
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

                if transfer.running || transfer.totalFiles > 0 {
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
                        "Проверено: \(transfer.verifiedFiles) / \(transfer.totalFiles) файлов"
                    )
                    .font(.caption.monospacedDigit())

                    Text(
                        "\(ByteCountFormatter.string(fromByteCount: Int64(clamping: transfer.verifiedBytes), countStyle: .file)) / " +
                        ByteCountFormatter.string(
                            fromByteCount: Int64(clamping: transfer.totalBytes),
                            countStyle: .file
                        )
                    )
                    .font(.caption)
                }

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
                            transfer.status = NSLocalizedString("Ожидаем завершения текущего файла…", comment: "Migration status")
                            transfer.job?.cancel()
                        }
                    }
                }

                if scanning {
                    ProgressView("Сканирование NINTENDO…")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .confirmationDialog(
            "Разрешить перенос на виртуальную SAKURASD?",
            isPresented: $confirmStart
        ) {
            Button("Начать копирование файлов") {
                start()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(
                "Источник NINTENDO — только чтение. " +
                "Назначение — проверенный виртуальный образ SAKURASD. " +
                "Запись может занять продолжительное время."
            )
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

        let result = await Task.detached(priority: .userInitiated) {
            let root = URL(fileURLWithPath: "/Volumes/NINTENDO",
                           isDirectory: true)
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
        display.phase = .running
        display.status = NSLocalizedString("Проверяем тома, паспорт и журнал…", comment: "Migration status")

        display.job = Task.detached(priority: .userInitiated) {
            do {
                let result = try SakuraLabMigrationEngine.run(
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
                    display.job = nil
                }
            }
        }
    }
}
