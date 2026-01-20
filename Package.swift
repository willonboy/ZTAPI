// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ZTAPI",
    platforms: [.macOS(.v11), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        .library(
            name: "ZTAPI",
            targets: ["ZTAPI"]
        ),
    ],
    dependencies: [
//        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2"),
//        .package(url: "https://github.com/willonboy/ZTJSON.git", from: "2.0.0"),
//        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.0")
    ],
    targets: [
//        .target(name: "ZTAPI", dependencies: ["ZTJSON", "SwiftyJSON", "Alamofire"]),
    ]
)
