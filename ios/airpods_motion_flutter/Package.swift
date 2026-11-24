// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "airpods_motion_flutter",
  platforms: [
    .iOS("14.0")
  ],
  products: [
    .library(name: "airpods-motion-flutter", targets: ["airpods_motion_flutter"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "airpods_motion_flutter",
      dependencies: []
    )
  ]
)
