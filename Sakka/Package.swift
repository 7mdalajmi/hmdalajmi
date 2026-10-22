// swift-tools-version: 6.2
// The rules of الهند and البلوت without any UI, so `swift test` checks them on Linux or a Mac without Xcode.
// The same files are compiled into the app by the synchronized folder Sakka/, and SakkaTests runs in Xcode too.
import PackageDescription

let package = Package(
    name: "SakkaRules",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "SakkaRules", targets: ["SakkaRules"])],
    targets: [
        .target(
            name: "SakkaRules",
            path: "Sakka/Rules",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "SakkaTests",
            dependencies: ["SakkaRules"],
            path: "SakkaTests",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
