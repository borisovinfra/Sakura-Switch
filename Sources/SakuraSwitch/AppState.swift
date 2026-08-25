import Foundation
import AppKit
import os
import Installer
import USBTransport
import NativeMTPTransport
import NetworkTransport
import DBIProtocol

protocol PreferencesStore {
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Bool, forKey defaultName: String)
    func string(forKey defaultName: String) -> String?
    func setString(_ value: String, forKey defaultName: String)
}

extension UserDefaults: PreferencesStore {
    func setString(_ value: String, forKey defaultName: String) {
        set(value, forKey: defaultName)
    }
}

/// Top-level observable state for the app.
@Observable
@MainActor
final class AppState {
    private static let installHelpDismissedKey = "sakuraswitch.installHelp.dismissed"
    private static let lastFTPAddressKey = "sakuraswitch.ftp.lastAddress"
    private static let lastTransportModeKey = "sakuraswitch.transportMode"

    let coordinator = InstallationCoordinator()
    let deviceMonitor: USBDeviceMonitor
    var isDeviceConnected = false
    var showInstallHelp: Bool
    var diagnosticsExportStatusMessage: String?
    private var monitorTask: Task<Void, Never>?
    private let preferences: PreferencesStore
    private let appVersionProvider: any AppVersionProviding
    private let diagnosticsExportRunner: any DiagnosticsExportRunning

    /// Shared flag for device mutex — set by coordinator state changes.
    private let _isTransferActive = TransferActiveFlag()

    init(
        preferences: PreferencesStore = UserDefaults.standard,
        appVersionProvider: any AppVersionProviding = DefaultAppVersionProvider(),
        diagnosticsExportRunner: (any DiagnosticsExportRunning)? = nil
    ) {
        let flag = _isTransferActive
        self.preferences = preferences
        self.appVersionProvider = appVersionProvider
        if let diagnosticsExportRunner {
            self.diagnosticsExportRunner = diagnosticsExportRunner
        } else {
            self.diagnosticsExportRunner = DiagnosticsExportUseCase(
                formatter: PlainTextDiagnosticsFormatter(),
                exporter: SavePanelDiagnosticsExporter()
            )
        }
        self.deviceMonitor = USBDeviceMonitor { flag.value }
        self.showInstallHelp = !preferences.bool(forKey: Self.installHelpDismissedKey)

        // Restore last FTP address
        if let lastAddress = preferences.string(forKey: Self.lastFTPAddressKey) {
            coordinator.ftpAddress = lastAddress
        }

        // Restore last transport mode
        if let savedMode = preferences.string(forKey: Self.lastTransportModeKey),
           let mode = InstallationCoordinator.TransportMode.allCases.first(where: { $0.rawValue == savedMode }) {
            coordinator.transportMode = mode
        }
    }

    var isTransferActive: Bool {
        switch coordinator.state {
        case .transferring, .reconnecting: return true
        default: return false
        }
    }

    var appVersionDisplay: String {
        let version = appVersionProvider.displayVersion
        guard shouldPrefixVersion(version) else { return version }
        return "v\(version)"
    }

    private func shouldPrefixVersion(_ version: String) -> Bool {
        guard let first = version.first else { return false }
        return first.isNumber
    }

    /// Help text depends on the selected mode.
    var installHelpText: String {
        switch coordinator.transportMode {
        case .dbiBackend:
            "На Switch откройте DBI и выберите \"Run DBI backend\" перед подключением USB."
        case .mtp:
            "На Switch откройте DBI → \"Run MTP responder\"."
        case .sdCard:
            "На Switch откройте DBI → \"Run MTP responder\" для доступа к SD-карте."
        case .network:
            "На Switch откройте DBI → Start FTP → Install on SD Card. Затем введите IP-адрес и порт, показанные на Switch."
        }
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task {
            // Poll for device based on current transport mode
            var wasConnected = false
            while !Task.isCancelled {
                let found: Bool
                switch coordinator.transportMode {
                case .dbiBackend:
                    // Use USBDeviceMonitor's underlying check (libusb, PID 0x3000)
                    found = USBDeviceScanner.findDevice(
                        vendorID: NintendoSwitchUSB.vendorID,
                        productID: NintendoSwitchUSB.backendProductID
                    ) != nil
                case .mtp, .sdCard:
                    // Scan for MTP PID (0x201D)
                    found = USBDeviceScanner.findDevice(
                        vendorID: NintendoSwitchUSB.vendorID,
                        productID: NintendoSwitchUSB.mtpProductID
                    ) != nil
                case .network:
                    // Network mode: "connected" when user validated FTP address
                    found = ftpAddressValidated
                }

                if found != wasConnected {
                    isDeviceConnected = found
                    wasConnected = found
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func updateTransferFlag() {
        _isTransferActive.value = isTransferActive
    }

    private func logMTP(_ msg: String, level: DBIProtocol.LogLevel = .info) {
        coordinator.log("[MTP] \(localizedMTPMessage(msg))", level: level)
    }

    private func localizedMTPMessage(_ message: String) -> String {
        var text = message

        let replacements: [(String, String)] = [
            ("Starting MTP connection test...", "Запуск проверки MTP-соединения..."),
            ("Testing MTP handshake (will ask for admin password)...", "Проверка MTP-соединения..."),
            ("SUCCESS — MTP handshake completed!", "Соединение MTP установлено успешно"),
            ("MTP handshake failed:", "Ошибка MTP-соединения:"),
            ("Kernel driver release:", "Освобождение USB-драйвера:"),
            ("Kernel driver released", "USB-драйвер освобождён"),
            ("Kernel driver detach:", "Отключение USB-драйвера:"),
            ("Switch opened through libmtp", "Nintendo Switch открыт через MTP"),
            ("Nintendo Switch / Switch Lite", "Nintendo Switch / Switch Lite"),
            ("Android device detected, assigning default bug flags",
             "Устройство MTP обнаружено, применены параметры совместимости"),
            ("Using storage", "Используется хранилище"),
            ("SD Card install", "Установка на SD-карту"),
            ("NAND install", "Установка в NAND"),
            ("No MTP devices found", "MTP-устройство не найдено"),
            ("Unable to open Switch through libmtp", "Не удалось открыть Nintendo Switch через MTP"),
            ("Nintendo Switch DBI MTP device not found", "Nintendo Switch с запущенным DBI MTP не найден")
        ]

        for (source, destination) in replacements {
            text = text.replacingOccurrences(
                of: source,
                with: destination
            )
        }

        if text.hasPrefix("Found: ") {
            text = "Найдено устройство: " + text.dropFirst("Found: ".count)
        }

        return text
    }

    private func runMTPDiagnostic() async {
        logMTP("Запуск проверки MTP-соединения...", level: .info)

        // Step 1: Scan for device (no admin needed)
        let devices = USBDeviceScanner.findDevices(vendorID: NintendoSwitchUSB.vendorID)
        if devices.isEmpty {
            logMTP("USB-устройство Nintendo не найдено", level: .error)
            mtpTestResult = "ОШИБКА — Nintendo Switch не найден. Проверьте подключение и запуск DBI MTP."
            return
        }
        for d in devices {
            logMTP("Найдено устройство: \(d.description)", level: .info)
        }

        // Step 2: Run a quick MTP handshake test via PrivilegedMTPSession
        // This prompts for admin password, then does DeviceCapture → OpenSession → CloseSession
        logMTP("Проверка MTP-соединения...", level: .info)

        let session = mtpSessionFactory()
        do {
            // Install with empty file list — just tests the handshake
            try await session.install(
                files: [],
                targetStorageID: nil,
                onProgress: { _, _, _ in },
                onLog: { [weak self] msg in
                    Task { @MainActor in self?.logMTP(msg, level: .debug) }
                }
            )
            logMTP("Соединение MTP установлено успешно", level: .info)
            mtpTestResult = "УСПЕХ — доступ по MTP подтверждён!"
        } catch {
            logMTP("Ошибка MTP-соединения: \(error.localizedDescription)", level: .error)
            let found = devices.map(\.description).joined(separator: ", ")
            mtpTestResult = "ОШИБКА — \(found). \(error.localizedDescription)"
        }
    }

    func dismissInstallHelp() {
        showInstallHelp = false
        preferences.set(true, forKey: Self.installHelpDismissedKey)
    }

    // MARK: - Copy Logs

    /// Formats all activity log entries as a string and copies to clipboard.
    @discardableResult
    func copyLogsToString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let text = coordinator.logs.map { entry in
            let level = "[\(String(describing: entry.level).uppercased())]"
            let time = formatter.string(from: entry.timestamp)
            return "\(time) \(level) \(entry.message)"
        }.joined(separator: "\n")

        return text
    }

    func copyLogsToClipboard() {
        let text = copyLogsToString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportDiagnosticsLogs() {
        let request = DiagnosticsExportRequest(
            appVersion: appVersionProvider.displayVersion,
            transportMode: coordinator.transportMode.rawValue,
            installationState: coordinator.state.diagnosticsLabel
        )

        do {
            let exportedURL = try diagnosticsExportRunner.export(request: request, entries: coordinator.logs)
            if let exportedURL {
                diagnosticsExportStatusMessage = "Диагностика сохранена: \(exportedURL.lastPathComponent)"
            } else {
                diagnosticsExportStatusMessage = "Экспорт диагностики отменён."
            }
        } catch {
            diagnosticsExportStatusMessage = "Ошибка экспорта диагностики: \(error.localizedDescription)"
        }
    }

    // MARK: - FTP Address Validation

    var ftpValidationError: String?
    var ftpAddressValidated: Bool = false

    func validateFTPAddress() {
        let address = coordinator.ftpAddress.trimmingCharacters(in: .whitespaces)

        if address.isEmpty {
            ftpValidationError = "Введите IP-адрес, указанный на Switch"
            ftpAddressValidated = false
            return
        }

        guard FTPConnectionInfo.parse(address) != nil else {
            ftpValidationError = "Неверный формат. Используйте IP:порт, например 192.168.0.96:5000"
            ftpAddressValidated = false
            return
        }

        ftpValidationError = nil
        ftpAddressValidated = true
        preferences.setString(address, forKey: Self.lastFTPAddressKey)
    }

    /// Change transport mode and persist the choice.
    func setTransportMode(_ mode: InstallationCoordinator.TransportMode) {
        coordinator.transportMode = mode
        preferences.setString(mode.rawValue, forKey: Self.lastTransportModeKey)
    }

    // MARK: - MTP Connection Test

    var mtpTestResult: String?

    /// Injectable for testing — defaults to real PrivilegedMTPSession.
    var mtpSessionFactory: () -> any MTPSessionProtocol = { PrivilegedMTPSession() }

    func testSDCardBrowser() {
        Task {
            coordinator.log(
                "Проверка доступа к SD-карте...",
                level: .info
            )

            do {
                let items = try await coordinator.browseSDCard(path: "/")

                let folders = items.filter { $0.isDirectory }.count
                let files = items.count - folders

                coordinator.log(
                    "SD-карта доступна",
                    level: .info
                )

                coordinator.log(
                    "Корень SD-карты: \(folders) папок, \(files) файлов",
                    level: .info
                )

                coordinator.log(
                    "Проверка SD-карты завершена успешно",
                    level: .info
                )

            } catch {
                let message = error.localizedDescription
                    .replacingOccurrences(
                        of: "No MTP device found",
                        with: "MTP-устройство не найдено"
                    )
                    .replacingOccurrences(
                        of: "DBI MTP device not found",
                        with: "Nintendo Switch с запущенным DBI MTP не найден"
                    )

                coordinator.log(
                    "Ошибка доступа к SD-карте: \(message)",
                    level: .error
                )
            }
        }
    }

    func testMTPConnection() {
        mtpTestResult = "Проверка..."
        Task {
            await runMTPDiagnostic()
        }
    }
}

private extension InstallationCoordinator.State {
    var diagnosticsLabel: String {
        switch self {
        case .idle: "idle"
        case .connecting: "connecting"
        case .connected: "connected"
        case .transferring: "transferring"
        case .reconnecting(let attempt): "reconnecting(\(attempt))"
        case .complete: "complete"
        case .error(let message): "error(\(message))"
        }
    }
}

/// Thread-safe flag bridging @MainActor state to background polling.
/// Uses os_unfair_lock for safe concurrent read/write.
final class TransferActiveFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var value: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
