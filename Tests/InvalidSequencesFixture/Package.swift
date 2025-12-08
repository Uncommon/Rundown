// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InvalidSequences",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "InvalidSequences",
            targets: ["InvalidSequences"]
        ),
    ],
    dependencies: [
        .package(name: "Rundown", path: "../..")
    ],
    targets: [
        .target(
            name: "InvalidSequences",
            dependencies: [
                .product(name: "Rundown", package: "Rundown")
            ]
        )
    ]
)
