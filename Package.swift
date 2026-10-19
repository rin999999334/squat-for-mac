// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ThinkAndMove", platforms: [.macOS(.v13)], products: [.executable(name: "ThinkAndMove", targets: ["ThinkAndMove"])], targets: [.executableTarget(name: "ThinkAndMove", resources: [.copy("Resources")], linkerSettings: [.linkedLibrary("sqlite3")])])
