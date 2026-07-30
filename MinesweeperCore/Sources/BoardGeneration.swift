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
