// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "monkmode",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "monkmode",
            path: "Sources/monkmode"
        )
    ]
)
