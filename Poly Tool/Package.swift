// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PolyTool", platforms: [.macOS(.v14)], products: [
    .library(name: "PolyCore", targets: ["PolyCore"])
], targets: [.target(name: "PolyCore"), .testTarget(name: "PolyCoreTests", dependencies: ["PolyCore"])])
