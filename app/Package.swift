// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowerView",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure decoding of PM5 / standard GATT payloads. No CoreBluetooth, so it's unit-testable.
        .target(name: "PowerProtocol"),
        // The chart's power trace. Pure logic, also unit-tested.
        .target(name: "RideCore"),
        .executableTarget(
            name: "PowerView",
            dependencies: ["PowerProtocol", "RideCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]  // CoreBluetooth delegates + AppKit; strict concurrency is noise here
        ),
        .testTarget(name: "PowerProtocolTests", dependencies: ["PowerProtocol"]),
        .testTarget(name: "RideCoreTests", dependencies: ["RideCore"]),
    ]
)
