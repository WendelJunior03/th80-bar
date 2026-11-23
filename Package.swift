// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TH80Bar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TH80Bar",
            path: "Sources/TH80Bar",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        )
    ]
)
