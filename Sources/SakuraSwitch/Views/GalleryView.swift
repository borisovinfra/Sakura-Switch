import Foundation
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import Installer

struct GalleryView: View {

    @Bindable var appState: AppState

    // MARK: - Games

    @State private var albumGames: [InstallationCoordinator.SDCardItem] = []
    @State private var selectedGame: InstallationCoordinator.SDCardItem?

    @State private var isLoadingGames = false
    @State private var gamesError: String?

    // MARK: - Media

    @State private var mediaItems: [InstallationCoordinator.SDCardItem] = []
    @State private var selectedMedia: InstallationCoordinator.SDCardItem?

    @State private var isLoadingMedia = false
    @State private var mediaError: String?

    // MARK: - Preview

    @State private var isLoadingPreview = false
    @State private var previewError: String?

    @State private var selectedLocalURL: URL?
    @State private var previewImage: NSImage?

    @State private var previewTempDirectory: URL?

    @State private var videoPlayer: AVPlayer?

    // MARK: - Export

    @State private var exportStatus: String?
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            header

            Divider()

            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .task {
            if albumGames.isEmpty && !isLoadingGames {
                await loadAlbumGames()
            }
        }
        .onDisappear {
            cleanupPreview()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {

            VStack(alignment: .leading, spacing: 2) {

                Text("Галерея")
                    .font(.title2.weight(.semibold))

                Text("Sakura Gallery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await loadAlbumGames()
                }
            } label: {
                Label(
                    "Обновить",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(
                isLoadingGames ||
                isLoadingMedia ||
                isLoadingPreview
            )
        }
        .padding()
    }

    // MARK: - Main Content

    @ViewBuilder
    private var content: some View {

        if isLoadingGames {

            loadingView(
                "Загрузка галереи..."
            )

        } else if let gamesError {

            errorView(
                title: "Не удалось открыть галерею",
                message: gamesError
            ) {
                Task {
                    await loadAlbumGames()
                }
            }

        } else if albumGames.isEmpty {

            emptyGalleryView

        } else {

            HSplitView {

                gamesList
                    .frame(
                        minWidth: 250,
                        idealWidth: 300
                    )

                mediaSection
                    .frame(
                        minWidth: 620,
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

    // MARK: - Empty Gallery

    private var emptyGalleryView: some View {
        VStack(spacing: 10) {

            Image(systemName: "photo.on.rectangle")
                .font(
                    .system(
                        size: 32,
                        weight: .light
                    )
                )
                .foregroundStyle(.secondary)

            Text("Галерея пуста")
                .font(.headline)

            Text(
                "В Album DBI не найдено фотографий или видео."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Games

    private var gamesList: some View {
        List(albumGames) { game in

            Button {
                selectedGame = game

                Task {
                    await loadMedia(
                        for: game
                    )
                }

            } label: {

                HStack(spacing: 10) {

                    Image(systemName: "gamecontroller")
                        .foregroundStyle(.secondary)

                    Text(game.name)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                selectedGame?.id == game.id
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Media Section

    @ViewBuilder
    private var mediaSection: some View {

        if let game = selectedGame {

            VStack(
                alignment: .leading,
                spacing: 0
            ) {

                HStack {

                    Image(systemName: "photo.stack")

                    Text(game.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if !mediaItems.isEmpty {
                        Text("\(mediaItems.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                if isLoadingMedia {

                    loadingView(
                        "Загрузка медиа..."
                    )

                } else if let mediaError {

                    errorView(
                        title: "Не удалось открыть альбом",
                        message: mediaError
                    ) {
                        Task {
                            await loadMedia(
                                for: game
                            )
                        }
                    }

                } else if mediaItems.isEmpty {

                    VStack(spacing: 10) {

                        Image(systemName: "photo")
                            .font(
                                .system(
                                    size: 30,
                                    weight: .light
                                )
                            )
                            .foregroundStyle(.secondary)

                        Text("Нет медиа")
                            .font(.headline)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                } else {

                    HSplitView {

                        mediaList
                            .frame(
                                minWidth: 260,
                                idealWidth: 310
                            )

                        previewView
                            .frame(
                                minWidth: 360,
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

        } else {

            VStack(spacing: 10) {

                Image(systemName: "photo.stack")
                    .font(
                        .system(
                            size: 32,
                            weight: .light
                        )
                    )
                    .foregroundStyle(.secondary)

                Text("Выберите игру")
                    .font(.headline)

                Text(
                    "Справа появятся фотографии и видео из Album."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Media List

    private var mediaList: some View {
        List(mediaItems) { media in

            Button {
                selectedMedia = media

                Task {
                    await loadPreview(
                        for: media
                    )
                }

            } label: {

                HStack(spacing: 10) {

                    Image(
                        systemName:
                            isVideo(media)
                            ? "video"
                            : "photo"
                    )
                    .foregroundStyle(.secondary)

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {

                        Text(
                            mediaDisplayDate(media)
                        )
                        .lineLimit(1)

                        HStack(spacing: 6) {

                            Text(
                                isVideo(media)
                                ? "Видео"
                                : "Фото"
                            )

                            Text("•")

                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount:
                                        Int64(media.size),
                                    countStyle: .file
                                )
                            )
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                selectedMedia?.id == media.id
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewView: some View {

        if let media = selectedMedia {

            VStack(
                alignment: .leading,
                spacing: 0
            ) {

                previewHeader(media)

                if let exportStatus {

                    Text(exportStatus)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)

                } else if let exportError {

                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)
                }

                Divider()

                if isLoadingPreview {

                    loadingView(
                        "Загрузка медиа..."
                    )

                } else if let previewError {

                    errorView(
                        title: "Не удалось загрузить медиа",
                        message: previewError
                    ) {
                        Task {
                            await loadPreview(
                                for: media
                            )
                        }
                    }

                } else if isVideo(media) {

                    videoPreview

                } else if let previewImage {

                    VStack {
                        Spacer(minLength: 16)

                        Image(
                            nsImage: previewImage
                        )
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                        .padding(20)

                        Spacer(minLength: 16)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                } else {

                    VStack(spacing: 10) {

                        Image(systemName: "photo")
                            .font(
                                .system(
                                    size: 34,
                                    weight: .light
                                )
                            )
                            .foregroundStyle(.secondary)

                        Text("Превью недоступно")
                            .font(.headline)
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                }
            }

        } else {

            VStack(spacing: 10) {

                Image(systemName: "photo")
                    .font(
                        .system(
                            size: 32,
                            weight: .light
                        )
                    )
                    .foregroundStyle(.secondary)

                Text("Выберите фото или видео")
                    .font(.headline)

                Text(
                    "Здесь появится предварительный просмотр."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Video Preview

    @ViewBuilder
    private var videoPreview: some View {

        if let videoPlayer {

            VideoPlayer(
                player: videoPlayer
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .padding(20)

        } else {

            VStack(spacing: 12) {

                Image(systemName: "video")
                    .font(
                        .system(
                            size: 42,
                            weight: .light
                        )
                    )
                    .foregroundStyle(.secondary)

                Text("Видео недоступно")
                    .font(.headline)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    // MARK: - Preview Header

    private func previewHeader(
        _ media: InstallationCoordinator.SDCardItem
    ) -> some View {

        HStack {

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(
                    mediaDisplayDate(media)
                )
                .font(.headline)

                Text(media.name)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                exportSelectedMedia()
            } label: {
                Label(
                    "Сохранить на Mac",
                    systemImage:
                        "square.and.arrow.down"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedLocalURL == nil ||
                isLoadingPreview
            )
        }
        .padding()
    }

    // MARK: - Load Album Games

    @MainActor
    private func loadAlbumGames() async {

        guard !isLoadingGames else {
            return
        }

        isLoadingGames = true
        gamesError = nil

        selectedGame = nil
        mediaItems = []
        selectedMedia = nil

        cleanupPreview()

        do {

            guard
                let storage =
                    try await appState
                        .coordinator
                        .findMTPStorageViaHelper(
                            named: "Album"
                        )
            else {
                throw GalleryError.albumStorageNotFound
            }

            let items =
                try await appState
                    .coordinator
                    .browseMTPStorage(
                        storageId: storage.id,
                        path: "/"
                    )

            albumGames =
                items
                    .filter {
                        $0.isDirectory
                    }
                    .sorted {
                        $0.name
                            .localizedCaseInsensitiveCompare(
                                $1.name
                            ) == .orderedAscending
                    }

            appState.coordinator.log(
                "Sakura Gallery: найдено альбомов игр: \(albumGames.count)",
                level: .info
            )

        } catch {

            gamesError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Gallery: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingGames = false
    }

    // MARK: - Load Media

    @MainActor
    private func loadMedia(
        for game: InstallationCoordinator.SDCardItem
    ) async {

        guard !isLoadingMedia else {
            return
        }

        isLoadingMedia = true
        mediaError = nil

        mediaItems = []
        selectedMedia = nil

        cleanupPreview()

        do {

            guard
                let storage =
                    try await appState
                        .coordinator
                        .findMTPStorageViaHelper(
                            named: "Album"
                        )
            else {
                throw GalleryError.albumStorageNotFound
            }

            let items =
                try await appState
                    .coordinator
                    .browseMTPStorage(
                        storageId: storage.id,
                        path: "/\(game.name)"
                    )

            mediaItems =
                items
                    .filter {
                        !$0.isDirectory &&
                        (
                            isImage($0) ||
                            isVideo($0)
                        )
                    }
                    .sorted {
                        $0.name > $1.name
                    }

            appState.coordinator.log(
                "Sakura Gallery: \(game.name) — медиа: \(mediaItems.count)",
                level: .info
            )

        } catch {

            mediaError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Gallery: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingMedia = false
    }

    // MARK: - Load Preview

    @MainActor
    private func loadPreview(
        for media: InstallationCoordinator.SDCardItem
    ) async {

        guard
            !isLoadingPreview,
            let game = selectedGame
        else {
            return
        }

        isLoadingPreview = true

        previewError = nil
        exportStatus = nil
        exportError = nil

        cleanupPreview()

        do {

            guard
                let storage =
                    try await appState
                        .coordinator
                        .findMTPStorageViaHelper(
                            named: "Album"
                        )
            else {
                throw GalleryError.albumStorageNotFound
            }

            let tempDirectory =
                URL(
                    fileURLWithPath:
                        "/private/tmp/sakuraswitch_download_gallery_\(UUID().uuidString)",
                    isDirectory: true
                )

            try FileManager.default
                .createDirectory(
                    at: tempDirectory,
                    withIntermediateDirectories: true
                )

            let destination =
                tempDirectory
                    .appendingPathComponent(
                        media.name,
                        isDirectory: false
                    )

            try await appState
                .coordinator
                .downloadMTPFile(
                    storageId: storage.id,
                    directoryPath:
                        "/\(game.name)",
                    fileName: media.name,
                    destinationURL: destination
                )

            guard
                selectedMedia?.id == media.id
            else {
                try? FileManager.default
                    .removeItem(
                        at: tempDirectory
                    )

                isLoadingPreview = false
                return
            }

            previewTempDirectory =
                tempDirectory

            selectedLocalURL =
                destination

            if isImage(media) {

                guard
                    let image =
                        NSImage(
                            contentsOf: destination
                        )
                else {
                    throw GalleryError.imageDecodeFailed
                }

                previewImage =
                    image

                videoPlayer =
                    nil

            } else if isVideo(media) {

                previewImage =
                    nil

                let player =
                    AVPlayer(
                        url: destination
                    )

                videoPlayer =
                    player

            } else {

                previewImage =
                    nil

                videoPlayer =
                    nil
            }

            appState.coordinator.log(
                "Sakura Gallery: загружено \(media.name)",
                level: .info
            )

        } catch {

            previewError =
                error.localizedDescription

            appState.coordinator.log(
                "Ошибка Sakura Gallery Preview: \(error.localizedDescription)",
                level: .error
            )
        }

        isLoadingPreview = false
    }

    // MARK: - Export

    @MainActor
    private func exportSelectedMedia() {

        guard
            let source = selectedLocalURL,
            let media = selectedMedia
        else {
            return
        }

        let panel = NSSavePanel()

        panel.title =
            "Сохранить медиа из Sakura Gallery"

        panel.nameFieldStringValue =
            media.name

        panel.canCreateDirectories =
            true

        guard
            panel.runModal() == .OK,
            let destination = panel.url
        else {
            return
        }

        do {

            let fm =
                FileManager.default

            if fm.fileExists(
                atPath: destination.path
            ) {
                try fm.removeItem(
                    at: destination
                )
            }

            try fm.copyItem(
                at: source,
                to: destination
            )

            exportStatus =
                "Сохранено: \(destination.path)"

            exportError = nil

            appState.coordinator.log(
                "Sakura Gallery: экспортировано — \(destination.path)",
                level: .info
            )

        } catch {

            exportStatus = nil

            exportError =
                "Ошибка сохранения: \(error.localizedDescription)"
        }
    }

    // MARK: - Preview Cleanup

    @MainActor
    private func cleanupPreview() {

        videoPlayer?.pause()
        videoPlayer?.replaceCurrentItem(
            with: nil
        )
        videoPlayer = nil

        previewImage = nil
        selectedLocalURL = nil

        if let directory =
            previewTempDirectory {

            try? FileManager.default
                .removeItem(
                    at: directory
                )
        }

        previewTempDirectory = nil
    }

    // MARK: - Media Helpers

    private func isImage(
        _ item: InstallationCoordinator.SDCardItem
    ) -> Bool {

        let ext =
            URL(
                fileURLWithPath: item.name
            )
            .pathExtension
            .lowercased()

        return [
            "jpg",
            "jpeg",
            "png"
        ].contains(ext)
    }

    private func isVideo(
        _ item: InstallationCoordinator.SDCardItem
    ) -> Bool {

        let ext =
            URL(
                fileURLWithPath: item.name
            )
            .pathExtension
            .lowercased()

        return [
            "mp4",
            "mov"
        ].contains(ext)
    }

    private func mediaDisplayDate(
        _ item: InstallationCoordinator.SDCardItem
    ) -> String {

        let base =
            URL(
                fileURLWithPath: item.name
            )
            .deletingPathExtension()
            .lastPathComponent

        guard base.count >= 14 else {
            return item.name
        }

        let prefix =
            String(
                base.prefix(14)
            )

        let input =
            DateFormatter()

        input.locale =
            Locale(
                identifier: "en_US_POSIX"
            )

        input.dateFormat =
            "yyyyMMddHHmmss"

        guard
            let date =
                input.date(
                    from: prefix
                )
        else {
            return item.name
        }

        let output =
            DateFormatter()

        output.locale =
            Locale.current

        output.dateFormat =
            "dd.MM.yyyy HH:mm:ss"

        return output.string(
            from: date
        )
    }

    // MARK: - Loading / Error

    private func loadingView(
        _ text: String
    ) -> some View {

        VStack(spacing: 10) {

            ProgressView()

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .foregroundStyle(.orange)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button(
                "Повторить",
                action: retry
            )
        }
        .padding(24)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Errors

    private enum GalleryError:
        LocalizedError {

        case albumStorageNotFound
        case imageDecodeFailed

        var errorDescription: String? {

            switch self {

            case .albumStorageNotFound:
                return
                    "Хранилище Album не найдено. Убедитесь, что на Switch запущен DBI MTP responder."

            case .imageDecodeFailed:
                return
                    "Файл получен со Switch, но macOS не смогла декодировать изображение."
            }
        }
    }
}
