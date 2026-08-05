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

  func testThreeBVCountsOpeningsAndIsolatedNumbers() {
    let configuration = BoardConfiguration(width: 4, height: 4, mineCount: 1)
    let board = GeneratedBoard(
      configuration: configuration,
      seed: 1,
      mines: [CellCoordinate(row: 0, column: 0)]
    )

    XCTAssertEqual(BoardDifficultyScorer().threeBV(board), 1)
  }

  func testHardNoGuessGeneratorReturnsVerifiedBoard() throws {
    let configuration = Difficulty.easy.configuration
    let firstReveal = CellCoordinate(row: configuration.height / 2, column: configuration.width / 2)
    let generator = HardNoGuessBoardGenerator(
      maximumAttempts: 96,
      randomAttemptsBeforeFallback: 64
    )
    let board = try generator.generate(
      configuration: configuration,
      firstReveal: firstReveal,
      seed: 7_777
    )

    XCTAssertTrue(NoGuessSolver().verify(board, firstReveal: firstReveal).isSolved)
    XCTAssertGreaterThan(BoardDifficultyScorer().threeBV(board), 0)
  }

  func testExtremeGeneratorIsFastVerifiedAndChallengingAcrossOpenings() throws {
    let configuration = Difficulty.extreme.configuration
    let generator = HardNoGuessBoardGenerator(
      maximumAttempts: 2_048,
      randomAttemptsBeforeFallback: 1_920
    )
    let solver = NoGuessSolver()
    let scorer = BoardDifficultyScorer()
    // Hosted runners have variable CPU allocation. Keep the tighter local
    // performance guard while allowing deterministic CI scheduling overhead.
    let timeBudget = ProcessInfo.processInfo.environment["CI"] == "true" ? 4.0 : 2.0
    let samples: [(CellCoordinate, UInt64)] = [
      (CellCoordinate(row: 0, column: 0), 90_999),
      (CellCoordinate(row: 16, column: 9), 91_000),
      (CellCoordinate(row: 21, column: 12), 91_001),
      (CellCoordinate(row: 26, column: 15), 91_002),
      (CellCoordinate(row: 31, column: 17), 91_003),
    ]

    for (firstReveal, seed) in samples {
      let startedAt = Date()
      let board = try generator.generate(
        configuration: configuration,
        firstReveal: firstReveal,
        seed: seed
      )
      let elapsed = Date().timeIntervalSince(startedAt)
      let report = solver.verify(board, firstReveal: firstReveal)

      XCTAssertEqual(board.configuration, configuration)
      XCTAssertEqual(board.mines.count, 150)
      XCTAssertFalse(board.isMine(at: firstReveal))
      XCTAssertTrue(configuration.neighbors(of: firstReveal).allSatisfy {
        !board.isMine(at: $0)
      })
      XCTAssertTrue(report.isSolved)
      XCTAssertGreaterThanOrEqual(scorer.threeBV(board), 150)
      XCTAssertGreaterThanOrEqual(report.deductionPasses, 20)
      XCTAssertLessThan(elapsed, timeBudget, "Extreme generation took \(elapsed)s")
    }
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

  func testProductionGenerationPoliciesAreVerifiedAndChallenging() throws {
    let scorer = BoardDifficultyScorer()
    var scores: [Difficulty: [Int]] = [:]

    for (difficultyIndex, difficulty) in Difficulty.allCases.enumerated() {
      let configuration = difficulty.configuration
      let generator: any BoardGenerating = switch difficulty {
      case .extreme:
        HardNoGuessBoardGenerator(maximumAttempts: 2_048, randomAttemptsBeforeFallback: 1_920)
      case .hard, .huge:
        NoGuessBoardGenerator(maximumAttempts: 4_096, randomAttemptsBeforeFallback: 96)
      case .beginner, .easy, .medium:
        NoGuessBoardGenerator(maximumAttempts: 2_048, randomAttemptsBeforeFallback: 64)
      }

      for iteration in 0..<3 {
        let firstReveal = CellCoordinate(
          row: (configuration.height / 2 + iteration * 5) % configuration.height,
          column: (configuration.width / 2 + iteration * 3) % configuration.width
        )
        let board = try generator.generate(
          configuration: configuration,
          firstReveal: firstReveal,
          seed: UInt64(90_000 + difficultyIndex * 100 + iteration)
        )
        XCTAssertFalse(board.isMine(at: firstReveal), difficulty.rawValue)
        XCTAssertTrue(
          configuration.neighbors(of: firstReveal).allSatisfy { !board.isMine(at: $0) },
          difficulty.rawValue
        )
        XCTAssertTrue(
          NoGuessSolver().verify(board, firstReveal: firstReveal).isSolved,
          difficulty.rawValue
        )
        scores[difficulty, default: []].append(scorer.threeBV(board))
      }
    }

    let averages = scores.mapValues { values in values.reduce(0, +) / values.count }
    print("Production 3BV averages: \(averages)")
    XCTAssertGreaterThan(averages[.medium, default: 0], averages[.easy, default: 0])
    XCTAssertGreaterThan(averages[.hard, default: 0], averages[.medium, default: 0])
    XCTAssertGreaterThan(averages[.huge, default: 0], averages[.hard, default: 0])
    XCTAssertGreaterThan(averages[.extreme, default: 0], averages[.huge, default: 0])
  }
}
