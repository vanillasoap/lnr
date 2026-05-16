// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lnr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lnr",
            path: "Sources/lnr",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "lnrTests",
            dependencies: ["lnr"],
            path: "Tests/lnrTests"
        ),
    ]
)
