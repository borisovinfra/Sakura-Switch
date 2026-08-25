import Foundation

/// Runs a USB device claim operation with admin privileges via osascript.
/// This prompts the user for their password once, then the helper claims
/// the device and releases it for our process to use.
///
/// The approach: run a small Swift snippet as root that does DeviceCapture,
/// configures the device, and exits — releasing all kernel drivers.
/// Then our process can immediately open the device and interface.
public enum PrivilegedUSBClaim {

    /// Claim a USB device by VID/PID with admin privileges.
    /// Prompts the user for their admin password.
    /// After this returns, the device is available for normal IOUSBHost access.
    public static func claimDevice(vendorID: UInt16, productID: UInt16) async throws {
        guard vendorID == 0x057E, productID == 0x201D else {
            throw IOUSBHostError.claimFailed("Unsupported USB device")
        }

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = [
                    "-n",
                    "/usr/local/libexec/sakuraswitch-mtp-helper",
                    "--claim-only"
                ]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 && output.contains("OK") {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: IOUSBHostError.claimFailed(output)
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runOsascript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: IOUSBHostError.claimFailed(output))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
