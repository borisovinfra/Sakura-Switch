import Foundation
import SwiftUI
import Installer
import ModInstaller

struct GamesAndModsView: View {

    @Bindable var appState: AppState

    struct GameInfo: Identifiable, Equatable {

        let rawName: String
        let title: String
        let titleID: String

        /// Точное физическое имя каталога на SD.
        /// Например: 01009bf0072d4000
        /// или:     01009bf0072d4000.disabled
        let contentsFolderName: String?

        let contentsEnabled: Bool

        var id: String {
            titleID
        }

        var hasContents: Bool {
            contentsFolderName != nil
        }

        /// Destination folder for new mods.
        /// Always the real Title ID, even when no mod exists yet.
        var installFolderName: String {
            titleID
        }
    }

    @State private var games: [GameInfo] = []
    @State private var selectedGame: GameInfo?

    @State private var contentsItems:
        [InstallationCoordinator.SDCardItem] = []

    @State private var isLoading = false
    @State private var isLoadingContents = false
    @State private var isChangingModState = false

    @State private var loadError: String?
    @State private var contentsError: String?
    @State private var selectedModURL: URL?
    @State private var selectedModInfo: ModInstaller.ModInfo?
    @State private var isInstallingMod = false
    @State private var modInstallMessage: String?

    
    private let modInstaller = ModInstaller()


    @State private var modStateError: String?

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            header

            Divider()

            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .task {

            if games.isEmpty &&
                !isLoading {

                await loadGames()
            }
        }

    }

    // MARK: - Header

    private var header: some View {

        HStack {

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(L10n.modsTitle)
                    .font(
                        .title2.weight(
                            .semibold
                        )
                    )

                Text("Atmosphère Contents")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }

            Spacer()

            if !games.isEmpty {


                Text(L10n.modsCounter(games.filter { $0.hasContents }.count, games.count))
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }

            Button {

                Task {

                    await loadGames()

                }

            } label: {

                Label(
                    L10n.modsRefresh,
                    systemImage: "arrow.clockwise"
                )

            }
            .buttonStyle(.bordered)
            .disabled(
                isLoading ||
                isLoadingContents ||
                isChangingModState
            )


            Button {

                print("🌸 ADD MOD CLICK")
                NSLog("🌸 ADD MOD BUTTON PRESSED")
                openModPicker()

            } label: {

                Label(
                    L10n.modsAdd,
                    systemImage: "plus.square.on.square"
                )

            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedGame == nil ||
                isLoading ||
                isChangingModState
            )

            
            Button {

                NSLog("🌸 INSTALL UI CLICK")

                Task {
                    await installSelectedMod()
                }

            } label: {

                Label(
                    isInstallingMod
                    ? L10n.modsInstalling
                    : L10n.modsInstall,
                    systemImage: "arrow.down.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isInstallingMod ||
                selectedModInfo == nil
            )


        }
        .padding()

    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {

        if isLoading {

            loadingView(
                L10n.modsScanning
            )

        } else if let loadError {

            errorView(
                title:
                    L10n.modsLoadFailed,
                message:
                    loadError
            ) {

                Task {
                    await loadGames()
                }
            }

        } else if games.isEmpty {

            VStack(spacing: 10) {

                Image(
                    systemName:
                        "gamecontroller"
                )
                .font(
                    .system(
                        size: 32,
                        weight: .light
                    )
                )
                .foregroundStyle(
                    .secondary
                )

                Text(
                    L10n.modsNoGames
                )
                .font(.headline)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )

        } else {

            HSplitView {

                gamesList
                    .frame(
                        minWidth: 360,
                        idealWidth: 430
                    )

                gameDetail
                    .frame(
                        minWidth: 430,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Games List

    private var gamesList: some View {

        List(games) { game in

            Button {

                selectedGame = game
                modStateError = nil

                Task {
                    await loadContents(
                        for: game
                    )
                }

            } label: {

                HStack(spacing: 10) {

                    Image(
                        systemName:
                            "gamecontroller"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {

                        Text(game.title)
                            .lineLimit(1)

                        Text(game.titleID)
                            .font(
                                .system(
                                    .caption2,
                                    design:
                                        .monospaced
                                )
                            )
                            .foregroundStyle(
                                .secondary
                            )
                    }

                    Spacer()

                    if game.hasContents {

                        Label(
                            game.contentsEnabled
                                ? L10n.modsBadgeEnabled
                                : L10n.modsBadgeDisabled,
                            systemImage:
                                game.contentsEnabled
                                ? "puzzlepiece.extension.fill"
                                : "pause.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
                .padding(
                    .vertical,
                    3
                )
                .contentShape(
                    Rectangle()
                )
            }
            .buttonStyle(.plain)
            .listRowBackground(

                selectedGame?.id ==
                    game.id

                ? Color.accentColor
                    .opacity(0.18)

                : Color.clear
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Detail

    @ViewBuilder
    private var gameDetail: some View {

        if let game =
            selectedGame {

            VStack(
                alignment: .leading,
                spacing: 0
            ) {

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {

                    HStack {

                        Text(game.title)
                            .font(.headline)

                        Spacer()

                        if game.hasContents {

                            Label(
                                game.contentsEnabled
                                    ? L10n.modsEnabled
                                    : L10n.modsDisabled,
                                systemImage:
                                    game.contentsEnabled
                                    ? "checkmark.circle.fill"
                                    : "pause.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                game.contentsEnabled
                                    ? Color.green
                                    : Color.red
                            )

                            Button {

                                Task {
                                    await toggleMods(
                                        for: game
                                    )
                                }

                            } label: {

                                if isChangingModState {

                                    ProgressView()
                                        .controlSize(
                                            .small
                                        )

                                } else {

                                    Label(
                                        game.contentsEnabled
                                            ? L10n.modsDisable
                                            : L10n.modsEnable,
                                        systemImage:
                                            game.contentsEnabled
                                            ? "pause.circle"
                                            : "play.circle"
                                    )
                                }
                            }
                            .buttonStyle(
                                .bordered
                            )
                            .disabled(
                                isChangingModState ||
                                isLoading ||
                                isLoadingContents
                            )

                        } else {

                            Text(
                                L10n.modsNotFound
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    Text(game.titleID)
                        .font(
                            .system(
                                .caption,
                                design:
                                    .monospaced
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .textSelection(
                            .enabled
                        )

                    if let folderName =
                        game.contentsFolderName {

                        Text(
                            "/atmosphere/contents/\(folderName)"
                        )
                        .font(
                            .system(
                                .caption2,
                                design:
                                    .monospaced
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .textSelection(
                            .enabled
                        )
                    }

                    if let modStateError {

                        Text(modStateError)
                            .font(.caption)
                            .foregroundStyle(
                                .red
                            )
                            .textSelection(
                                .enabled
                            )
                    }
                }
                .padding()

                Divider()

                if !game.hasContents {

                    VStack(spacing: 10) {

                        Image(
                            systemName:
                                "puzzlepiece.extension"
                        )
                        .font(
                            .system(
                                size: 30,
                                weight: .light
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )

                        Text(
                            L10n.modsNoneDetected
                        )
                        .font(.headline)

                        Text(
                            L10n.modsNoneHint
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                } else if isLoadingContents {

                    loadingView(
                        L10n.modsReadingContents
                    )

                } else if let contentsError {

                    errorView(
                        title:
                            L10n.modsOpenContentsFailed,
                        message:
                            contentsError
                    ) {

                        Task {
                            await loadContents(
                                for: game
                            )
                        }
                    }

                } else if contentsItems.isEmpty {

                    VStack(spacing: 10) {

                        Image(
                            systemName:
                                "folder"
                        )
                        .font(
                            .system(
                                size: 30,
                                weight: .light
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )

                        Text(L10n.modsFolderEmpty)
                            .font(.headline)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                } else {

                    List(
                        contentsItems
                    ) { item in

                        HStack(
                            spacing: 10
                        ) {

                            Image(
                                systemName:
                                    item.isDirectory
                                    ? folderIcon(
                                        item.name
                                    )
                                    : "doc"
                            )
                            .foregroundStyle(
                                .secondary
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {

                                Text(item.name)

                                if !item.isDirectory {

                                    Text(
                                        ByteCountFormatter
                                            .string(
                                                fromByteCount:
                                                    Int64(
                                                        item.size
                                                    ),
                                                countStyle:
                                                    .file
                                            )
                                    )
                                    .font(
                                        .caption2
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }

                            Spacer()

                            if item.isDirectory,
                               let meaning =
                                folderMeaning(
                                    item.name
                                ) {

                                Text(meaning)
                                    .font(
                                        .caption
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )
                            }
                        }
                        .padding(
                            .vertical,
                            3
                        )
                    }
                    .listStyle(.inset)
                }
            }

        } else {

            VStack(spacing: 10) {

                Image(
                    systemName:
                        "puzzlepiece.extension"
                )
                .font(
                    .system(
                        size: 32,
                        weight: .light
                    )
                )
                .foregroundStyle(
                    .secondary
                )

                Text(L10n.modsSelectGame)
                    .font(.headline)

                Text(
                    L10n.modsSelectGameHint
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .multilineTextAlignment(
                    .center
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Load Games

    @MainActor
    private func loadGames() async {

        guard !isLoading else {
            return
        }

        isLoading = true
        loadError = nil

        selectedGame = nil
        contentsItems = []
        contentsError = nil
        modStateError = nil

        do {

            /*
             DBI MTP must be accessed serially.
             Two simultaneous helper sessions compete
             for the same USB device.
             */

            let installed =
                try await appState
                    .coordinator
                    .loadInstalledSaveGames()

            let contents =
                try await appState
                    .coordinator
                    .browseSDCard(
                        path:
                            "/atmosphere/contents"
                    )

            /*
             Active:
                 0100...

             Disabled by Sakura:
                 0100....disabled

             Key is normalized uppercase Title ID.
             folderName always preserves the REAL SD spelling.
             */

            var contentFolders: [
                String: (
                    folderName: String,
                    enabled: Bool
                )
            ] = [:]

            for item in contents {

                guard item.isDirectory else {
                    continue
                }

                if isTitleID(
                    item.name
                ) {

                    contentFolders[
                        item.name.uppercased()
                    ] = (
                        folderName:
                            item.name,
                        enabled:
                            true
                    )

                    continue
                }

                let suffix =
                    ".disabled"

                guard
                    item.name
                        .lowercased()
                        .hasSuffix(
                            suffix
                        )
                else {
                    continue
                }

                let baseName =
                    String(
                        item.name
                            .dropLast(
                                suffix.count
                            )
                    )

                guard isTitleID(
                    baseName
                ) else {
                    continue
                }

                let key =
                    baseName.uppercased()

                /*
                 If both active and disabled somehow
                 exist, the active directory wins.
                 */

                if contentFolders[key] ==
                    nil {

                    contentFolders[
                        key
                    ] = (
                        folderName:
                            item.name,
                        enabled:
                            false
                    )
                }
            }

            games =
                installed
                    .compactMap {
                        item
                        -> GameInfo? in

                        guard
                            let id =
                                titleID(
                                    item.name
                                )
                        else {
                            return nil
                        }

                        let normalizedID =
                            id.uppercased()

                        let contentsInfo =
                            contentFolders[
                                normalizedID
                            ]

                        return GameInfo(
                            rawName:
                                item.name,
                            title:
                                displayName(
                                    item.name
                                ),
                            titleID:
                                normalizedID,
                            contentsFolderName:
                                contentsInfo?
                                    .folderName,
                            contentsEnabled:
                                contentsInfo?
                                    .enabled
                                ?? false
                        )
                    }
                    .sorted {

                        $0.title
                            .localizedCaseInsensitiveCompare(
                                $1.title
                            )
                        ==
                        .orderedAscending
                    }

            appState.coordinator.log(
                L10n.modsLogGames(games.count, games.filter { $0.hasContents }.count),
                level: .info
            )

        } catch {

            loadError =
                error.localizedDescription

            appState.coordinator.log(
                L10n.modsLogError(error.localizedDescription),
                level: .error
            )
        }

        isLoading = false
    }

    // MARK: - Enable / Disable Mods

    @MainActor
    private func toggleMods(
        for game: GameInfo
    ) async {

        guard
            !isChangingModState,
            let currentFolder =
                game.contentsFolderName
        else {
            return
        }

        isChangingModState = true
        modStateError = nil

        defer {
            isChangingModState = false
        }

        let suffix =
            ".disabled"

        let newFolder: String

        if game.contentsEnabled {

            /*
             Do not delete anything.
             Atmosphère will no longer treat this
             directory as a valid Title ID.
             */

            newFolder =
                currentFolder +
                suffix

        } else {

            guard
                currentFolder
                    .lowercased()
                    .hasSuffix(
                        suffix
                    )
            else {

                modStateError =
                    L10n.modsInvalidDisabledName

                return
            }

            newFolder =
                String(
                    currentFolder
                        .dropLast(
                            suffix.count
                        )
                )
        }

        do {

            try await appState
                .coordinator
                .renameSDCardItem(
                    parentPath:
                        "/atmosphere/contents",
                    oldName:
                        currentFolder,
                    newName:
                        newFolder
                )

            appState.coordinator.log(
                L10n.modsLogToggle(game.title, !game.contentsEnabled),
                level: .info
            )

            /*
             Read the real SD state again instead of
             pretending the rename succeeded locally.
             */

            await loadGames()

            if let refreshed =
                games.first(
                    where: {
                        $0.titleID ==
                            game.titleID
                    }
                ) {

                selectedGame =
                    refreshed

                await loadContents(
                    for: refreshed
                )
            }

        } catch {

            modStateError =
                error.localizedDescription

            appState.coordinator.log(
                L10n.modsLogToggleError(error.localizedDescription),
                level: .error
            )
        }
    }

    // MARK: - Load Game Contents

    @MainActor
    private func loadContents(
        for game: GameInfo
    ) async {

        contentsItems = []
        contentsError = nil

        guard
            let contentsFolderName =
                game.contentsFolderName
        else {
            return
        }

        isLoadingContents = true

        do {

            contentsItems =
                try await appState
                    .coordinator
                    .browseSDCard(
                        path:
                            "/atmosphere/contents/\(contentsFolderName)"
                    )

            appState.coordinator.log(
                L10n.modsLogContents(game.title, contentsItems.count),
                level: .info
            )

        } catch {

            contentsError =
                error.localizedDescription

            appState.coordinator.log(
                L10n.modsLogError(error.localizedDescription),
                level: .error
            )
        }

        isLoadingContents = false
    }

    

    private func openModPicker() {

        NSLog("🌸 OPEN MOD PICKER ENTER")

        let panel = NSOpenPanel()

        panel.title = L10n.modsChooseFolder
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK,
           let url = panel.url {

            NSLog("🌸 PICKED \(url.path)")

            Task { @MainActor in

                do {

                    NSLog("🌸 ANALYZE START")

                    let info =
                        try modInstaller.analyze(
                            url: url
                        )

                    NSLog(
                        "🌸 ANALYZE OK \(info.titleID)"
                    )

                    selectedModInfo = nil

                    await Task.yield()

                    selectedModInfo = info

                    NSLog(
                        "🌸 SELECTED MOD INFO SET \(info.titleID)"
                    )

                    appState.coordinator.log(
                        L10n.modsLogDetected(info.titleID),
                        level: .info
                    )

                } catch {

                    NSLog(
                        "❌ MOD ERROR \(error)"
                    )
                }
            }
        }
    }

    @MainActor
    private func installSelectedMod() async {

        NSLog("🌸 INSTALL BUTTON PRESSED")

        guard let info = selectedModInfo else {
            return
        }

        guard !isInstallingMod else {
            return
        }

        isInstallingMod = true
        modInstallMessage = nil

        defer {
            isInstallingMod = false
        }

        do {

            let contentsPath = "/atmosphere/contents"
            let titleFolder = info.titleID.lowercased()

            try await appState.coordinator.createSDCardFolder(
                parentPath: contentsPath,
                folderName: titleFolder
            )

            NSLog(
                "🌸 TITLE FOLDER PREPARED \\(titleFolder)"
            )

            try await modInstaller.install(
                mod: info,
                uploadDirectory: { url, destination in

                    try await appState.coordinator
                        .uploadSDCardDirectoryContents(
                            url,
                            destinationPath: destination
                        )
                },
                log: { message in

                    appState.coordinator.log(
                        message,
                        level: .info
                    )
                },

                progress: { message in
                    modInstallMessage = message
                }
            )

            modInstallMessage =
                L10n.modsInstalled

            if let currentGame = selectedGame {
                await loadGames()

                if let refreshed =
                    games.first(
                        where: {
                            $0.titleID == currentGame.titleID
                        }
                    ) {

                    selectedGame = refreshed

                    await loadContents(
                        for: refreshed
                    )
                }
            }

        } catch {

            modInstallMessage =
                L10n.modsInstallError(error.localizedDescription)
        }
    }



// MARK: - Title ID

    private func titleID(
        _ rawName: String
    ) -> String? {

        guard
            let open =
                rawName.lastIndex(
                    of: "["
                ),
            let close =
                rawName.lastIndex(
                    of: "]"
                ),
            open < close
        else {
            return nil
        }

        let value =
            String(
                rawName[
                    rawName.index(
                        after: open
                    )
                    ..<
                    close
                ]
            )

        guard isTitleID(
            value
        ) else {
            return nil
        }

        return value
    }

    private func isTitleID(
        _ value: String
    ) -> Bool {

        guard value.count == 16 else {
            return false
        }

        let allowed =
            CharacterSet(
                charactersIn:
                    "0123456789abcdefABCDEF"
            )

        return value
            .unicodeScalars
            .allSatisfy {
                allowed.contains($0)
            }
    }

    private func displayName(
        _ rawName: String
    ) -> String {

        guard
            let id =
                titleID(
                    rawName
                )
        else {
            return rawName
        }

        return rawName
            .replacingOccurrences(
                of:
                    " [\(id)]",
                with:
                    ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }

    // MARK: - Folder Presentation

    private func folderIcon(
        _ name: String
    ) -> String {

        switch name.lowercased() {

        case "romfs":
            return "folder.fill"

        case "exefs":
            return "cpu"

        case "cheats":
            return "terminal"

        default:
            return "folder"
        }
    }

    private func folderMeaning(
        _ name: String
    ) -> String? {

        switch name.lowercased() {

        case "romfs":
            return "RomFS"

        case "exefs":
            return "ExeFS"

        case "cheats":
            return L10n.modsFolderCheats

        case "flags":
            return L10n.modsFolderFlags

        default:
            return nil
        }
    }

    // MARK: - Loading / Error

    private func loadingView(
        _ text: String
    ) -> some View {

        VStack(spacing: 10) {

            ProgressView()

            Text(text)
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private func errorView(
        title: String,
        message: String,
        retry: @escaping () -> Void
    ) -> some View {

        VStack(spacing: 10) {

            Image(
                systemName:
                    "exclamationmark.triangle"
            )
            .font(
                .system(
                    size: 26
                )
            )
            .foregroundStyle(
                .orange
            )

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .multilineTextAlignment(
                    .center
                )
                .textSelection(
                    .enabled
                )

            Button(
                L10n.modsRetry,
                action: retry
            )
        }
        .padding(24)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }
}
