// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFKitStructureTreeProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "StructureTreeProbe", path: "Sources/StructureTreeProbe"),
    ]
)
