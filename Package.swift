// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BtopDesktop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.99.3")),
    ],
    targets: [
        .executableTarget(
            name: "BtopDesktop",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/BtopDesktop"
        ),
    ]
)
