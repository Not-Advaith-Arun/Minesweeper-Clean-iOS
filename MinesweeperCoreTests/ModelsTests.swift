import Foundation
import XCTest

@testable import MinesweeperCore

final class ModelsTests: XCTestCase {
  func testDifficultyConfigurationsMatchProductSpecification() {
    XCTAssertEqual(
      Difficulty.beginner.configuration, BoardConfiguration(width: 12, height: 22, mineCount: 12))
    XCTAssertEqual(
      Difficulty.easy.configuration, BoardConfiguration(width: 7, height: 10, mineCount: 10))
    XCTAssertEqual(
      Difficulty.medium.configuration, BoardConfiguration(width: 12, height: 22, mineCount: 40))
    XCTAssertEqual(
      Difficulty.hard.configuration, BoardConfiguration(width: 18, height: 32, mineCount: 100))
    XCTAssertEqual(
      Difficulty.huge.configuration, BoardConfiguration(width: 27, height: 48, mineCount: 220))
    XCTAssertEqual(
      Difficulty.extreme.configuration, BoardConfiguration(width: 18, height: 32, mineCount: 150))
  }

  func testCoordinateIndexRoundTripAndNeighbors() {
    let configuration = BoardConfiguration(width: 4, height: 3, mineCount: 2)
    for index in 0..<configuration.cellCount {
      let coordinate = try! XCTUnwrap(configuration.coordinate(for: index))
      XCTAssertEqual(configuration.index(for: coordinate), index)
    }
    XCTAssertEqual(
      Set(configuration.neighbors(of: CellCoordinate(row: 0, column: 0))),
      [
        CellCoordinate(row: 0, column: 1), CellCoordinate(row: 1, column: 0),
        CellCoordinate(row: 1, column: 1),
      ]
    )
    XCTAssertEqual(configuration.neighbors(of: CellCoordinate(row: 1, column: 1)).count, 8)
    XCTAssertNil(configuration.index(for: CellCoordinate(row: -1, column: 0)))
  }

  func testSettingsClampRangesAndEnforceToggleDependency() {
    let settings = GameSettings(
      showsActionToggle: false,
      longPressEnabled: false,
      longPressDelayMilliseconds: 20,
      animationSpeedPercent: 999,
      vibrationDurationMilliseconds: 1
    )
    XCTAssertTrue(settings.showsActionToggle)
    XCTAssertEqual(settings.longPressDelayMilliseconds, 100)
    XCTAssertEqual(settings.animationSpeedPercent, 150)
    XCTAssertEqual(settings.vibrationDurationMilliseconds, 5)
  }

  func testModelsRoundTripThroughJSON() throws {
    let original = SettingsState(
      settings: GameSettings(defaultAction: .flag, easyFlaggingEnabled: true),
      selectedTheme: "retro-cyan-amoled"
    )
    let data = try JSONEncoder().encode(original)
    XCTAssertEqual(try JSONDecoder().decode(SettingsState.self, from: data), original)
  }

  func testCoordinateComparableUsesReadingOrder() {
    let values = [
      CellCoordinate(row: 2, column: 0),
      CellCoordinate(row: 0, column: 4),
      CellCoordinate(row: 0, column: 1),
    ]
    XCTAssertEqual(
      values.sorted(),
      [
        CellCoordinate(row: 0, column: 1),
        CellCoordinate(row: 0, column: 4),
        CellCoordinate(row: 2, column: 0),
      ])
  }
}
