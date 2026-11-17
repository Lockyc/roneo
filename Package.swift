// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "roneo",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "RoneoCore"),
        .target(name: "RoneoPDF", linkerSettings: [.linkedFramework("PDFKit")]),
        .executableTarget(name: "Roneo", dependencies: ["RoneoCore", "RoneoPDF", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "RoneoCoreTests", dependencies: ["RoneoCore"]),
        .testTarget(name: "RoneoPDFTests", dependencies: ["RoneoPDF"]),
    ],
    swiftLanguageModes: [.v5]
)
