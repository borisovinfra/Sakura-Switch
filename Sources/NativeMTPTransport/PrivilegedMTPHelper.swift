import Foundation

public enum PrivilegedMTPHelper {

    public static let installRoot =
        "/Library/PrivilegedHelperTools/SakuraSwitch"

    public static let installedPath =
        "/Library/PrivilegedHelperTools/SakuraSwitch/Helpers/sakuraswitch-mtp-helper"

    public static let installedFrameworksPath =
        "/Library/PrivilegedHelperTools/SakuraSwitch/Frameworks"

    public static let sudoersPath =
        "/etc/sudoers.d/sakuraswitch-mtp-helper"

    private static let helperName =
        "sakuraswitch-mtp-helper"

    private static let libmtpName =
        "libmtp.9.dylib"

    private static let libusbName =
        "libusb-1.0.0.dylib"

    public static var bundledPath: String? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent(helperName)
            .path
    }

    private static var bundledFrameworksPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Frameworks")
            .path
    }

    public static var isInstalled: Bool {
        let fm = FileManager.default

        return
            fm.isExecutableFile(atPath: installedPath) &&
            fm.fileExists(
                atPath:
                    "\(installedFrameworksPath)/\(libmtpName)"
            ) &&
            fm.fileExists(
                atPath:
                    "\(installedFrameworksPath)/\(libusbName)"
            ) &&
            fm.fileExists(atPath: sudoersPath)
    }

    /// Installs the bundled privileged MTP runtime.
    ///
    /// macOS presents its standard administrator authorization dialog.
    /// Installation is required only once unless the helper is missing.
    public static func installIfNeeded() async throws {

        if isInstalled {
            return
        }

        guard let bundledHelper = bundledPath else {
            throw HelperError.bundledHelperMissing
        }

        let fm = FileManager.default

        guard fm.isExecutableFile(atPath: bundledHelper) else {
            throw HelperError.bundledHelperMissing
        }

        let bundledLibmtp =
            "\(bundledFrameworksPath)/\(libmtpName)"

        let bundledLibusb =
            "\(bundledFrameworksPath)/\(libusbName)"

        guard
            fm.fileExists(atPath: bundledLibmtp),
            fm.fileExists(atPath: bundledLibusb)
        else {
            throw HelperError.bundledFrameworksMissing
        }

        let userName = NSUserName()

        let sudoersLine =
            "\(userName) ALL=(root) NOPASSWD: \(installedPath) *"

        let command = [
            "/bin/mkdir -p",
            shellQuote("\(installRoot)/Helpers"),
            shellQuote(installedFrameworksPath),
            "&&",

            "/usr/bin/install -o root -g wheel -m 0755",
            shellQuote(bundledHelper),
            shellQuote(installedPath),
            "&&",

            "/usr/bin/install -o root -g wheel -m 0755",
            shellQuote(bundledLibmtp),
            shellQuote("\(installedFrameworksPath)/\(libmtpName)"),
            "&&",

            "/usr/bin/install -o root -g wheel -m 0755",
            shellQuote(bundledLibusb),
            shellQuote("\(installedFrameworksPath)/\(libusbName)"),
            "&&",

            "/usr/bin/printf '%s\\n'",
            shellQuote(sudoersLine),
            ">",
            shellQuote(sudoersPath),
            "&&",

            "/usr/sbin/chown root:wheel",
            shellQuote(sudoersPath),
            "&&",

            "/bin/chmod 0440",
            shellQuote(sudoersPath),
            "&&",

            "/usr/sbin/visudo -cf",
            shellQuote(sudoersPath)
        ].joined(separator: " ")

        try await runWithAdministratorPrivileges(command)

        guard isInstalled else {
            throw HelperError.installationFailed
        }
    }

    private static func runWithAdministratorPrivileges(
        _ command: String
    ) async throws {

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in

            DispatchQueue.global(qos: .userInitiated).async {

                let escaped =
                    command.replacingOccurrences(
                        of: "\\",
                        with: "\\\\"
                    )
                    .replacingOccurrences(
                        of: "\"",
                        with: "\\\""
                    )

                let appleScript =
                    "do shell script \"\(escaped)\" " +
                    "with administrator privileges"

                let process = Process()

                process.executableURL =
                    URL(fileURLWithPath: "/usr/bin/osascript")

                process.arguments = [
                    "-e",
                    appleScript
                ]

                let pipe = Pipe()

                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data =
                        pipe.fileHandleForReading
                            .readDataToEndOfFile()

                    let output =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? ""

                    guard process.terminationStatus == 0 else {
                        throw HelperError.authorizationFailed(
                            output
                        )
                    }

                    continuation.resume()

                } catch {
                    continuation.resume(
                        throwing: error
                    )
                }
            }
        }
    }

    private static func shellQuote(
        _ value: String
    ) -> String {

        "'" +
        value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) +
        "'"
    }

    public enum HelperError: LocalizedError {

        case bundledHelperMissing
        case bundledFrameworksMissing
        case authorizationFailed(String)
        case installationFailed

        public var errorDescription: String? {
            switch self {

            case .bundledHelperMissing:
                return
                    "Встроенный MTP helper не найден."

            case .bundledFrameworksMissing:
                return
                    "Встроенные библиотеки MTP не найдены."

            case .authorizationFailed(let output):
                if output.isEmpty {
                    return
                        "Не удалось получить права администратора."
                }

                return output

            case .installationFailed:
                return
                    "MTP helper не был установлен."
            }
        }
    }
}
