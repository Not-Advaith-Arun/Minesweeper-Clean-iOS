import Foundation
import XCTest

@testable import MinesweeperCore

final class BoardGenerationTests: XCTestCase {
  func testSplitMixIsDeterministicAndSeedSensitive() {
    var first = SplitMix64(seed: 123)
    var second = SplitMix64(seed: 123)
    var third = SplitMix64(seed: 124)
    let firstSequence = (0..<20).map { _ in first.next() }
    XCTAssertEqual(firstSequence, (0..<20).map { _ in second.next() })
    XCTAssertNotEqual(firstSequence, (0..<20).map { _ in third.next() })
  }

  func testGeneratedBoardCalculatesClues() {
    let configuration = BoardConfiguration(width: 3, height: 3, mineCount: 2)
    let board = GeneratedBoard(
      configuration: configuration,
      seed: 1,
      mines: [CellCoordinate(row: 0, column: 0), CellCoordinate(row: 2, column: 2)]
    )
    XCTAssertEqual(board.adjacentMineCount(at: CellCoordinate(row: 1, column: 1)), 2)
    XCTAssertEqual(board.adjacentMineCount(at: CellCoordinate(row: 0, column: 2)), 0)
    XCTAssertEqual(board.makeCells().filter(\.isMine).count, 2)
  }

  func testSolverCompletesSimpleBoardWithoutGuessing() {
    let configuration = BoardConfiguration(width: 3, height: 3, mineCount: 1)
    let board = GeneratedBoard(
      configuration: configuration,
      seed: 1,
      mines: [CellCoordinate(row: 0, column: 0)]
    )
    let report = NoGuessSolver().verify(board, firstReveal: CellCoordinate(row: 2, column: 2))
    XCTAssertEqual(report.status, .solved)
    XCTAssertEqual(report.revealedSafeCells, 8)
  }

  func testSolverRejectsMineAsFirstReveal() {
    let configuration = BoardConfiguration(width: 3, height: 3, mineCount: 1)
    let mine = CellCoordinate(row: 1, column: 1)
    let board = GeneratedBoard(configuration: configuration, seed: 1, mines: [mine])
    XCTAssertEqual(NoGuessSolver().verify(board, firstReveal: mine).status, .inconsistent)
  }

  func testNoGuessGeneratorIsDeterministicSafeAndVerified() throws {
    let configuration = BoardConfiguration(width: 7, height: 10, mineCount: 10)
    let firstReveal = CellCoordinate(row: 5, column: 3)
    let generator = NoGuessBoardGenerator(maximumAttempts: 2_000)
    let first = try generator.generate(
      configuration: configuration, firstReveal: firstReveal, seed: 42)
    let second = try generator.generate(
      configuration: configuration, firstReveal: firstReveal, seed: 42)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.mines.count, configuration.mineCount)
    XCTAssertFalse(first.isMine(at: firstReveal))
    XCTAssertTrue(configuration.neighbors(of: firstReveal).allSatisfy { !first.isMine(at: $0) })
    XCTAssertTrue(NoGuessSolver().verify(first, firstReveal: firstReveal).isSolved)
  }

  func testGeneratorFailsForCoordinateOutsideBoard() {
    let generator = NoGuessBoardGenerator()
    XCTAssertThrowsError(
      try generator.generate(
        configuration: BoardConfiguration(width: 3, height: 3, mineCount: 1),
        firstReveal: CellCoordinate(row: 10, column: 10),
        seed: 1
      )
    ) { error in
      XCTAssertEqual(error as? BoardGenerationError, .invalidFirstReveal)
    }
  }

  func testEveryProductionPresetGeneratesAVerifiedNoGuessBoard() throws {
    let generator = NoGuessBoardGenerator(maximumAttempts: 1)
    for (offset, difficulty) in Difficulty.allCases.enumerated() {
      let configuration = difficulty.configuration
      let firstReveal = CellCoordinate(
        row: configuration.height / 2, column: configuration.width / 2)
      let board: GeneratedBoard
      do {
        board = try generator.generate(
          configuration: configuration,
          firstReveal: firstReveal,
          seed: UInt64(10_000 + offset)
        )
      } catch {
        XCTFail("\(difficulty.rawValue) generation failed: \(error)")
        return
      }
      XCTAssertEqual(board.mines.count, configuration.mineCount, difficulty.rawValue)
      XCTAssertFalse(board.isMine(at: firstReveal), difficulty.rawValue)
      XCTAssertTrue(
        NoGuessSolver().verify(board, firstReveal: firstReveal).isSolved, difficulty.rawValue)
    }
  }

  func testNormalGamesPreferVariedRandomLayoutsBeforeStructuredFallback() throws {
    let configuration = Difficulty.medium.configuration
    let firstReveal = CellCoordinate(row: configuration.height / 2, column: configuration.width / 2)
    let generator = NoGuessBoardGenerator(maximumAttempts: 200, randomAttemptsBeforeFallback: 32)
    let boards = try (0..<8).map { offset in
      try generator.generate(
        configuration: configuration,
        firstReveal: firstReveal,
        seed: UInt64(50_000 + offset)
      )
    }
    XCTAssertEqual(Set(boards.map(\.mines)).count, boards.count)
    let boardsWithNearbyMines = boards.filter { board in
      board.mines.contains { mine in
        max(abs(mine.row - firstReveal.row), abs(mine.column - firstReveal.column)) <= 3
      }
    }
    XCTAssertGreaterThanOrEqual(boardsWithNearbyMines.count, 4)
  }

  /// Runs three boards per preset normally. Set MINESWEEPER_EXTENDED_TESTS=1 for 250 per preset,
  /// or set it to an explicit larger iteration count (for example 1000) for the overnight gate.
  func testBulkNoGuessGenerationAcrossPresets() throws {
    let extendedValue = ProcessInfo.processInfo.environment["MINESWEEPER_EXTENDED_TESTS"]
    let iterations = extendedValue == "1" ? 250 : max(3, Int(extendedValue ?? "") ?? 3)
    let generator = NoGuessBoardGenerator(maximumAttempts: 128)
    for iteration in 0..<iterations {
      for (difficultyIndex, difficulty) in Difficulty.allCases.enumerated() {
        let configuration = difficulty.configuration
        let firstReveal = CellCoordinate(
          row: (iteration * 7 + configuration.height / 2) % configuration.height,
          column: (iteration * 11 + configuration.width / 2) % configuration.width
        )
        let seed = UInt64(iteration * Difficulty.allCases.count + difficultyIndex)
        let board = try generator.generate(
          configuration: configuration,
          firstReveal: firstReveal,
          seed: seed
        )
        XCTAssertEqual(board.mines.count, configuration.mineCount)
        XCTAssertFalse(board.isMine(at: firstReveal))
        XCTAssertTrue(configuration.neighbors(of: firstReveal).allSatisfy { !board.isMine(at: $0) })
        XCTAssertTrue(
          NoGuessSolver().verify(board, firstReveal: firstReveal).isSolved,
          "\(difficulty.rawValue), iteration \(iteration)"
        )
      }
    }
  }
}
