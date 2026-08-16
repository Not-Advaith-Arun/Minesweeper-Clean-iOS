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
    // The simulator job runs with code coverage and is not a stable wall-clock
    // benchmark. Portable CI still enforces a hosted-runner budget, while
    // normal local and on-device runs keep the tighter performance guard.
#if !DEBUG && !targetEnvironment(simulator)
    let timeBudget = ProcessInfo.processInfo.environment["CI"] == "true" ? 4.0 : 3.0
#endif
    let samples: [(CellCoordinate, UInt64)] = [
      (CellCoordinate(row: 0, column: 0), 90_999),
      (CellCoordinate(row: 16, column: 9), 91_000),
      (CellCoordinate(row: 21, column: 12), 91_001),
      (CellCoordinate(row: 26, column: 15), 91_002),
      (CellCoordinate(row: 31, column: 17), 91_003),
    ]

    for (firstReveal, seed) in samples {
#if !DEBUG && !targetEnvironment(simulator)
      let startedAt = Date()
#endif
      let board = try generator.generate(
        configuration: configuration,
        firstReveal: firstReveal,
        seed: seed
      )
#if !DEBUG && !targetEnvironment(simulator)
      let elapsed = Date().timeIntervalSince(startedAt)
#endif
      let report = solver.verify(board, firstReveal: firstReveal)

      XCTAssertEqual(board.configuration, configuration)
      XCTAssertEqual(board.mines.count, 150)
      XCTAssertFalse(board.isMine(at: firstReveal))
      XCTAssertTrue(configuration.neighbors(of: firstReveal).allSatisfy {
        !board.isMine(at: $0)
      })
      XCTAssertTrue(report.isSolved)
      XCTAssertGreaterThanOrEqual(scorer.threeBV(board), 350)
      XCTAssertGreaterThanOrEqual(report.deductionPasses, 20)
      XCTAssertGreaterThanOrEqual(report.advancedDeductionPasses, 4)
      let metrics = BoardDistributionScorer().metrics(board)
      XCTAssertTrue(
        BoardDistributionLimits().admits(metrics),
        "opening \(firstReveal) produced a patterned layout: \(metrics)"
      )
#if !DEBUG && !targetEnvironment(simulator)
      XCTAssertLessThan(elapsed, timeBudget, "Extreme generation took \(elapsed)s")
#endif
    }
  }

  /// The generator used to build Extreme from modular templates, which produced boards whose
  /// mines sat on visible diagonal stripes. These fixtures pin the metric that detects that:
  /// every deliberate lattice has to fail, and both ordinary and cluster-heavy random layouts
  /// have to pass, so the check cannot be satisfied by simply spreading mines apart.
  func testDistributionMetricsRejectLatticesAndAcceptClusters() {
    let configuration = Difficulty.extreme.configuration
    let scorer = BoardDistributionScorer()
    let limits = BoardDistributionLimits()
    let cells = (0..<configuration.cellCount).compactMap(configuration.coordinate)

    func board(orderedBy residue: (CellCoordinate) -> Int) -> GeneratedBoard {
      let ordered = cells.sorted { left, right in
        let leftResidue = residue(left)
        let rightResidue = residue(right)
        return leftResidue == rightResidue ? left < right : leftResidue < rightResidue
      }
      return GeneratedBoard(
        configuration: configuration,
        seed: 1,
        mines: Set(ordered.prefix(configuration.mineCount))
      )
    }

    let lattices: [(String, GeneratedBoard)] = [
      ("horizontal stripes", board { $0.row % 4 }),
      ("vertical stripes", board { $0.column % 4 }),
      ("diagonal bands", board { (($0.row + 2 * $0.column) % 13 + 13) % 13 }),
      ("checkerboard", board { ($0.row + $0.column) % 2 }),
    ]
    for (name, lattice) in lattices {
      let metrics = scorer.metrics(lattice)
      XCTAssertFalse(limits.admits(metrics), "\(name) was accepted: \(metrics)")
    }

    var random = SplitMix64(seed: 4_242)
    func shuffled(_ values: [CellCoordinate]) -> [CellCoordinate] {
      var pool = values
      for position in stride(from: pool.count - 1, to: 0, by: -1) {
        pool.swapAt(position, random.next(upperBound: position + 1))
      }
      return pool
    }

    let uniform = GeneratedBoard(
      configuration: configuration,
      seed: 2,
      mines: Set(shuffled(cells).prefix(configuration.mineCount))
    )
    XCTAssertTrue(limits.admits(scorer.metrics(uniform)), "a uniform layout must pass")

    // Ten planted 2×2 blocks: far more clustering than the generator produces on its own.
    var clustered: Set<CellCoordinate> = []
    for anchor in shuffled(cells) where clustered.count < 40 {
      guard anchor.row + 1 < configuration.height, anchor.column + 1 < configuration.width
      else { continue }
      let block = [
        anchor,
        CellCoordinate(row: anchor.row, column: anchor.column + 1),
        CellCoordinate(row: anchor.row + 1, column: anchor.column),
        CellCoordinate(row: anchor.row + 1, column: anchor.column + 1),
      ]
      guard block.allSatisfy({ !clustered.contains($0) }) else { continue }
      clustered.formUnion(block)
    }
    for cell in shuffled(cells) where clustered.count < configuration.mineCount {
      clustered.insert(cell)
    }
    let clusteredBoard = GeneratedBoard(
      configuration: configuration,
      seed: 3,
      mines: Set(clustered.sorted().prefix(configuration.mineCount))
    )
    XCTAssertGreaterThanOrEqual(scorer.solidTwoByTwoBlockCount(clusteredBoard), 8)
    XCTAssertTrue(
      limits.admits(scorer.metrics(clusteredBoard)),
      "clustered layouts are legitimate Minesweeper structure and must pass"
    )
  }

  /// Extreme layouts have to look like random layouts, not like a construction. Mine repulsion
  /// is as much a fingerprint as a stripe is, so this also requires the sample to contain solid
  /// 2×2 mine groups at roughly the rate chance produces them.
  func testExtremeLayoutsStayStatisticallyRandom() throws {
    let configuration = Difficulty.extreme.configuration
    let firstReveal = CellCoordinate(row: 16, column: 9)
    let generator = HardNoGuessBoardGenerator()
    let scorer = BoardDistributionScorer()
    let limits = BoardDistributionLimits()

    var blockTotal = 0
    for offset in 0..<6 {
      let board = try generator.generate(
        configuration: configuration,
        firstReveal: firstReveal,
        seed: UInt64(660_000 + offset)
      )
      let metrics = scorer.metrics(board)
      XCTAssertTrue(limits.admits(metrics), "seed \(offset) produced \(metrics)")
      blockTotal += metrics.solidTwoByTwoBlockCount
    }
    XCTAssertGreaterThan(
      blockTotal, 0,
      "no 2×2 mine group in six boards means the generator is pushing mines apart again"
    )
  }

  func testExtremeUsesFreshSeededLayoutsForTheSameOpening() throws {
    let configuration = Difficulty.extreme.configuration
    let firstReveal = CellCoordinate(row: 16, column: 9)
    let generator = HardNoGuessBoardGenerator()
    let boards = try (0..<5).map { offset in
      try generator.generate(
        configuration: configuration,
        firstReveal: firstReveal,
        seed: UInt64(810_000 + offset)
      )
    }

    XCTAssertEqual(Set(boards.map(\.mines)).count, boards.count)
    let pairwiseMineDifferences = boards.indices.flatMap { left in
      boards.indices.compactMap { right in
        left < right ? boards[left].mines.symmetricDifference(boards[right].mines).count : nil
      }
    }
    XCTAssertGreaterThanOrEqual(pairwiseMineDifferences.min() ?? 0, 80)
    for board in boards {
      let report = NoGuessSolver().verify(board, firstReveal: firstReveal)
      XCTAssertTrue(report.isSolved)
      XCTAssertGreaterThanOrEqual(BoardDifficultyScorer().threeBV(board), 350)
      XCTAssertGreaterThanOrEqual(report.advancedDeductionPasses, 4)
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
    var advancedScores: [Difficulty: [Int]] = [:]

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
        let report = NoGuessSolver().verify(board, firstReveal: firstReveal)
        XCTAssertTrue(report.isSolved, difficulty.rawValue)
        scores[difficulty, default: []].append(scorer.threeBV(board))
        advancedScores[difficulty, default: []].append(report.advancedDeductionPasses)
      }
    }

    let averages = scores.mapValues { values in values.reduce(0, +) / values.count }
    print("Production 3BV averages: \(averages)")
    XCTAssertGreaterThan(averages[.medium, default: 0], averages[.easy, default: 0])
    XCTAssertGreaterThan(averages[.hard, default: 0], averages[.medium, default: 0])
    XCTAssertGreaterThan(averages[.huge, default: 0], averages[.hard, default: 0])
    XCTAssertGreaterThanOrEqual(averages[.extreme, default: 0], 350)
    let advancedAverages = advancedScores.mapValues { values in values.reduce(0, +) / values.count }
    XCTAssertGreaterThan(
      advancedAverages[.extreme, default: 0],
      advancedAverages[.huge, default: 0]
    )
  }
}
