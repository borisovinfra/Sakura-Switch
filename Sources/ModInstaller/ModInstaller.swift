import Foundation

@MainActor
public final class ModInstaller {

    public struct ModInfo: Sendable {
        public let titleID: String
        public let root: URL
        public let payloadRoot: URL

        public init(
            titleID: String,
            root: URL,
            payloadRoot: URL
        ) {
            self.titleID = titleID
            self.root = root
            self.payloadRoot = payloadRoot
        }
    }


    public enum ModError: Error {
        case invalidMod
        case titleIDNotFound
    }


    public init() {}


    public func analyze(url: URL) throws -> ModInfo {

        let name = url.lastPathComponent

        // 01009bf0072d4000/romfs
        if isTitleID(name) {

            return ModInfo(
                titleID: name.lowercased(),
                root: url,
                payloadRoot: url
            )
        }


        // contents/01009bf0072d4000
        if let idFolder = findTitleFolder(
            inside: url
        ) {

            return ModInfo(
                titleID: idFolder.lastPathComponent.lowercased(),
                root: url,
                payloadRoot: idFolder
            )
        }


        throw ModError.titleIDNotFound
    }



    public func install(
        mod: ModInfo,
        uploadDirectory: @escaping(URL, String) async throws -> Void,
        log: @escaping(String)->Void,
        progress: @escaping(String)->Void
    ) async throws {

        NSLog("🌸 MOD INSTALL ENTER DIRECT \(mod.titleID)")

        log("🌸 MOD INSTALL ENTER \(mod.titleID)")

        let destination =
            "/atmosphere/contents/\(mod.titleID)"

        progress(
            "📦 Подготовка установки"
        )

        log(
            "🌸 INSTALL TARGET \(destination)"
        )

        progress(
            "📤 Загрузка мода"
        )

        NSLog("🌸 CALL DIRECTORY UPLOAD \(mod.payloadRoot.path)")
        
        try await uploadDirectory(
            mod.payloadRoot,
            destination
        )

        NSLog("🌸 DIRECTORY UPLOAD RETURNED")

        progress(
            "✅ Мод установлен"
        )

        log(
            "🌸 INSTALL COMPLETE"
        )
    }



    private func findTitleFolder(
        inside url: URL
    ) -> URL? {


        guard let e = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil
        )
        else {
            return nil
        }


        for case let item as URL in e {

            if isTitleID(
                item.lastPathComponent
            ) {
                return item
            }
        }

        return nil
    }



    private func isTitleID(
        _ value:String
    ) -> Bool {

        value.range(
            of: "^[0-9A-Fa-f]{16}$",
            options: .regularExpression
        ) != nil
    }
}
