// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Cuts",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cuts",
            path: "Sources/Cuts"
        )
    ]
)
