// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriveQuizKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DriveQuizKit", targets: ["DriveQuizKit"])
    ],
    targets: [
        .target(name: "DriveQuizKit"),
        .testTarget(name: "DriveQuizKitTests", dependencies: ["DriveQuizKit"])
    ]
)
