// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Auth",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "Auth", targets: ["Auth"])],
  dependencies: [
    .package(
      url: "https://github.com/BK-Teisrud/SwiftNetworking.git",
      revision: "54fa46cb140de470d6cffe6ba5c691d56e677298")
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
