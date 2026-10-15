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

        // A matching helper alone is not sufficient: libraries may change.
        if isInstalled,
           fm.contentsEqual(atPath: bundledHelper, andPath: installedPath),
           fm.contentsEqual(
               atPath: bundledLibmtp,
               andPath: "\(installedFrameworksPath)/\(libmtpName)"
           ),
           fm.contentsEqual(
               atPath: bundledLibusb,
               andPath: "\(installedFrameworksPath)/\(libusbName)"
           ) {
            return
        }

        // Stage and validate every component before touching installed files.
        // On any failure during commit, restore all previously installed files.
        let components: [(source: String, destination: String, name: String)] = [
            (bundledHelper, installedPath, "helper"),
            (bundledLibmtp, "\(installedFrameworksPath)/\(libmtpName)", "libmtp"),
            (bundledLibusb, "\(installedFrameworksPath)/\(libusbName)", "libusb")
        ]

        var steps: [String] = [
            "set -eu",
            "/bin/mkdir -p " + shellQuote("\(installRoot)/Helpers") +
                " " + shellQuote(installedFrameworksPath),
            "stage=$(/usr/bin/mktemp -d " +
                shellQuote("\(installRoot)/.mtp-update.XXXXXXXX") + ")",
            "commit_started=0"
        ]

        // This trap must not abort after the first failed restoration.
        // Keep staged backups when any restoration fails for manual recovery.
        var recovery: [String] = [
            "status=$?",
            "trap - EXIT",
            "set +e",
            "rollback_failed=0",
            "if [ \"$status\" -ne 0 ] && [ \"$commit_started\" -eq 1 ]; then"
        ]

        for component in components {
            let old = "$stage/old-\(component.name)"
            recovery.append(
                "if [ -f \"\(old)\" ]; then /bin/cp -p \"\(old)\" " +
                    shellQuote(component.destination) +
                    "; else /bin/rm -f " + shellQuote(component.destination) +
                    "; fi || rollback_failed=1"
            )
        }

        recovery.append(
            "if [ -f \"$stage/old-sudoers\" ]; then " +
                "/bin/cp -p \"$stage/old-sudoers\" " + shellQuote(sudoersPath) +
                "; else /bin/rm -f " + shellQuote(sudoersPath) +
                "; fi || rollback_failed=1"
        )
        recovery += [
            "fi",
            "if [ \"$rollback_failed\" -ne 0 ]; then",
            "  echo 'MTP UPDATE: ROLLBACK INCOMPLETE; backups preserved at' \"$stage\" >&2",
            "  exit 1",
            "fi",
            "/bin/rm -rf \"$stage\" || { echo 'MTP UPDATE: cleanup failed' >&2; exit 1; }",
            "exit \"$status\""
        ]
        steps.append("trap " + shellQuote(recovery.joined(separator: "\n")) + " EXIT")

        for component in components {
            steps.append(
                "/usr/bin/install -o root -g wheel -m 0755 " +
                    shellQuote(component.source) + " \"$stage/new-\(component.name)\""
            )
            steps.append(
                "/usr/bin/cmp -s " + shellQuote(component.source) +
                    " \"$stage/new-\(component.name)\""
            )
        }

        steps.append(
            "/usr/bin/printf '%s\\n' " + shellQuote(sudoersLine) +
                " > \"$stage/new-sudoers\""
        )
        steps += [
            "/usr/sbin/chown root:wheel \"$stage/new-sudoers\"",
            "/bin/chmod 0440 \"$stage/new-sudoers\"",
            "/usr/sbin/visudo -cf \"$stage/new-sudoers\""
        ]

        for component in components {
            steps.append(
                "if [ -f " + shellQuote(component.destination) +
                    " ]; then /bin/cp -p " + shellQuote(component.destination) +
                    " \"$stage/old-\(component.name)\"; fi"
            )
        }
        steps.append(
            "if [ -f " + shellQuote(sudoersPath) +
                " ]; then /bin/cp -p " + shellQuote(sudoersPath) +
                " \"$stage/old-sudoers\"; fi"
        )

        steps.append("commit_started=1")
        // Switch supporting libraries first, then sudoers, helper last.
        for component in components.dropFirst() {
            steps.append(
                "/bin/mv -f \"$stage/new-\(component.name)\" " +
                    shellQuote(component.destination)
            )
        }
        steps += [
            "/bin/mv -f \"$stage/new-sudoers\" " + shellQuote(sudoersPath),
            "/bin/mv -f \"$stage/new-helper\" " + shellQuote(installedPath)
        ]
        for component in components {
            steps.append(
                "/usr/bin/cmp -s " + shellQuote(component.source) +
                    " " + shellQuote(component.destination)
            )
        }
        steps.append("/usr/sbin/visudo -cf " + shellQuote(sudoersPath))

        let command = steps.joined(separator: "\n")

        try await runWithAdministratorPrivileges(command)

        guard isInstalled,
              fm.contentsEqual(atPath: bundledHelper, andPath: installedPath),
              fm.contentsEqual(
                  atPath: bundledLibmtp,
                  andPath: "\(installedFrameworksPath)/\(libmtpName)"
              ),
              fm.contentsEqual(
                  atPath: bundledLibusb,
                  andPath: "\(installedFrameworksPath)/\(libusbName)"
              )
        else {
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
