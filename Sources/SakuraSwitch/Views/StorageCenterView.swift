import SwiftUI
import StorageCore

/// First-stage Storage Center screen. No disk writes or device commands.
struct StorageCenterView: View {
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

                GroupBox("Накопители") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Обнаружение внешних дисков пока не подключено к экрану.",
                              systemImage: "externaldrive")
                        Text("Следующий шаг — подключение StorageInspector и проверки физических дисков.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                GroupBox("Диагностика emuMMC") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Проверка пока не запускалась.", systemImage: "waveform.path.ecg")
                        Text("Здесь появится отчёт для файловой или RAW emuMMC после выбора источника.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                Text("Обнаруженная структура не является подтверждением целостности NAND или готовности к переносу.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
