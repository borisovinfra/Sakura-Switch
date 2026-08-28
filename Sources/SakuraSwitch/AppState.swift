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
            L10n.helpDBIBackend
        case .mtp:
            L10n.helpMTP
        case .sdCard:
            L10n.helpSDCard
        case .network:
            L10n.helpFTP
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
            ("Starting MTP connection test...", L10n.mtpStartingTest),
            ("Testing MTP handshake (will ask for admin password)...", L10n.mtpTestingHandshake),
            ("SUCCESS — MTP handshake completed!", L10n.mtpHandshakeSuccess),
            ("MTP handshake failed:", L10n.mtpHandshakeFailed),
            ("Kernel driver release:", L10n.mtpKernelRelease),
            ("Kernel driver released", L10n.mtpKernelReleased),
            ("Kernel driver detach:", L10n.mtpKernelDetach),
            ("Switch opened through libmtp", L10n.mtpSwitchOpened),
            ("Nintendo Switch / Switch Lite", "Nintendo Switch / Switch Lite"),
            ("Android device detected, assigning default bug flags",
             L10n.mtpCompatibility),
            ("Using storage", L10n.mtpUsingStorage),
            ("SD Card install", L10n.mtpInstallSD),
            ("NAND install", L10n.mtpInstallNAND),
            ("No MTP devices found", L10n.mtpNoDevices),
            ("Unable to open Switch through libmtp", L10n.mtpUnableOpen),
            ("Nintendo Switch DBI MTP device not found", L10n.mtpDBINotFound)
        ]

        for (source, destination) in replacements {
            text = text.replacingOccurrences(
                of: source,
                with: destination
            )
        }

        if text.hasPrefix("Found: ") {
            text = L10n.mtpFoundDevice(String(text.dropFirst("Found: ".count)))
        }

        return text
    }

    private func runMTPDiagnostic() async {
        logMTP(L10n.mtpStartingTest, level: .info)

        // Step 1: Scan for device (no admin needed)
        let devices = USBDeviceScanner.findDevices(vendorID: NintendoSwitchUSB.vendorID)
        if devices.isEmpty {
            logMTP(L10n.mtpUSBNotFound, level: .error)
            mtpTestResult = L10n.mtpSwitchNotFound
            return
        }
        for d in devices {
            logMTP(L10n.mtpFoundDevice(d.description), level: .info)
        }

        // Step 2: Run a quick MTP handshake test via PrivilegedMTPSession
        // This prompts for admin password, then does DeviceCapture → OpenSession → CloseSession
        logMTP(L10n.mtpTestingHandshake, level: .info)

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
            logMTP(L10n.mtpHandshakeSuccess, level: .info)
            mtpTestResult = L10n.mtpSuccess
        } catch {
            logMTP(L10n.mtpError(error.localizedDescription), level: .error)
            let found = devices.map(\.description).joined(separator: ", ")
            mtpTestResult = L10n.mtpResultError(found, error.localizedDescription)
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
                diagnosticsExportStatusMessage = L10n.diagnosticsSaved(exportedURL.lastPathComponent)
            } else {
                diagnosticsExportStatusMessage = L10n.diagnosticsCancelled
            }
        } catch {
            diagnosticsExportStatusMessage = L10n.diagnosticsError(error.localizedDescription)
        }
    }

    // MARK: - FTP Address Validation

    var ftpValidationError: String?
    var ftpAddressValidated: Bool = false

    func validateFTPAddress() {
        let address = coordinator.ftpAddress.trimmingCharacters(in: .whitespaces)

        if address.isEmpty {
            ftpValidationError = L10n.ftpMissingAddress
            ftpAddressValidated = false
            return
        }

        guard FTPConnectionInfo.parse(address) != nil else {
            ftpValidationError = L10n.ftpInvalidAddress
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
                L10n.sdChecking,
                level: .info
            )

            do {
                let items = try await coordinator.browseSDCard(path: "/")

                let folders = items.filter { $0.isDirectory }.count
                let files = items.count - folders

                coordinator.log(
                    L10n.sdAvailable,
                    level: .info
                )

                coordinator.log(
                    L10n.sdRootSummary(folders, files),
                    level: .info
                )

                coordinator.log(
                    L10n.sdCheckSuccess,
                    level: .info
                )

            } catch {
                let message = error.localizedDescription
                    .replacingOccurrences(
                        of: "No MTP device found",
                        with: L10n.mtpNoDevices
                    )
                    .replacingOccurrences(
                        of: "DBI MTP device not found",
                        with: L10n.mtpDBINotFound
                    )

                coordinator.log(
                    L10n.sdAccessError(message),
                    level: .error
                )
            }
        }
    }

    func testMTPConnection() {
        mtpTestResult = L10n.mtpChecking
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
