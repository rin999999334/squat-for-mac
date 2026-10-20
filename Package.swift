// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SquatForMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SquatForMac", targets: ["SquatForMac"])
    ],
    targets: [
        .executableTarget(
            name: "SquatForMac",
            resources: [.copy("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
