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
  ],
  swiftLanguageModes: [.v6]
)
