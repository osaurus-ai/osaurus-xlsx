// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-xlsx",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-xlsx", type: .dynamic, targets: ["osaurus_xlsx"])
    ],
    targets: [
        .target(
            name: "osaurus_xlsx",
            path: "Sources/osaurus_xlsx"
        ),
        .testTarget(
            name: "osaurus_xlsx_tests",
            dependencies: ["osaurus_xlsx"],
            path: "Tests/osaurus_xlsx_tests"
        )
    ]
)