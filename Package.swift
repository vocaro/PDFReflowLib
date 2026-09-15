// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PDFReflowLib",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "PDFReflowLib", targets: ["PDFReflowLib"]),
        .executable(name: "pdf-reflow", targets: ["PDFReflowLibCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(name: "PDFReflowLib", dependencies: ["ZIPFoundation"], path: "Sources/PDFReflowLib"),
        .executableTarget(name: "PDFReflowLibCLI", dependencies: ["PDFReflowLib"]),
        .testTarget(name: "PDFReflowLibTests", dependencies: ["PDFReflowLib", "ZIPFoundation"],
                    resources: [.copy("fixtures")]),
    ]
)
