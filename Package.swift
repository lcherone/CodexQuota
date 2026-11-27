// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexQuota", targets: ["CodexQuota"])
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .target(
            name: "CodexQuotaModel",
            dependencies: ["CodexQuotaCore"]
        ),
        .executableTarget(
            name: "CodexQuota",
            dependencies: ["CodexQuotaCore", "CodexQuotaModel"]
        ),
        .executableTarget(
            name: "CodexQuotaChecks",
            dependencies: ["CodexQuotaCore", "CodexQuotaModel"]
        )
    ]
)
