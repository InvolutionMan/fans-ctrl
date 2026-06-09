// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FansCtrl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FansCtrl",
            path: "Sources"
        )
    ]
)
