// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StayAwakeDaemon",
    targets: [
        .executableTarget(name: "StayAwakeDaemon", path: "Sources/StayAwakeDaemon")
    ]
)
