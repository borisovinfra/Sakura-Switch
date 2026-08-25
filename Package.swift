// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SakuraSwitch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SakuraSwitch", targets: ["SakuraSwitch"])
    ],
    targets: [
        // C Bridge — wraps libusb for Swift import
        .systemLibrary(
            name: "CLibUSB",
            pkgConfig: "libusb-1.0",
            providers: [.brew(["libusb"])]
        ),

        // Infrastructure — USB device communication
        .target(
            name: "USBTransport",
            dependencies: ["CLibUSB", "DBIProtocol"]
        ),

        // C Bridge — wraps libmtp for Swift import
        .systemLibrary(
            name: "CLibMTP",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"])]
        ),

        // Domain — DBI protocol encode/decode and command handling
        .target(
            name: "DBIProtocol"
        ),

        // Infrastructure — MTP device communication
        .target(
            name: "MTPTransport",
            dependencies: ["CLibMTP", "DBIProtocol"]
        ),

        // Infrastructure — Native MTP via IOUSBHost (replaces libmtp)
        .target(
            name: "NativeMTPTransport",
            dependencies: ["DBIProtocol", "MTPTransport"]
        ),

        // Infrastructure — HTTP network file server
        .target(
            name: "NetworkTransport",
            dependencies: ["DBIProtocol"]
        ),

        // Domain — mod installation engine
        .target(
            name: "ModInstaller"
        ),

        // Orchestration — wires protocol + USB + MTP + Network + file serving
        .target(
            name: "Installer",
            dependencies: [
                "USBTransport",
                "DBIProtocol",
                "MTPTransport",
                "NativeMTPTransport",
                "NetworkTransport",
                "ModInstaller"
            ]
        ),

        // Presentation — SwiftUI app
        .executableTarget(
            name: "SakuraSwitch",
            dependencies: ["Installer"],
            resources: [
                .copy("Resources")
            ]
        ),

        // Tests
        .testTarget(
            name: "USBTransportTests",
            dependencies: ["USBTransport", "DBIProtocol"]
        ),
        .testTarget(
            name: "DBIProtocolTests",
            dependencies: ["DBIProtocol"]
        ),
        .testTarget(
            name: "InstallerTests",
            dependencies: ["Installer"]
        ),
        .testTarget(
            name: "MTPTransportTests",
            dependencies: ["MTPTransport", "DBIProtocol"]
        ),
        .testTarget(
            name: "NativeMTPTransportTests",
            dependencies: ["NativeMTPTransport", "MTPTransport"]
        ),
        .testTarget(
            name: "NetworkTransportTests",
            dependencies: ["NetworkTransport"]
        ),
        .testTarget(
            name: "SakuraSwitchTests",
            dependencies: ["SakuraSwitch", "NativeMTPTransport"]
        ),
    ]
)
