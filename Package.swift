// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Auth",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "Auth", targets: ["Auth"])],
  dependencies: [
    .package(
      url: "https://github.com/BK-Teisrud/SwiftNetworking.git",
      exact: "0.3.0")
  ],
  targets: [
    .target(
      name: "Auth",
      dependencies: [
        .product(name: "Networking", package: "SwiftNetworking")
      ]),
    .testTarget(name: "AuthTests", dependencies: ["Auth"]),
  ]
)
