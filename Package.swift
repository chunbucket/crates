// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Crates",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Crates",
            path: "Sources/Crates"
        )
    ]
)
