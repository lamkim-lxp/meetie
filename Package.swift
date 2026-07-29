// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Meetie",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Meetie",
            path: "Sources/Meetie",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MeetieTests",
            dependencies: ["Meetie"],
            path: "Tests/MeetieTests"
        )
    ]
)
