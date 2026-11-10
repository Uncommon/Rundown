// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ExternalSpecFixture",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "Rundown", path: "../..")],
    targets: [
        .testTarget(
            name: "ExternalSpecFixtureTests",
            dependencies: [.product(name: "RundownSwiftTesting", package: "Rundown")]
        )
    ]
)
