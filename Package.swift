// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Minutes",
  platforms: [.macOS("15.0")],
  products: [.executable(name: "Minutes", targets: ["Minutes"])],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.12.4")
  ],
  targets: [
    .target(name: "MinutesCore"),
    .executableTarget(
      name: "Minutes",
      dependencies: ["MinutesCore", .product(name: "FluidAudio", package: "FluidAudio")]),
    .testTarget(name: "MinutesCoreTests", dependencies: ["MinutesCore"]),
    .testTarget(name: "MinutesTests", dependencies: ["Minutes"]),
  ]
)
