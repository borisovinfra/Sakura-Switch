import Foundation

struct HomebrewRelease: Codable, Sendable {
    let version: String
    let size: Int64
    let downloadURL: URL
    let assetName: String
}

enum HomebrewReleaseError: Error {
    case invalidRepository
    case badResponse
    case noCompatibleAsset
    case rateLimited
}

struct GitHubRateLimitStatus: Sendable {
    let remaining: Int
    let reset: Date
}

actor HomebrewReleaseService {
    static let shared = HomebrewReleaseService()

    // Не опрашиваем один и тот же release чаще одного раза в 6 часов.
    private let cacheLifetime: TimeInterval = 6 * 60 * 60

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let size: Int64
        let browser_download_url: URL
    }

    private struct CacheEntry: Codable {
        let release: HomebrewRelease
        let etag: String?
        var fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private var cacheLoaded = false

    private var cacheURL: URL {
        let fm = FileManager.default

        let base = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let directory = base
            .appendingPathComponent("Sakura Switch", isDirectory: true)

        try? fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory.appendingPathComponent(
            "homebrew-release-cache.json"
        )
    }

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true

        guard let data = try? Data(contentsOf: cacheURL) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode(
            [String: CacheEntry].self,
            from: data
        ) else {
            return
        }

        cache = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }

        try? data.write(
            to: cacheURL,
            options: .atomic
        )
    }

    private func cacheKey(
        repository: String,
        assetRule: HomebrewAssetRule
    ) -> String {
        "\(repository.lowercased())|\(assetRule.cacheIdentifier)"
    }

    func githubRateLimitStatus() async throws -> GitHubRateLimitStatus {

        guard let url = URL(string: "https://api.github.com/rate_limit") else {
            throw HomebrewReleaseError.badResponse
        }

        var request = URLRequest(url: url)

        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )

        request.setValue(
            "SakuraSwitch/1.1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw HomebrewReleaseError.badResponse
        }

        struct RateLimitResponse: Decodable {

            struct Resources: Decodable {

                struct Core: Decodable {
                    let remaining: Int
                    let reset: Int
                }

                let core: Core
            }

            let resources: Resources
        }

        let result = try JSONDecoder().decode(
            RateLimitResponse.self,
            from: data
        )

        return GitHubRateLimitStatus(
            remaining: result.resources.core.remaining,
            reset: Date(
                timeIntervalSince1970:
                    TimeInterval(result.resources.core.reset)
            )
        )
    }

    func latestRelease(
        repository: String,
        assetRule: HomebrewAssetRule,
        forceRefresh: Bool = false
    ) async throws -> HomebrewRelease {
        loadCacheIfNeeded()

        let key = cacheKey(
            repository: repository,
            assetRule: assetRule
        )

        let cached = cache[key]

        // Обычный запуск Sakura не обращается к GitHub.
        // Сначала локальный cache, затем встроенный manifest.
        if !forceRefresh {
            if let cached {
                return cached.release
            }

            if let bootstrap = HomebrewBootstrapCatalog.release(
                forKey: key
            ) {
                return bootstrap
            }
        }

        let parts = repository.split(separator: "/")

        guard parts.count == 2 else {
            throw HomebrewReleaseError.invalidRepository
        }

        let owner = String(parts[0])
        let repo = String(parts[1])

        guard let url = URL(
            string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        ) else {
            throw HomebrewReleaseError.invalidRepository
        }

        var request = URLRequest(url: url)

        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )

        request.setValue(
            "SakuraSwitch/1.1.0",
            forHTTPHeaderField: "User-Agent"
        )

        if let etag = cached?.etag {
            request.setValue(
                etag,
                forHTTPHeaderField: "If-None-Match"
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                if let cached {
                    return cached.release
                }

                throw HomebrewReleaseError.badResponse
            }

            switch http.statusCode {
            case 200:
                let githubRelease = try JSONDecoder().decode(
                    GitHubRelease.self,
                    from: data
                )

                guard let asset = githubRelease.assets.first(where: {
                    assetRule.matches($0.name)
                }) else {
                    // GitHub ответил свежими данными, но ожидаемого
                    // Switch asset нет. Старый asset не подсовываем.
                    throw HomebrewReleaseError.noCompatibleAsset
                }

                let release = HomebrewRelease(
                    version: githubRelease.tag_name,
                    size: asset.size,
                    downloadURL: asset.browser_download_url,
                    assetName: asset.name
                )

                cache[key] = CacheEntry(
                    release: release,
                    etag: http.value(
                        forHTTPHeaderField: "ETag"
                    ),
                    fetchedAt: Date()
                )

                saveCache()

                return release

            case 304:
                guard var cached else {
                    throw HomebrewReleaseError.badResponse
                }

                cached.fetchedAt = Date()
                cache[key] = cached
                saveCache()

                return cached.release

            case 403, 429:
                // При исчерпанном GitHub API не ломаем каталог,
                // если у Sakura уже есть проверенные данные.
                if let cached {
                    return cached.release
                }

                throw HomebrewReleaseError.rateLimited

            default:
                if let cached {
                    return cached.release
                }

                throw HomebrewReleaseError.badResponse
            }

        } catch let error as HomebrewReleaseError {
            throw error

        } catch {
            // Нет сети / timeout / временная проблема GitHub.
            if let cached {
                return cached.release
            }

            throw error
        }
    }
}
