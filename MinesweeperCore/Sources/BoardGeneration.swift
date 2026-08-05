import Foundation

/// A stable random-number generator used to make games reproducible across launches and platforms.
public struct SplitMix64: RandomNumberGenerator, Codable, Sendable {
  public private(set) var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  mutating func next(upperBound: Int) -> Int {
    precondition(upperBound > 0)
    let bound = UInt64(upperBound)
    let rejectionLimit = UInt64.max - UInt64.max % bound
    var candidate = next()
    while candidate >= rejectionLimit { candidate = next() }
    return Int(candidate % bound)
  }
}

public struct GeneratedBoard: Hashable, Codable, Sendable {
  public let configuration: BoardConfiguration
  public let seed: UInt64
  public let mines: Set<CellCoordinate>

  public init(configuration: BoardConfiguration, seed: UInt64, mines: Set<CellCoordinate>) {
    precondition(mines.count == configuration.mineCount)
    precondition(mines.allSatisfy(configuration.contains))
    self.configuration = configuration
    self.seed = seed
    self.mines = mines
  }

  public func isMine(at coordinate: CellCoordinate) -> Bool {
    mines.contains(coordinate)
  }

  public func adjacentMineCount(at coordinate: CellCoordinate) -> Int {
    configuration.neighbors(of: coordinate).reduce(into: 0) { count, neighbor in
      if mines.contains(neighbor) { count += 1 }
    }
  }

  public func makeCells() -> [Cell] {
    (0..<configuration.cellCount).compactMap(configuration.coordinate).map { coordinate in
      Cell(
        isMine: mines.contains(coordinate),
        adjacentMineCount: adjacentMineCount(at: coordinate)
      )
    }
  }
}

public enum BoardGenerationError: Error, Equatable, Sendable {
  case invalidFirstReveal
  case insufficientUnprotectedCells
  case unableToGenerateNoGuessBoard(attempts: Int)
}

public protocol BoardGenerating: Sendable {
  func generate(
    configuration: BoardConfiguration,
    firstReveal: CellCoordinate,
    seed: UInt64
  ) throws -> GeneratedBoard
}

public enum SolverStatus: String, Codable, Sendable {
  case solved
  case stalled
  case inconsistent
}

public struct SolverReport: Equatable, Codable, Sendable {
  public let status: SolverStatus
  public let revealedSafeCells: Int
  public let inferredMines: Int
  public let deductionPasses: Int

  public var isSolved: Bool { status == .solved }
}

/// Verifies that a board can be completed using only deductions a player can make from clues.
/// It combines direct clue saturation, subset differences, and exact enumeration of small
/// frontier components. It never reads mine locations when selecting a move.
public struct NoGuessSolver: Sendable {
  public var maximumDeductionPasses: Int
  public var maximumExactComponentSize: Int
  public var maximumEnumeratedSolutions: Int

  public init(
    maximumDeductionPasses: Int = 10_000,
    maximumExactComponentSize: Int = 20,
    maximumEnumeratedSolutions: Int = 250_000
  ) {
    self.maximumDeductionPasses = maximumDeductionPasses
    self.maximumExactComponentSize = maximumExactComponentSize
    self.maximumEnumeratedSolutions = maximumEnumeratedSolutions
  }

  public func verify(_ board: GeneratedBoard, firstReveal: CellCoordinate) -> SolverReport {
    guard board.configuration.contains(firstReveal), !board.isMine(at: firstReveal) else {
      return SolverReport(
        status: .inconsistent, revealedSafeCells: 0, inferredMines: 0, deductionPasses: 0)
    }

    var revealed: Set<CellCoordinate> = []
    var knownMines: Set<CellCoordinate> = []
    reveal(firstReveal, on: board, into: &revealed)
    var pass = 0

    while pass < maximumDeductionPasses {
      if revealed.count == board.configuration.safeCellCount {
        return SolverReport(
          status: .solved,
          revealedSafeCells: revealed.count,
          inferredMines: knownMines.count,
          deductionPasses: pass
        )
      }
      pass += 1

      let build = makeConstraints(on: board, revealed: revealed, knownMines: knownMines)
      if build.isInconsistent {
        return SolverReport(
          status: .inconsistent,
          revealedSafeCells: revealed.count,
          inferredMines: knownMines.count,
          deductionPasses: pass
        )
      }

      var safeDeductions: Set<CellCoordinate> = []
      var mineDeductions: Set<CellCoordinate> = []
      applyDirectDeductions(
        build.constraints,
        safe: &safeDeductions,
        mines: &mineDeductions
      )
      applySubsetDeductions(
        build.constraints,
        safe: &safeDeductions,
        mines: &mineDeductions
      )

      let hidden = allCoordinates(in: board.configuration).subtracting(revealed).subtracting(
        knownMines)
      let remainingMines = board.configuration.mineCount - knownMines.count
      if remainingMines == 0 {
        safeDeductions.formUnion(hidden)
      } else if remainingMines == hidden.count {
        mineDeductions.formUnion(hidden)
      }

      if safeDeductions.isEmpty && mineDeductions.isEmpty {
        let exact = exactDeductions(from: build.constraints)
        safeDeductions.formUnion(exact.safe)
        mineDeductions.formUnion(exact.mines)
      }

      if !safeDeductions.isDisjoint(with: mineDeductions) {
        return SolverReport(
          status: .inconsistent,
          revealedSafeCells: revealed.count,
          inferredMines: knownMines.count,
          deductionPasses: pass
        )
      }

      mineDeductions.subtract(revealed)
      safeDeductions.subtract(knownMines)
      if safeDeductions.isEmpty && mineDeductions.isEmpty { break }

      knownMines.formUnion(mineDeductions)
      for coordinate in safeDeductions {
        // This check validates deductions after the fact; it is not used to choose a move.
        guard !board.isMine(at: coordinate) else {
          return SolverReport(
            status: .inconsistent,
            revealedSafeCells: revealed.count,
            inferredMines: knownMines.count,
            deductionPasses: pass
          )
        }
        reveal(coordinate, on: board, into: &revealed)
      }
    }

    let status: SolverStatus =
      revealed.count == board.configuration.safeCellCount ? .solved : .stalled
    return SolverReport(
      status: status,
      revealedSafeCells: revealed.count,
      inferredMines: knownMines.count,
      deductionPasses: pass
    )
  }

  private struct Constraint: Hashable {
    let cells: Set<CellCoordinate>
    let mines: Int
  }

  private func makeConstraints(
    on board: GeneratedBoard,
    revealed: Set<CellCoordinate>,
    knownMines: Set<CellCoordinate>
  ) -> (constraints: [Constraint], isInconsistent: Bool) {
    var unique: Set<Constraint> = []
    for coordinate in revealed {
      let adjacent = board.configuration.neighbors(of: coordinate)
      let knownAdjacent = adjacent.reduce(into: 0) { total, neighbor in
        if knownMines.contains(neighbor) { total += 1 }
      }
      let unknown = Set(adjacent.filter { !revealed.contains($0) && !knownMines.contains($0) })
      let remaining = board.adjacentMineCount(at: coordinate) - knownAdjacent
      if remaining < 0 || remaining > unknown.count { return ([], true) }
      if !unknown.isEmpty { unique.insert(Constraint(cells: unknown, mines: remaining)) }
    }
    return (Array(unique), false)
  }

  private func applyDirectDeductions(
    _ constraints: [Constraint],
    safe: inout Set<CellCoordinate>,
    mines: inout Set<CellCoordinate>
  ) {
    for constraint in constraints {
      if constraint.mines == 0 { safe.formUnion(constraint.cells) }
      if constraint.mines == constraint.cells.count { mines.formUnion(constraint.cells) }
    }
  }

  private func applySubsetDeductions(
    _ constraints: [Constraint],
    safe: inout Set<CellCoordinate>,
    mines: inout Set<CellCoordinate>
  ) {
    guard constraints.count > 1 else { return }
    for firstIndex in constraints.indices {
      for secondIndex in constraints.indices where firstIndex != secondIndex {
        let subset = constraints[firstIndex]
        let superset = constraints[secondIndex]
        guard subset.cells.isSubset(of: superset.cells) else { continue }
        let difference = superset.cells.subtracting(subset.cells)
        guard !difference.isEmpty else { continue }
        let mineDifference = superset.mines - subset.mines
        if mineDifference == 0 { safe.formUnion(difference) }
        if mineDifference == difference.count { mines.formUnion(difference) }
      }
    }
  }

  private func exactDeductions(from constraints: [Constraint]) -> (
    safe: Set<CellCoordinate>, mines: Set<CellCoordinate>
  ) {
    var remainingVariables = Set(constraints.flatMap(\.cells))
    var safe: Set<CellCoordinate> = []
    var mines: Set<CellCoordinate> = []

    while let seed = remainingVariables.first {
      var componentVariables: Set<CellCoordinate> = [seed]
      var componentConstraints: Set<Int> = []
      var grew = true
      while grew {
        grew = false
        for (index, constraint) in constraints.enumerated()
        where !componentConstraints.contains(index)
          && !constraint.cells.isDisjoint(with: componentVariables)
        {
          componentConstraints.insert(index)
          let oldCount = componentVariables.count
          componentVariables.formUnion(constraint.cells)
          grew = grew || componentVariables.count != oldCount
        }
      }
      remainingVariables.subtract(componentVariables)
      guard componentVariables.count <= maximumExactComponentSize else { continue }

      let localConstraints = componentConstraints.map { constraints[$0] }
      let enumeration = enumerate(componentVariables, constraints: localConstraints)
      guard !enumeration.wasTruncated, enumeration.solutionCount > 0 else { continue }
      for variable in componentVariables {
        let mineOccurrences = enumeration.mineOccurrences[variable, default: 0]
        if mineOccurrences == 0 { safe.insert(variable) }
        if mineOccurrences == enumeration.solutionCount { mines.insert(variable) }
      }
    }
    return (safe, mines)
  }

  private func enumerate(
    _ variableSet: Set<CellCoordinate>,
    constraints: [Constraint]
  ) -> (solutionCount: Int, mineOccurrences: [CellCoordinate: Int], wasTruncated: Bool) {
    let ordered = variableSet.sorted { left, right in
      let leftDegree = constraints.reduce(0) { $0 + ($1.cells.contains(left) ? 1 : 0) }
      let rightDegree = constraints.reduce(0) { $0 + ($1.cells.contains(right) ? 1 : 0) }
      return leftDegree == rightDegree ? left < right : leftDegree > rightDegree
    }
    var assignment: [CellCoordinate: Bool] = [:]
    var solutionCount = 0
    var mineOccurrences: [CellCoordinate: Int] = [:]
    var truncated = false

    func remainsFeasible() -> Bool {
      for constraint in constraints {
        var assignedMines = 0
        var unassigned = 0
        for cell in constraint.cells {
          if let value = assignment[cell] {
            if value { assignedMines += 1 }
          } else {
            unassigned += 1
          }
        }
        if assignedMines > constraint.mines || assignedMines + unassigned < constraint.mines {
          return false
        }
      }
      return true
    }

    func visit(_ index: Int) {
      if truncated { return }
      if index == ordered.count {
        solutionCount += 1
        for (coordinate, isMine) in assignment where isMine {
          mineOccurrences[coordinate, default: 0] += 1
        }
        if solutionCount >= maximumEnumeratedSolutions { truncated = true }
        return
      }
      let coordinate = ordered[index]
      assignment[coordinate] = false
      if remainsFeasible() { visit(index + 1) }
      assignment[coordinate] = true
      if remainsFeasible() { visit(index + 1) }
      assignment.removeValue(forKey: coordinate)
    }

    visit(0)
    return (solutionCount, mineOccurrences, truncated)
  }

  private func reveal(
    _ start: CellCoordinate,
    on board: GeneratedBoard,
    into revealed: inout Set<CellCoordinate>
  ) {
    guard !board.isMine(at: start), !revealed.contains(start) else { return }
    var queue = [start]
    var cursor = 0
    revealed.insert(start)
    while cursor < queue.count {
      let coordinate = queue[cursor]
      cursor += 1
      guard board.adjacentMineCount(at: coordinate) == 0 else { continue }
      for neighbor in board.configuration.neighbors(of: coordinate)
      where !board.isMine(at: neighbor) && revealed.insert(neighbor).inserted {
        queue.append(neighbor)
      }
    }
  }

  private func allCoordinates(in configuration: BoardConfiguration) -> Set<CellCoordinate> {
    Set((0..<configuration.cellCount).compactMap(configuration.coordinate))
  }
}

public struct NoGuessBoardGenerator: BoardGenerating, Sendable {
  public var maximumAttempts: Int
  public var randomAttemptsBeforeFallback: Int
  public var protectsFirstRevealNeighbors: Bool
  public var solver: NoGuessSolver

  public init(
    maximumAttempts: Int = 4_096,
    randomAttemptsBeforeFallback: Int = 24,
    protectsFirstRevealNeighbors: Bool = true,
    solver: NoGuessSolver = NoGuessSolver()
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.randomAttemptsBeforeFallback = max(0, randomAttemptsBeforeFallback)
    self.protectsFirstRevealNeighbors = protectsFirstRevealNeighbors
    self.solver = solver
  }

  public func generate(
    configuration: BoardConfiguration,
    firstReveal: CellCoordinate,
    seed: UInt64
  ) throws -> GeneratedBoard {
    guard configuration.contains(firstReveal) else { throw BoardGenerationError.invalidFirstReveal }
    var protected: Set<CellCoordinate> = [firstReveal]
    if protectsFirstRevealNeighbors {
      protected.formUnion(configuration.neighbors(of: firstReveal))
    }
    var candidates = allCoordinates(in: configuration).filter { !protected.contains($0) }
    if candidates.count < configuration.mineCount {
      // Very small/custom boards still receive first-cell safety when a zero opening is impossible.
      protected = [firstReveal]
      candidates = allCoordinates(in: configuration).filter { !protected.contains($0) }
      guard candidates.count >= configuration.mineCount else {
        throw BoardGenerationError.insufficientUnprotectedCells
      }
    }

    var random = SplitMix64(seed: seed)
    let initialRandomAttempts = min(maximumAttempts, randomAttemptsBeforeFallback)
    for _ in 0..<initialRandomAttempts {
      shuffle(&candidates, using: &random)
      let mines = Set(candidates.prefix(configuration.mineCount))
      let board = GeneratedBoard(configuration: configuration, seed: seed, mines: mines)
      if solver.verify(board, firstReveal: firstReveal).isSolved { return board }
    }

    // A compact band against the edges farthest from the opening is usually solved by the
    // opening flood alone: every safe boundary clue touches the connected zero region.
    // This fallback makes high-density presets reliable without thousands of retries.
    for mines in structuredMineSets(
      candidates: candidates,
      mineCount: configuration.mineCount,
      firstReveal: firstReveal,
      random: &random
    ) {
      let board = GeneratedBoard(configuration: configuration, seed: seed, mines: mines)
      if solver.verify(board, firstReveal: firstReveal).isSolved { return board }
    }

    for _ in initialRandomAttempts..<maximumAttempts {
      shuffle(&candidates, using: &random)
      let mines = Set(candidates.prefix(configuration.mineCount))
      let board = GeneratedBoard(configuration: configuration, seed: seed, mines: mines)
      if solver.verify(board, firstReveal: firstReveal).isSolved { return board }
    }
    throw BoardGenerationError.unableToGenerateNoGuessBoard(attempts: maximumAttempts)
  }

  private func allCoordinates(in configuration: BoardConfiguration) -> [CellCoordinate] {
    (0..<configuration.cellCount).compactMap(configuration.coordinate)
  }

  private func shuffle(_ values: inout [CellCoordinate], using random: inout SplitMix64) {
    guard values.count > 1 else { return }
    for index in stride(from: values.count - 1, through: 1, by: -1) {
      values.swapAt(index, random.next(upperBound: index + 1))
    }
  }

  private func structuredMineSets(
    candidates: [CellCoordinate],
    mineCount: Int,
    firstReveal: CellCoordinate,
    random: inout SplitMix64
  ) -> [Set<CellCoordinate>] {
    var tieBreakers: [CellCoordinate: UInt64] = [:]
    for coordinate in candidates { tieBreakers[coordinate] = random.next() }

    func makeSet(distance: (CellCoordinate) -> Int) -> Set<CellCoordinate> {
      let ordered = candidates.sorted { left, right in
        let leftDistance = distance(left)
        let rightDistance = distance(right)
        if leftDistance != rightDistance { return leftDistance > rightDistance }
        return tieBreakers[left, default: 0] < tieBreakers[right, default: 0]
      }
      return Set(ordered.prefix(mineCount))
    }

    let chebyshev = makeSet { coordinate in
      max(abs(coordinate.row - firstReveal.row), abs(coordinate.column - firstReveal.column))
    }
    let manhattan = makeSet { coordinate in
      abs(coordinate.row - firstReveal.row) + abs(coordinate.column - firstReveal.column)
    }
    let squaredEuclidean = makeSet { coordinate in
      let row = coordinate.row - firstReveal.row
      let column = coordinate.column - firstReveal.column
      return row * row + column * column
    }
    return [chebyshev, manhattan, squaredEuclidean]
  }
}

public struct BoardDifficultyScorer: Sendable {
  public init() {}

  /// Bechtel's Board Benchmark Value: the minimum number of direct safe-cell openings
  /// needed to reveal every non-mine cell without flags or chords.
  public func threeBV(_ board: GeneratedBoard) -> Int {
    var marked: Set<CellCoordinate> = []
    var score = 0

    for row in 0..<board.configuration.height {
      for column in 0..<board.configuration.width {
        let coordinate = CellCoordinate(row: row, column: column)
        guard !marked.contains(coordinate),
          !board.isMine(at: coordinate),
          board.adjacentMineCount(at: coordinate) == 0
        else { continue }
        score += 1
        markZeroOpening(from: coordinate, on: board, into: &marked)
      }
    }

    for row in 0..<board.configuration.height {
      for column in 0..<board.configuration.width {
        let coordinate = CellCoordinate(row: row, column: column)
        if !marked.contains(coordinate), !board.isMine(at: coordinate) {
          marked.insert(coordinate)
          score += 1
        }
      }
    }

    return score
  }

  private func markZeroOpening(
    from start: CellCoordinate,
    on board: GeneratedBoard,
    into marked: inout Set<CellCoordinate>
  ) {
    var queue = [start]
    var cursor = 0
    marked.insert(start)
    while cursor < queue.count {
      let coordinate = queue[cursor]
      cursor += 1
      guard board.adjacentMineCount(at: coordinate) == 0 else { continue }
      for neighbor in board.configuration.neighbors(of: coordinate)
      where !board.isMine(at: neighbor) && marked.insert(neighbor).inserted {
        if board.adjacentMineCount(at: neighbor) == 0 { queue.append(neighbor) }
      }
    }
  }
}

public struct HardNoGuessBoardGenerator: BoardGenerating, Sendable {
  public var maximumAttempts: Int
  public var randomAttemptsBeforeFallback: Int
  public var solver: NoGuessSolver
  public var scorer: BoardDifficultyScorer

  public init(
    maximumAttempts: Int = 2_048,
    randomAttemptsBeforeFallback: Int = 1_920,
    solver: NoGuessSolver = NoGuessSolver(),
    scorer: BoardDifficultyScorer = BoardDifficultyScorer()
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.randomAttemptsBeforeFallback = max(0, min(randomAttemptsBeforeFallback, maximumAttempts))
    self.solver = solver
    self.scorer = scorer
  }

  public func generate(
    configuration: BoardConfiguration,
    firstReveal: CellCoordinate,
    seed: UInt64
  ) throws -> GeneratedBoard {
    guard configuration.contains(firstReveal) else { throw BoardGenerationError.invalidFirstReveal }

    var protected: Set<CellCoordinate> = [firstReveal]
    protected.formUnion(configuration.neighbors(of: firstReveal))
    var candidates = allCoordinates(in: configuration).filter { !protected.contains($0) }
    if candidates.count < configuration.mineCount {
      protected = [firstReveal]
      candidates = allCoordinates(in: configuration).filter { !protected.contains($0) }
      guard candidates.count >= configuration.mineCount else {
        throw BoardGenerationError.insufficientUnprotectedCells
      }
    }

    var random = SplitMix64(seed: seed)
    var bestBoard: GeneratedBoard?
    var bestScore = Int.min

    // At Extreme's 26% density, verified random layouts are vanishingly rare.
    // Sampling thousands of them both blocked the first reveal for close to a
    // minute and eventually selected a trivial compact-band fallback. Diagonal
    // modular fronts are constructive: the protected zero opens one end of a
    // deduction chain, while the repeated fronts keep mines distributed across
    // the board. The small symmetry family covers every first-reveal coordinate
    // in the production Extreme grid and is still independently verified here.
    if configuration == Difficulty.extreme.configuration {
      let patterns = [
        (modulus: 11, row: 1, column: 3),
        (modulus: 11, row: 3, column: 1),
        (modulus: 11, row: 1, column: 8),
        (modulus: 11, row: 8, column: 10),
        (modulus: 11, row: 2, column: 5),
        (modulus: 11, row: 5, column: 2),
        (modulus: 11, row: 4, column: 7),
        (modulus: 11, row: 7, column: 4),
        (modulus: 13, row: 1, column: 5),
        (modulus: 13, row: 5, column: 1),
        (modulus: 13, row: 2, column: 7),
        (modulus: 13, row: 7, column: 2),
        (modulus: 13, row: 3, column: 8),
        (modulus: 13, row: 8, column: 3),
        (modulus: 17, row: 3, column: 7),
        (modulus: 17, row: 7, column: 3),
        (modulus: 17, row: 5, column: 9),
        (modulus: 17, row: 9, column: 5),
      ]
      let rotation = Int(seed % UInt64(patterns.count))
      var hardestBoard: GeneratedBoard?
      var hardestThreeBV = Int.min
      var hardestPasses = Int.min
      for offset in patterns.indices {
        let pattern = patterns[(rotation + offset) % patterns.count]
        let mines = modularMineSet(
          candidates: candidates,
          mineCount: configuration.mineCount,
          modulus: pattern.modulus,
          rowMultiplier: pattern.row,
          columnMultiplier: pattern.column
        )
        let board = GeneratedBoard(configuration: configuration, seed: seed, mines: mines)
        let report = solver.verify(board, firstReveal: firstReveal)
        guard report.isSolved else { continue }
        let threeBV = scorer.threeBV(board)
        // 3BV is the primary workload measure. Deduction passes break ties so
        // boards with longer logical chains win over equally sized openings.
        if threeBV > hardestThreeBV
          || (threeBV == hardestThreeBV && report.deductionPasses > hardestPasses)
        {
          hardestBoard = board
          hardestThreeBV = threeBV
          hardestPasses = report.deductionPasses
        }
      }
      if let hardestBoard, hardestThreeBV >= 150, hardestPasses >= 20 {
        // The modular boards are reliable seeds at this unusually high mine
        // density, but returning one directly exposes its diagonal bands to
        // the player. Run a seeded local search over mine/safe swaps and retain
        // only layouts that the no-guess solver can still finish. This keeps
        // the constructive reliability while removing the visible template.
        return randomizeExtremeSeed(
          hardestBoard,
          candidates: candidates,
          firstReveal: firstReveal,
          random: &random
        )
      }
      throw BoardGenerationError.unableToGenerateNoGuessBoard(attempts: patterns.count)
    }

    for _ in 0..<randomAttemptsBeforeFallback {
      shuffle(&candidates, using: &random)
      consider(
        GeneratedBoard(configuration: configuration, seed: seed, mines: Set(candidates.prefix(configuration.mineCount))),
        firstReveal: firstReveal,
        bestBoard: &bestBoard,
        bestScore: &bestScore
      )
    }

    for mines in structuredMineSets(
      candidates: candidates,
      mineCount: configuration.mineCount,
      firstReveal: firstReveal,
      random: &random
    ) {
      consider(
        GeneratedBoard(configuration: configuration, seed: seed, mines: mines),
        firstReveal: firstReveal,
        bestBoard: &bestBoard,
        bestScore: &bestScore
      )
    }

    for _ in randomAttemptsBeforeFallback..<maximumAttempts {
      shuffle(&candidates, using: &random)
      consider(
        GeneratedBoard(configuration: configuration, seed: seed, mines: Set(candidates.prefix(configuration.mineCount))),
        firstReveal: firstReveal,
        bestBoard: &bestBoard,
        bestScore: &bestScore
      )
    }

    if let bestBoard { return bestBoard }
    throw BoardGenerationError.unableToGenerateNoGuessBoard(attempts: maximumAttempts)
  }

  private func consider(
    _ board: GeneratedBoard,
    firstReveal: CellCoordinate,
    bestBoard: inout GeneratedBoard?,
    bestScore: inout Int
  ) {
    guard solver.verify(board, firstReveal: firstReveal).isSolved else { return }
    let score = scorer.threeBV(board)
    if score > bestScore {
      bestScore = score
      bestBoard = board
    }
  }

  private func randomizeExtremeSeed(
    _ seedBoard: GeneratedBoard,
    candidates: [CellCoordinate],
    firstReveal: CellCoordinate,
    random: inout SplitMix64
  ) -> GeneratedBoard {
    var current = seedBoard
    var currentReport = solver.verify(current, firstReveal: firstReveal)
    var currentThreeBV = scorer.threeBV(current)
    var currentPatternPenalty = patternPenalty(current)
    var acceptedMutationCount = 0

    // A bounded search keeps first-click latency predictable. Accepting a
    // small difficulty step down lets the walk escape its initial template;
    // the returned board still has a deliberately high minimum workload.
    for _ in 0..<6 {
      var revisedMines = current.mines
      // Mutate several cells per verification so every accepted step breaks
      // a meaningful part of the seed's visual rhythm.
      for _ in 0..<3 {
        // Set iteration order is intentionally randomized by Swift. Sort before
        // seeded selection so an identical game seed always creates the same
        // board across launches and test processes.
        let mines = revisedMines.sorted()
        guard !mines.isEmpty else { break }
        revisedMines.remove(mines[random.next(upperBound: mines.count)])
        for _ in 0..<24 {
          let candidate = candidates[random.next(upperBound: candidates.count)]
          if !revisedMines.contains(candidate) {
            revisedMines.insert(candidate)
            break
          }
        }
      }
      guard revisedMines.count == current.configuration.mineCount else { continue }
      let proposal = GeneratedBoard(
        configuration: current.configuration,
        seed: current.seed,
        mines: revisedMines
      )
      let report = solver.verify(proposal, firstReveal: firstReveal)
      guard report.isSolved else { continue }
      let threeBV = scorer.threeBV(proposal)
      guard threeBV >= max(300, currentThreeBV - 2), report.deductionPasses >= 20 else { continue }
      let penalty = patternPenalty(proposal)
      let improvesWalk = penalty < currentPatternPenalty
        || threeBV > currentThreeBV + 8
        || (penalty == currentPatternPenalty && report.deductionPasses > currentReport.deductionPasses)
      guard improvesWalk else { continue }

      current = proposal
      acceptedMutationCount += 1
      currentReport = report
      currentThreeBV = threeBV
      currentPatternPenalty = penalty
    }
#if DEBUG
    if ProcessInfo.processInfo.environment["MINESWEEPER_GENERATOR_DIAGNOSTICS"] == "1" {
      print("Extreme accepted mutations: \(acceptedMutationCount), penalty: \(patternPenalty(seedBoard)) -> \(patternPenalty(current))")
    }
#endif
    // Return the end of the verified random walk, not merely the highest 3BV
    // intermediate; otherwise a visually regular seed can win by a few score
    // points and undo the purpose of the mutation pass.
    return current
  }

  /// Penalizes the conspicuous horizontal/vertical mine runs produced by a
  /// constructive seed. Random-looking high-density boards naturally retain
  /// clusters, but not a screen full of equally spaced bars.
  private func patternPenalty(_ board: GeneratedBoard) -> Int {
    var penalty = 0
    func addRun(_ length: Int) {
      guard length >= 3 else { return }
      penalty += length * length
    }

    for row in 0..<board.configuration.height {
      var run = 0
      for column in 0..<board.configuration.width {
        if board.isMine(at: CellCoordinate(row: row, column: column)) {
          run += 1
        } else {
          addRun(run)
          run = 0
        }
      }
      addRun(run)
    }
    for column in 0..<board.configuration.width {
      var run = 0
      for row in 0..<board.configuration.height {
        if board.isMine(at: CellCoordinate(row: row, column: column)) {
          run += 1
        } else {
          addRun(run)
          run = 0
        }
      }
      addRun(run)
    }
    return penalty
  }

  private func allCoordinates(in configuration: BoardConfiguration) -> [CellCoordinate] {
    (0..<configuration.cellCount).compactMap(configuration.coordinate)
  }

  private func shuffle(_ values: inout [CellCoordinate], using random: inout SplitMix64) {
    guard values.count > 1 else { return }
    for index in stride(from: values.count - 1, through: 1, by: -1) {
      values.swapAt(index, random.next(upperBound: index + 1))
    }
  }

  private func structuredMineSets(
    candidates: [CellCoordinate],
    mineCount: Int,
    firstReveal: CellCoordinate,
    random: inout SplitMix64
  ) -> [Set<CellCoordinate>] {
    var tieBreakers: [CellCoordinate: UInt64] = [:]
    for coordinate in candidates { tieBreakers[coordinate] = random.next() }

    func makeSet(distance: (CellCoordinate) -> Int) -> Set<CellCoordinate> {
      let ordered = candidates.sorted { left, right in
        let leftDistance = distance(left)
        let rightDistance = distance(right)
        if leftDistance != rightDistance { return leftDistance > rightDistance }
        return tieBreakers[left, default: 0] < tieBreakers[right, default: 0]
      }
      return Set(ordered.prefix(mineCount))
    }

    return [
      makeSet {
        max(abs($0.row - firstReveal.row), abs($0.column - firstReveal.column))
      },
      makeSet {
        abs($0.row - firstReveal.row) + abs($0.column - firstReveal.column)
      },
      makeSet {
        let row = $0.row - firstReveal.row
        let column = $0.column - firstReveal.column
        return row * row + column * column
      },
    ]
  }

  private func modularMineSet(
    candidates: [CellCoordinate],
    mineCount: Int,
    modulus: Int,
    rowMultiplier: Int,
    columnMultiplier: Int
  ) -> Set<CellCoordinate> {
    func residue(_ coordinate: CellCoordinate) -> Int {
      let value = coordinate.row * rowMultiplier + coordinate.column * columnMultiplier
      let remainder = value % modulus
      return remainder >= 0 ? remainder : remainder + modulus
    }
    let ordered = candidates.sorted { left, right in
      let leftResidue = residue(left)
      let rightResidue = residue(right)
      return leftResidue == rightResidue ? left < right : leftResidue < rightResidue
    }
    return Set(ordered.prefix(mineCount))
  }
}

/// Fast personal-play generator used by the iOS replica app to match the Android app's
/// immediate first tap. It preserves first-tap and neighbor safety but does not run the
/// no-guess verifier, so board materialization is effectively instant on device.
public struct FastBoardGenerator: BoardGenerating, Sendable {
  public var protectsFirstRevealNeighbors: Bool

  public init(protectsFirstRevealNeighbors: Bool = true) {
    self.protectsFirstRevealNeighbors = protectsFirstRevealNeighbors
  }

  public func generate(
    configuration: BoardConfiguration,
    firstReveal: CellCoordinate,
    seed: UInt64
  ) throws -> GeneratedBoard {
    guard configuration.contains(firstReveal) else { throw BoardGenerationError.invalidFirstReveal }

    var protected: Set<CellCoordinate> = [firstReveal]
    if protectsFirstRevealNeighbors {
      protected.formUnion(configuration.neighbors(of: firstReveal))
    }

    var candidates = allCoordinates(in: configuration).filter { !protected.contains($0) }
    if candidates.count < configuration.mineCount {
      protected = [firstReveal]
      candidates = allCoordinates(in: configuration).filter { !protected.contains($0) }
      guard candidates.count >= configuration.mineCount else {
        throw BoardGenerationError.insufficientUnprotectedCells
      }
    }

    var random = SplitMix64(seed: seed)
    for index in stride(from: candidates.count - 1, through: 1, by: -1) {
      candidates.swapAt(index, random.next(upperBound: index + 1))
    }
    return GeneratedBoard(
      configuration: configuration,
      seed: seed,
      mines: Set(candidates.prefix(configuration.mineCount))
    )
  }

  private func allCoordinates(in configuration: BoardConfiguration) -> [CellCoordinate] {
    (0..<configuration.cellCount).compactMap(configuration.coordinate)
  }
}
