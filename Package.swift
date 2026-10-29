// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Minutes",
  platforms: [.macOS("15.0")],
  products: [.executable(name: "Minutes", targets: ["Minutes"])],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
  ],
  targets: [
    .target(name: "MinutesCore"),
    .executableTarget(
      name: "Minutes",
      dependencies: [
        "MinutesCore", .product(name: "FluidAudio", package: "FluidAudio"),
        .product(name: "Sparkle", package: "Sparkle"),
      ]),
    .testTarget(name: "MinutesCoreTests", dependencies: ["MinutesCore"]),
    .testTarget(name: "MinutesTests", dependencies: ["Minutes"]),
  ]
)
