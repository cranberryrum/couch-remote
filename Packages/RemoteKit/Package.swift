// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemoteKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "RemoteKit", targets: ["RemoteKit"]),
    ],
    targets: [
        .target(name: "RemoteKit"),
        .testTarget(name: "RemoteKitTests", dependencies: ["RemoteKit"]),
    ]
)
