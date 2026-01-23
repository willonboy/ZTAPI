// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ZTAPI",
    platforms: [.macOS(.v11), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        .library(
            name: "ZTAPI",
            targets: ["ZTAPICore", "ZTAPIXPath", "ZTAPIParamMacro"]
        ),
        .library(
            name: "ZTAPICore",
            targets: ["ZTAPICore"]
        ),
        .library(
            name: "ZTAPIXPath",
            targets: ["ZTAPIXPath"]
        ),
        .library(
            name: "ZTAPIParamMacro",
            targets: ["ZTAPIParamMacro"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/willonboy/ZTJSON.git", from: "2.1.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0-latest")
    ],
    targets: [
        .target(
            name: "ZTAPICore",
            dependencies: [],
            path: "Sources/ZTAPICore"
        ),
        .target(
            name: "ZTAPIXPath",
            dependencies: [
                "ZTAPICore",
                .product(name: "ZTJSON", package: "ZTJSON"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON")
            ],
            path: "Sources/ZTAPIXPath"
        ),
        .macro(
            name: "ZTAPIParamMacros",
            dependencies: [
                "ZTAPICore",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/ZTAPIParamMacros"
        ),
        .target(
            name: "ZTAPIParamMacro",
            dependencies: ["ZTAPICore", "ZTAPIParamMacros"],
            path: "Sources/ZTAPIParamMacro"
        ),
    ]
)
