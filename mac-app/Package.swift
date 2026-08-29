// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MagicPen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MagicPen",
            resources: [
                .copy("Resources/logo.png"),
                .copy("Resources/arrow.png"),
                .copy("Resources/eye.png")
            ]
        )
    ]
)
