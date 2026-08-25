import SwiftUI
import Installer
import DBIProtocol

struct LogView: View {
    let entries: [LogEntry]
    @State private var minimumLevel: LogLevel = .debug

    private var filteredEntries: [LogEntry] {
        entries.filter { $0.level >= minimumLevel }
    }

    var body: some View {
        VStack(spacing: 0) {
            levelFilterBar
            Divider()
            logContent
        }
    }

    // MARK: - Filter Bar

    private var levelFilterBar: some View {
        Picker("", selection: $minimumLevel) {
            Text("Все").tag(LogLevel.debug)
            Text("Информация").tag(LogLevel.info)
            Text("Предупреждения").tag(LogLevel.warning)
            Text("Ошибки").tag(LogLevel.error)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: entries.count) {
                if let last = filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(colorForEntry(entry))
                .textSelection(.enabled)
        }
    }

    private func colorForEntry(_ entry: LogEntry) -> Color {
        switch entry.level {
        case .error:
            return .red
        case .warning:
            return .orange
        case .debug:
            return .secondary
        case .info:
            break
        }

        let message = entry.message.lowercased()

        let successMarkers = [
            "успешно",
            "успех",
            "sd-карта доступна",
            "соединение mtp установлено успешно",
            "проверка sd-карты завершена успешно",
            "подключён",
            "подключено"
        ]

        if successMarkers.contains(where: { message.contains($0) }) {
            return .green
        }

        let errorMarkers = [
            "ошибка",
            "не удалось",
            "не найден",
            "не найдена",
            "не найдено",
            "failed",
            "error"
        ]

        if errorMarkers.contains(where: { message.contains($0) }) {
            return .red
        }

        return .primary
    }
}
