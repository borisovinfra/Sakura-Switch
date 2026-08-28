import SwiftUI

struct ApplicationsView: View {
    @Bindable var appState: AppState

    @State private var searchText = ""
    @State private var selectedCategory: HomebrewCategory = .all

    @State private var releases: [String: HomebrewRelease] = [:]
    @State private var unavailable: Set<String> = []
    @State private var isRefreshing = false
    @State private var installingAppID: String?
    @State private var eventMessage = L10n.proReady

    @State private var eventColor: Color = .secondary
private var filteredApplications: [HomebrewApp] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return HomebrewCatalog.applications.filter { app in
            let categoryMatches =
                selectedCategory == .all ||
                app.category == selectedCategory

            guard categoryMatches else {
                return false
            }

            guard !query.isEmpty else {
                return true
            }

            return app.name.lowercased().contains(query)
                || app.author.lowercased().contains(query)
                || app.description.lowercased().contains(query)
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.proTitle)
                            .font(.title2.bold())

                        Text(L10n.proSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await refreshReleases(forceRefresh: true)
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)

                    Text("PRO")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.22))
                        )
                }

                TextField(L10n.proSearch, text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(HomebrewCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Text(category.title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background {
                                        Capsule()
                                            .fill(
                                                selectedCategory == category
                                                ? Color.accentColor.opacity(0.28)
                                                : Color.secondary.opacity(0.12)
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredApplications) { app in
                            applicationRow(app)
                        }
                    }
                }

                HStack {
                    Text(L10n.proCount(filteredApplications.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker(
                        L10n.proInstallTo,
                        selection: .constant("SD Card")
                    ) {
                        Text("SD Card").tag("SD Card")
                        Text("NAND").tag("NAND")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            .padding(18)
            .frame(
                minWidth: 520,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.proEventLog)
                    .font(.headline)

                Divider()

                Text(eventMessage)
                .font(.caption)
                .foregroundStyle(eventColor)

                Spacer()
            }
            .padding(16)
            .frame(
                minWidth: 300,
                idealWidth: 340,
                maxWidth: 420,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .task {
            await refreshReleases(forceRefresh: false)
        }
    }

    @ViewBuilder
    private func applicationRow(_ app: HomebrewApp) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)

                Text(app.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(app.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let release = releases[app.id] {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(release.version)
                        .font(.caption)

                    Text(formatSize(release.size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    

                    Task {
                        await installApplication(
                            app: app,
                            release: release
                        )
                    }
                } label: {
                    if installingAppID == app.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.proInstall)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    installingAppID != nil ||
                    !HomebrewInstallService.canInstall(
                        release: release
                    )
                )

            } else if unavailable.contains(app.id) {
                Text(L10n.proUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }


    @MainActor
    private func installApplication(
        app: HomebrewApp,
        release: HomebrewRelease
    ) async {

        guard installingAppID == nil else {
            return
        }

        guard HomebrewInstallService.canInstall(
            release: release
        ) else {
            return
        }

        installingAppID = app.id
        eventColor = .secondary

        let installing = String(
            localized: "pro.install.generic.installing",
            bundle: .module
        )

        eventMessage =
            "\(installing): \(app.name)…"

        defer {
            installingAppID = nil
        }

        do {

            try await HomebrewInstallService.installRelease(
                release: release,
                coordinator: appState.coordinator
            )

            let success = String(
                localized: "pro.install.generic.success",
                bundle: .module
            )

            eventMessage =
                "\(success): \(app.name)"

            eventColor = .green

        } catch {

            let failed = String(
                localized: "pro.install.generic.failed",
                bundle: .module
            )

            eventMessage =
                "\(failed) \(app.name): \(error.localizedDescription)"

            eventColor = .red
        }
    }

    @MainActor
    private func refreshReleases(forceRefresh: Bool) async {

        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        eventColor = .secondary

        eventMessage = forceRefresh
            ? L10n.proLogChecking
            : L10n.proLogLoading

        if forceRefresh {

            do {

                let status =
                    try await HomebrewReleaseService.shared.githubRateLimitStatus()

                let required =
                    HomebrewCatalog.applications.count + 5

                guard status.remaining >= required else {

                    let resetTime = status.reset.formatted(
                        date: .omitted,
                        time: .shortened
                    )

                    eventMessage =
                        L10n.proLogDeferred(
                            resetTime,
                            status.remaining,
                            required
                        )

                    eventColor = .red

                    return
                }

            } catch {

                eventMessage =
                    L10n.proLogRateCheckFailed

                eventColor = .red

                return
            }
        }

        if !forceRefresh {
            unavailable.removeAll()
        }

        var loadedCount = 0

        for app in HomebrewCatalog.applications {

            do {

                let release =
                    try await HomebrewReleaseService.shared.latestRelease(

                        repository: app.repository,
                        assetRule: app.assetRule,
                        forceRefresh: forceRefresh
                    )

                releases[app.id] = release
                unavailable.remove(app.id)

                loadedCount += 1

            } catch {

                if !forceRefresh {
                    releases.removeValue(forKey: app.id)
                    unavailable.insert(app.id)
                }
            }
        }

        let total = HomebrewCatalog.applications.count

        if forceRefresh {

            if loadedCount == total {

                eventMessage =
                    L10n.proLogCatalogUpdated(loadedCount)

                eventColor = .green

            } else {

                eventMessage =
                    L10n.proLogCatalogUpdatedPartial(loadedCount, total)

                eventColor = .red
            }

        } else {

            if releases.count == total {

                eventMessage =
                    L10n.proLogCatalogLoaded(releases.count)

                eventColor = .green

            } else {

                eventMessage =
                    L10n.proLogCatalogLoadedPartial(releases.count, total)

                eventColor = .red
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
