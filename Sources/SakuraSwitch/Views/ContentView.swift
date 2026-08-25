import SwiftUI
import Installer
import NativeMTPTransport

struct ContentView: View {

    private enum SakuraSection: String, CaseIterable, Identifiable {
        case installation
        case sdCard
        case saves
        case gallery
        case gamesAndMods

        case dbiBackend
        case ftp

        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .installation: return "Установка"
            case .sdCard: return "SD-карта"
            case .saves: return "Сохранения"
            case .gallery: return "Галерея"
            case .gamesAndMods: return "Игры и моды"
            case .dbiBackend: return "DBI Backend"
            case .ftp: return "FTP"
            case .about: return "О программе"
            }
        }

        var icon: String {
            switch self {
            case .installation: return "square.and.arrow.down"
            case .sdCard: return "externaldrive"
            case .saves: return "archivebox"
            case .gallery: return "photo.on.rectangle"
            case .gamesAndMods: return "puzzlepiece.extension"
            case .dbiBackend: return "cable.connector"
            case .ftp: return "network"
            case .about: return "info.circle"
            }
        }
    }

    @Bindable var appState: AppState

    @State private var selectedSection: SakuraSection = .installation

    @State private var saveGames: [InstallationCoordinator.SDCardItem] = []
    @State private var isLoadingSaves = false
    @State private var savesError: String?
    @State private var lastInstallTransport: InstallationCoordinator.TransportMode = .mtp

    /// USB modes require a connected device; Network mode doesn't.
    private var installRequiresDevice: Bool {
        switch appState.coordinator.transportMode {
        case .dbiBackend, .mtp, .sdCard:
            return !appState.isDeviceConnected
        case .network:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sakuraSidebar

            Divider()

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            synchronizeInitialSection()
            appState.startMonitoring()
        }
        .onChange(of: appState.coordinator.state) {
            appState.updateTransferFlag()
        }
        .onChange(of: appState.coordinator.transportMode) {
            synchronizeSectionWithTransport()
        }
    }

    // MARK: - Sakura Navigation

    private var sakuraSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sakura Switch")
                    .font(.system(size: 16, weight: .semibold))

                Text(appState.appVersionDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            sidebarGroup([
                .installation,
                .sdCard,
                .saves,
                .gallery,
                .gamesAndMods
            ])

            Spacer(minLength: 16)

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

            sidebarGroup([
                .dbiBackend,
                .ftp
            ])

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

            sidebarGroup([
                .about
            ])
            .padding(.bottom, 10)
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
    }

    private func sidebarGroup(
        _ sections: [SakuraSection]
    ) -> some View {
        VStack(spacing: 2) {
            ForEach(sections) { section in
                Button {
                    selectSection(section)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon)
                            .frame(width: 17)

                        Text(section.title)
                            .lineLimit(1)

                        Spacer(minLength: 4)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.20))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .installation, .sdCard, .dbiBackend, .ftp:
            workingInterface

        case .saves:
            SavesView(appState: appState)

        case .gallery:
            GalleryView(appState: appState)

        case .gamesAndMods:
            GamesAndModsView(appState: appState)

        case .about:
            AboutView()
        }
    }

    private var workingInterface: some View {
        HSplitView {
            leftPanel
                .frame(
                    minWidth: 500,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            rightPanel
                .frame(
                    minWidth: 320,
                    idealWidth: 350,
                    maxWidth: 420,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var savesView: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Сохранения")
                        .font(.title2.weight(.semibold))

                    Text("Sakura Saves")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await loadSaveGames()
                    }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingSaves)
            }
            .padding()

            Divider()

            if isLoadingSaves {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Загрузка сохранений...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let savesError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)

                    Text("Не удалось загрузить сохранения")
                        .font(.headline)

                    Text(savesError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    Button("Повторить") {
                        Task {
                            await loadSaveGames()
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if saveGames.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)

                    Text("Сохранения не загружены")
                        .font(.headline)

                    Text("Подключите Switch с запущенным DBI MTP responder и нажмите «Обновить».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Загрузить сохранения") {
                        Task {
                            await loadSaveGames()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                List(saveGames) { game in
                    HStack(spacing: 10) {
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(.secondary)

                        Text(game.name)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if saveGames.isEmpty && !isLoadingSaves {
                await loadSaveGames()
            }
        }
    }

    @MainActor
    private func loadSaveGames() async {
        guard !isLoadingSaves else { return }

        isLoadingSaves = true
        savesError = nil

        do {
            saveGames = try await appState.coordinator.loadInstalledSaveGames()

            appState.coordinator.log(
                "Sakura Saves: найдено игр с сохранениями: \(saveGames.count)",
                level: .info
            )
        } catch {
            savesError = error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Saves: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingSaves = false
    }

    private func placeholderSection(
        title: String,
        icon: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectSection(_ section: SakuraSection) {
        selectedSection = section

        switch section {

        case .installation:
            if appState.coordinator.transportMode != .mtp {
                appState.setTransportMode(.mtp)
            }

        case .sdCard:
            if appState.coordinator.transportMode != .sdCard {
                appState.setTransportMode(.sdCard)
            }

        case .dbiBackend:
            if appState.coordinator.transportMode != .dbiBackend {
                appState.setTransportMode(.dbiBackend)
            }

        case .ftp:
            if appState.coordinator.transportMode != .network {
                appState.setTransportMode(.network)
            }

        default:
            break
        }
    }

    private func synchronizeInitialSection() {
        switch appState.coordinator.transportMode {

        case .mtp:
            selectedSection = .installation

        case .sdCard:
            selectedSection = .sdCard

        case .dbiBackend:
            selectedSection = .dbiBackend

        case .network:
            selectedSection = .ftp
        }
    }

    private func synchronizeSectionWithTransport() {
        switch appState.coordinator.transportMode {

        case .mtp:
            selectedSection = .installation

        case .sdCard:
            selectedSection = .sdCard

        case .dbiBackend:
            selectedSection = .dbiBackend

        case .network:
            selectedSection = .ftp
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {

            ConnectionStatusView(
                isConnected: appState.isDeviceConnected,
                mode: appState.coordinator.transportMode
            )

            if appState.coordinator.transportMode == .mtp {
                mtpTestSection
                mtpDestinationPicker
            }

            if appState.coordinator.transportMode == .sdCard {
                sdCardTestSection
            }

            if appState.showInstallHelp {
                installHelpBanner
            }

            if appState.coordinator.transportMode == .network {
                ftpAddressField
            }

            Divider()

            if appState.coordinator.transportMode == .sdCard {
                SDCardBrowserView(coordinator: appState.coordinator)
            } else {
                DropZoneView { urls in
                    appState.coordinator.queueFiles(urls)
                }
                .frame(height: 120)
                .padding()

                Divider()

                FileListView(files: appState.coordinator.progress.files)

                Divider()

                bottomBar
                    .padding()
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    // MARK: - Transport Mode Picker

    private var transportModePicker: some View {
        Picker("Режим", selection: Binding(
            get: { appState.coordinator.transportMode },
            set: { appState.setTransportMode($0) }
        )) {
            ForEach(InstallationCoordinator.TransportMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .disabled(appState.isTransferActive)
    }

    // MARK: - SD Card Test

    private var sdCardTestSection: some View {
        HStack {
            Button("Проверить SD-карту") {
                appState.testSDCardBrowser()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - MTP Test

    private var mtpTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Проверить MTP-соединение") {
                    appState.testMTPConnection()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if let result = appState.mtpTestResult {
                    Text(result)
                        .font(.caption2)
                        .foregroundStyle((result.contains("SUCCESS") || result.contains("УСПЕХ")) ? .green : result.contains("Проверка") ? .secondary : .red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - MTP Destination Picker

    private var mtpDestinationPicker: some View {
        HStack {
            Text("Установить в:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { appState.coordinator.mtpInstallDestination ?? MTPInstallDestination(storageID: 0, rawName: "SD Card install") },
                set: { appState.coordinator.mtpInstallDestination = $0 }
            )) {
                Text("SD Card").tag(MTPInstallDestination(storageID: 0, rawName: "SD Card install"))
                Text("NAND").tag(MTPInstallDestination(storageID: 0, rawName: "NAND install"))
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Help Banner

    private var installHelpBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Быстрая настройка")
                    .font(.subheadline.weight(.semibold))
                Text(appState.installHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Закрыть") {
                appState.dismissInstallHelp()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(10)
    }

    private var ftpAddressField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                    .font(.title3)

                Text("FTP-адрес Switch")
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 8) {
                TextField("Введите IP Switch (например, 192.168.0.96:5000)", text: Binding(
                    get: { appState.coordinator.ftpAddress },
                    set: { appState.coordinator.ftpAddress = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    appState.validateFTPAddress()
                }

                Button("Подключить") {
                    appState.validateFTPAddress()
                }
                .buttonStyle(.bordered)
                .disabled(appState.coordinator.ftpAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = appState.ftpValidationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if appState.isDeviceConnected && appState.coordinator.transportMode == .network {
                Label("Готово к установке через FTP", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Журнал событий")
                    .font(.headline)

                Spacer()

                Button {
                    appState.exportDiagnosticsLogs()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Экспортировать журнал диагностики")

                Button {
                    appState.copyLogsToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Скопировать журнал в буфер обмена")
                .disabled(appState.coordinator.logs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let exportStatus = appState.diagnosticsExportStatusMessage {
                Text(exportStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            Divider()

            LogView(entries: appState.coordinator.logs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            installButton

            Spacer()

            Text(appState.appVersionDisplay)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !appState.coordinator.progress.files.isEmpty {
                Button("Очистить очередь") {
                    appState.coordinator.reset()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var installButton: some View {
        InstallButtonView(
            state: appState.coordinator.state,
            progress: appState.coordinator.progress,
            isDisabled: appState.coordinator.progress.files.isEmpty || installRequiresDevice,
            onInstall: { appState.coordinator.startInstallation() },
            onCancel: { appState.coordinator.cancel() }
        )
    }
}
