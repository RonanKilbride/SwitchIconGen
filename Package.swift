// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwitchIconGen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwitchIconGen", targets: ["SwitchIconGen"]),
    ],
    targets: [
        .target(
            name: "SwitchIconGenKit",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "SwitchIconGen",
            dependencies: ["SwitchIconGenKit"]
        ),
    ]
)
