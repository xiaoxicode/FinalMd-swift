// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FinalMd",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FinalMd", targets: ["FinalMd"])
    ],
    targets: [
        .executableTarget(
            name: "FinalMd",
            path: "Sources/FinalMd",
            swiftSettings: [
                .define("FINALMD_NATIVE")
            ]
        )
    ]
)
