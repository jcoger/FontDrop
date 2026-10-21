// swift-tools-version:6.0
// FontDrop macOS spike. Build with macos/build.sh (it runs core/build-swift.sh first
// if the generated XCFramework is missing).
import PackageDescription

let package = Package(
    name: "FontDrop",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "FontDropCore")],
    targets: [
        .executableTarget(
            name: "FontDrop",
            dependencies: [.product(name: "FontDropCore", package: "FontDropCore")],
            path: "Sources/FontDrop"
        )
    ]
)
