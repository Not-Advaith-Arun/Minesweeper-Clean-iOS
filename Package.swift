// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Minesweeper",
  platforms: [
    .iOS(.v17),
    .macOS(.v13),
  ],
  products: [
    .library(name: "MinesweeperCore", targets: ["MinesweeperCore"])
  ],
  targets: [
    .target(
      name: "MinesweeperCore",
      path: "MinesweeperCore/Sources"
    ),
    .testTarget(
      name: "MinesweeperCoreTests",
      dependencies: ["MinesweeperCore"],
      path: "MinesweeperCoreTests"
    ),
  ],
  swiftLanguageModes: [.v6]
)
