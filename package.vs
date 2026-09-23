// The 'io' package: the protocols everything that moves bytes conforms to,
// and the functions and adapters that work over any of them.
import PackageDescription

let package = Package(
    name: "io",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "io", targets: ["io"]),
        .executable(name: "check", targets: ["check"]),
    ],
    targets: [
        // No native target: io moves nothing itself. The packages that own
        // handles (fs, net, os) conform their types to its protocols.
        .target(
            name: "io",
            path: "io"
        ),
        .executableTarget(
            name: "check",
            dependencies: ["io"],
            path: "tests/check"
        ),
    ]
)
