// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "PlatformSmokeFixture",
                      platforms: [.macOS(.v15), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
                      dependencies: [.package(name: "Rundown", path: "../..")],
                      targets: [
                        .testTarget(name: "XCTestSmokeTests",
                                    dependencies: [.product(name: "Rundown", package: "Rundown")]),
                        .testTarget(name: "SwiftTestingSmokeTests",
                                    dependencies: [.product(name: "RundownSwiftTesting", package: "Rundown")]),
                      ])
