import Foundation
import XCTest

@testable import MinesweeperCore

final class GameEngineTests: XCTestCase {
  private func board(width: Int = 3, height: Int = 3, mines: Set<CellCoordinate>) -> GeneratedBoard
  {
    GeneratedBoard(
      configuration: BoardConfiguration(width: width, height: height, mineCount: mines.count),
      seed: 7,
      mines: mines
    )
  }

  func testFlaggingTogglesAndUpdatesCounter() throws {
    let mine = CellCoordinate(row: 0, column: 0)
    var game = GameEngine(board: board(mines: [mine]), difficulty: .easy, phase: .playing)
    XCTAssertEqual(game.remainingMineCount, 1)
    let placed = try game.toggleFlag(at: mine)
    XCTAssertTrue(placed.didChange)
    XCTAssertTrue(game.cell(at: mine)!.isFlagged)
    XCTAssertEqual(game.remainingMineCount, 0)
    _ = try game.toggleFlag(at: mine)
    XCTAssertFalse(game.cell(at: mine)!.isFlagged)
  }

  func testFlagsMayExceedMineCountAndCounterBecomesNegative() throws {
    let mine = CellCoordinate(row: 0, column: 0)
    var game = GameEngine(board: board(mines: [mine]), difficulty: .easy, phase: .playing)
    _ = try game.toggleFlag(at: CellCoordinate(row: 1, column: 1))
    _ = try game.toggleFlag(at: CellCoordinate(row: 2, column: 2))
    XCTAssertEqual(game.flaggedCellCount, 2)
    XCTAssertEqual(game.remainingMineCount, -1)
  }

  func testDiggingAFlaggedCellIsANoOp() throws {
    let coordinate = CellCoordinate(row: 1, column: 1)
    var game = GameEngine(
      board: board(mines: [CellCoordinate(row: 0, column: 0)]),
      difficulty: .easy,
      phase: .playing
    )
    _ = try game.toggleFlag(at: coordinate)
    let result = try game.reveal(at: coordinate)
    XCTAssertFalse(result.didChange)
    XCTAssertTrue(game.cell(at: coordinate)!.isFlagged)
    XCTAssertFalse(game.cell(at: coordinate)!.isRevealed)
  }

  func testFirstRevealProtectsNeighborhoodAndKeepsExistingFlags() throws {
    let opening = CellCoordinate(row: 5, column: 3)
    let flag = CellCoordinate(row: 0, column: 0)
    var game = GameEngine(difficulty: .easy, seed: 0xC1EA)
    _ = try game.toggleFlag(at: flag)
    _ = try game.reveal(at: opening)

    XCTAssertTrue(game.cell(at: flag)!.isFlagged)
    XCTAssertFalse(game.cell(at: opening)!.isMine)
    XCTAssertTrue(
      game.configuration.neighbors(of: opening).allSatisfy {
        game.cell(at: $0)?.isMine == false
      })
  }

  func testZeroFloodRevealWinsWhenAllSafeCellsConnect() throws {
    var game = GameEngine(
      board: board(width: 4, height: 4, mines: [CellCoordinate(row: 0, column: 0)]),
      difficulty: .easy,
      phase: .playing
    )
    let result = try game.reveal(at: CellCoordinate(row: 3, column: 3))
    XCTAssertEqual(result.phase, .won)
    XCTAssertEqual(game.revealedSafeCellCount, 15)
    XCTAssertFalse(game.isTimerRunning)
  }

  func testMineRevealLosesAndRevealsAllMines() throws {
    let mines: Set<CellCoordinate> = [
      CellCoordinate(row: 0, column: 0), CellCoordinate(row: 2, column: 2),
    ]
    var game = GameEngine(board: board(mines: mines), difficulty: .easy, phase: .playing)
    let result = try game.reveal(at: CellCoordinate(row: 0, column: 0))
    XCTAssertEqual(game.phase, .lost)
    XCTAssertEqual(result.explodedMine, CellCoordinate(row: 0, column: 0))
    XCTAssertTrue(mines.allSatisfy { game.cell(at: $0)!.isRevealed })
  }

  func testCorrectChordRevealsNeighbors() throws {
    let mine = CellCoordinate(row: 0, column: 0)
    var game = GameEngine(board: board(mines: [mine]), difficulty: .easy, phase: .playing)
    _ = try game.reveal(at: CellCoordinate(row: 1, column: 1))
    _ = try game.toggleFlag(at: mine)
    let result = try game.chord(at: CellCoordinate(row: 1, column: 1))
    XCTAssertTrue(result.didChange)
    XCTAssertEqual(game.phase, .won)
  }

  func testIncorrectChordExplodesUnflaggedMine() throws {
    let mine = CellCoordinate(row: 0, column: 0)
    var game = GameEngine(board: board(mines: [mine]), difficulty: .easy, phase: .playing)
    _ = try game.reveal(at: CellCoordinate(row: 1, column: 1))
    _ = try game.toggleFlag(at: CellCoordinate(row: 0, column: 1))
    let result = try game.chord(at: CellCoordinate(row: 1, column: 1))
    XCTAssertEqual(result.explodedMine, mine)
    XCTAssertEqual(game.phase, .lost)
  }

  func testEasyFlaggingMarksForcedCoveredNeighbors() throws {
    let mines: Set<CellCoordinate> = [
      CellCoordinate(row: 0, column: 0), CellCoordinate(row: 0, column: 2),
      CellCoordinate(row: 2, column: 0), CellCoordinate(row: 2, column: 2),
    ]
    var game = GameEngine(
      board: board(width: 4, height: 3, mines: mines), difficulty: .easy, phase: .playing)
    let center = CellCoordinate(row: 1, column: 1)
    _ = try game.reveal(at: center)
    let knownSafe = [
      CellCoordinate(row: 0, column: 1), CellCoordinate(row: 1, column: 0),
      CellCoordinate(row: 1, column: 2), CellCoordinate(row: 2, column: 1),
    ]
    for safe in knownSafe { _ = try game.reveal(at: safe) }
    let result = try game.flagChord(at: center)
    XCTAssertEqual(result.changedCoordinates, mines)
    XCTAssertTrue(mines.allSatisfy { game.cell(at: $0)!.isFlagged })
  }

  func testTimerExcludesPausedTimeAndSnapshotRestoresPaused() throws {
    let board = board(mines: [CellCoordinate(row: 0, column: 0)])
    var game = GameEngine(board: board, difficulty: .easy, phase: .playing)
    let start = Date(timeIntervalSince1970: 100)
    game.startTimer(at: start)
    XCTAssertEqual(game.elapsedTime(at: start.addingTimeInterval(4.5)), 4.5)
    game.pauseTimer(at: start.addingTimeInterval(5))
    XCTAssertEqual(game.elapsedTime(at: start.addingTimeInterval(100)), 5)

    // Use a matching fixed-difficulty game for snapshot validation.
    let resumable = GameEngine(difficulty: .easy, seed: 1)
    let restored = try GameEngine(snapshot: resumable.snapshot(at: start))
    XCTAssertFalse(restored.isTimerRunning)
    XCTAssertEqual(restored.elapsedTime, 0)
  }

  func testActionsOutsideBoardThrow() {
    var game = GameEngine(difficulty: .easy, seed: 1)
    XCTAssertThrowsError(try game.reveal(at: CellCoordinate(row: -1, column: 0))) {
      XCTAssertEqual($0 as? GameEngineError, .coordinateOutsideBoard)
    }
  }

  func testSnapshotRejectsUnsupportedVersionAndWrongCellCount() {
    let game = GameEngine(difficulty: .easy, seed: 1)
    let valid = game.snapshot()
    let future = GameSnapshot(
      schemaVersion: GameSnapshot.currentSchemaVersion + 1,
      difficulty: valid.difficulty,
      configuration: valid.configuration,
      seed: valid.seed,
      cells: valid.cells,
      phase: valid.phase,
      actionMode: valid.actionMode,
      elapsedTime: valid.elapsedTime
    )
    XCTAssertThrowsError(try GameEngine(snapshot: future)) {
      XCTAssertEqual(
        $0 as? GameEngineError,
        .unsupportedSnapshotVersion(GameSnapshot.currentSchemaVersion + 1)
      )
    }

    let truncated = GameSnapshot(
      difficulty: valid.difficulty,
      configuration: valid.configuration,
      seed: valid.seed,
      cells: Array(valid.cells.dropLast()),
      phase: valid.phase,
      actionMode: valid.actionMode,
      elapsedTime: valid.elapsedTime
    )
    XCTAssertThrowsError(try GameEngine(snapshot: truncated)) {
      XCTAssertEqual($0 as? GameEngineError, .invalidSnapshot)
    }
  }

  func testActionModeRoutingAndToggle() throws {
    var game = GameEngine(
      board: board(mines: [CellCoordinate(row: 0, column: 0)]), difficulty: .easy)
    game.setActionMode(.flag)
    _ = try game.performPrimaryAction(at: CellCoordinate(row: 2, column: 2))
    XCTAssertTrue(game.cell(at: CellCoordinate(row: 2, column: 2))!.isFlagged)
    XCTAssertEqual(game.toggleActionMode(), .dig)
  }
}
