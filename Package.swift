// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let headerPath: [CXXSetting] = [.headerSearchPath("include"), .headerSearchPath("src")]

let package = Package(
    name: "DLAB",
    platforms: [.macOS(.v10_14)],
    products: [
        .library(name: "DLABCapture", targets: ["DLABCapture"]),
        .library(name: "DLABCore", targets: ["DLABCore"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(name: "DLABCapture", dependencies: ["DLABCore"]),
        .testTarget(name: "DLABCaptureTests", dependencies: ["DLABCapture"]),
        .target(name: "DLABCore", dependencies: ["DLABridging"]),
        .target(name: "DLABridging", dependencies: ["DLABridgingCpp"], cxxSettings: headerPath),
        .target(name: "DLABridgingCpp", dependencies: ["DeckLinkAPI"]),
        .target(name: "DeckLinkAPI"),
        .testTarget(name: "DLABCoreTests", dependencies: ["DLABCore"]),
    ]
    
    , swiftLanguageVersions: [.v5]
    , cLanguageStandard: .c18
    , cxxLanguageStandard: .cxx17
)
