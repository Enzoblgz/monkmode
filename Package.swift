// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusLock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FocusLock",
            path: "Sources/FocusLock"
        )
    ]
)
