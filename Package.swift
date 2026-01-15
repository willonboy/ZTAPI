// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ZTAPI",
    platforms: [.macOS(.v11), .iOS(.v14), .tvOS(.v14), .watchOS(.v7), .macCatalyst(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ZTAPI",
            targets: ["ZTAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2"),
        .package(url: "https://github.com/willonboy/ZTJSON.git", from: "2.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        
        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "ZTAPI", dependencies: ["ZTJSON", "SwiftyJSON", "Alamofire"]),
    ]
)
