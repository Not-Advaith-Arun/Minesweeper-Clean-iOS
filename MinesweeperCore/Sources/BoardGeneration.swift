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

private struct BoardTopology: Sendable {
  let neighbors: [[CellCoordinate]]
  let neighborIndices: [[Int]]
}

/// Board geometry is immutable and rebuilding it dominated the solver's hot loop, so it is
/// computed once per configuration and shared behind a lock.
private final class BoardTopologyCache: @unchecked Sendable {
  static let shared = BoardTopologyCache()

  private let lock = NSLock()
  private var storage: [BoardConfiguration: BoardTopology] = [:]

  func topology(for configuration: BoardConfiguration) -> BoardTopology {
    lock.lock()
    if let cached = storage[configuration] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let coordinates = (0..<configuration.cellCount).compactMap(configuration.coordinate(for:))
    let neighbors = coordinates.map(configuration.neighbors(of:))
    let topology = BoardTopology(
      neighbors: neighbors,
      neighborIndices: neighbors.map { $0.compactMap(configuration.index(for:)) }
    )

    lock.lock()
    let result = storage[configuration] ?? topology
    storage[configuration] = result
    lock.unlock()
    return result
  }
}

/// A mine layout that keeps its adjacent-mine counts up to date as mines move, so the generator
/// can ask what a single swap does to the board's openings without rebuilding anything.
private struct MineLayout {
  let configuration: BoardConfiguration
  let topology: BoardTopology
  private(set) var mines: Set<CellCoordinate>
  private var mineFlags: [Bool]
  private var adjacentMineCounts: [Int]

  init(configuration: BoardConfiguration, topology: BoardTopology, mines: Set<CellCoordinate>) {
    self.configuration = configuration
    self.topology = topology
    self.mines = mines
    mineFlags = [Bool](repeating: false, count: configuration.cellCount)
    adjacentMineCounts = [Int](repeating: 0, count: configuration.cellCount)
    for mine in mines {
      guard let index = configuration.index(for: mine) else { continue }
      mineFlags[index] = true
      for neighbor in topology.neighborIndices[index] { adjacentMineCounts[neighbor] += 1 }
    }
  }

  func contains(_ coordinate: CellCoordinate) -> Bool { mines.contains(coordinate) }

  func isMine(at index: Int) -> Bool { mineFlags[index] }

  mutating func move(from source: CellCoordinate, to destination: CellCoordinate) {
    guard let sourceIndex = configuration.index(for: source),
      let destinationIndex = configuration.index(for: destination)
    else { return }
    mines.remove(source)
    mines.insert(destination)
    mineFlags[sourceIndex] = false
    mineFlags[destinationIndex] = true
    for neighbor in topology.neighborIndices[sourceIndex] { adjacentMineCounts[neighbor] -= 1 }
    for neighbor in topology.neighborIndices[destinationIndex] { adjacentMineCounts[neighbor] += 1 }
  }

  /// Safe cells with no adjacent mine. Each one floods a whole region on a single click, which
  /// is what costs a high-density board most of its 3BV.
  func openings(excluding opening: Int) -> [Int] {
    (0..<adjacentMineCounts.count).filter {
      $0 != opening && !mineFlags[$0] && adjacentMineCounts[$0] == 0
    }
  }

  func openingCount(excluding opening: Int) -> Int {
    var total = 0
    for index in 0..<adjacentMineCounts.count
    where index != opening && !mineFlags[index] && adjacentMineCounts[index] == 0 {
      total += 1
    }
    return total
  }

  /// True when taking the mine off `coordinate` leaves no new opening behind: the vacated cell
  /// still touches a mine, and so does every safe neighbor that would lose one.
  func isSafeToVacate(_ coordinate: CellCoordinate, cap: CellCoordinate) -> Bool {
    guard let index = configuration.index(for: coordinate), index != configuration.index(for: cap)
    else { return false }
    guard adjacentMineCounts[index] >= 1 else { return false }
    return topology.neighborIndices[index].allSatisfy { neighbor in
      mineFlags[neighbor] || adjacentMineCounts[neighbor] >= 2
    }
  }
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
  public let subsetDeductionPasses: Int
  public let exactDeductionPasses: Int

  public init(
    status: SolverStatus,
    revealedSafeCells: Int,
    inferredMines: Int,
    deductionPasses: Int,
    subsetDeductionPasses: Int = 0,
    exactDeductionPasses: Int = 0
  ) {
    self.status = status
    self.revealedSafeCells = revealedSafeCells
    self.inferredMines = inferredMines
    self.deductionPasses = deductionPasses
    self.subsetDeductionPasses = subsetDeductionPasses
    self.exactDeductionPasses = exactDeductionPasses
  }

  public var isSolved: Bool { status == .solved }
  public var advancedDeductionPasses: Int {
    subsetDeductionPasses + exactDeductionPasses
  }
}

/// The solver's final knowledge state alongside its report. Generation needs the cells a player
/// would have opened or flagged when a layout stalls, so it can perturb the ambiguous frontier
/// instead of resampling the whole board.
public struct SolverAnalysis: Sendable {
  public let report: SolverReport
  public let revealed: Set<CellCoordinate>
  public let knownMines: Set<CellCoordinate>

  public init(
    report: SolverReport,
    revealed: Set<CellCoordinate>,
    knownMines: Set<CellCoordinate>
  ) {
    self.report = report
    self.revealed = revealed
    self.knownMines = knownMines
  }
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
    analyze(board, firstReveal: firstReveal).report
  }

  /// Runs the deduction loop and also returns the knowledge state it ended with.
  public func analyze(_ board: GeneratedBoard, firstReveal: CellCoordinate) -> SolverAnalysis {
    guard board.configuration.contains(firstReveal), !board.isMine(at: firstReveal) else {
      return SolverAnalysis(
        report: SolverReport(
          status: .inconsistent, revealedSafeCells: 0, inferredMines: 0, deductionPasses: 0),
        revealed: [],
        knownMines: []
      )
    }

    // Extreme verification revisits the same clues over many deduction passes.
    // Cache immutable topology once per candidate instead of rebuilding every
    // neighbor list and mine count inside the solver's hot loop.
    let topology = BoardTopologyCache.shared.topology(for: board.configuration)
    let neighbors = topology.neighbors
    let adjacentMineCounts = neighbors.map { adjacent in
      adjacent.reduce(into: 0) { count, coordinate in
        if board.mines.contains(coordinate) { count += 1 }
      }
    }

    var revealed: Set<CellCoordinate> = []
    var knownMines: Set<CellCoordinate> = []
    var subsetDeductionPasses = 0
    var exactDeductionPasses = 0
    reveal(
      firstReveal,
      on: board,
      neighbors: neighbors,
      adjacentMineCounts: adjacentMineCounts,
      into: &revealed
    )
    var pass = 0

    func result(_ status: SolverStatus, pass: Int) -> SolverAnalysis {
      SolverAnalysis(
        report: SolverReport(
          status: status,
          revealedSafeCells: revealed.count,
          inferredMines: knownMines.count,
          deductionPasses: pass,
          subsetDeductionPasses: subsetDeductionPasses,
          exactDeductionPasses: exactDeductionPasses
        ),
        revealed: revealed,
        knownMines: knownMines
      )
    }

    while pass < maximumDeductionPasses {
      if revealed.count == board.configuration.safeCellCount {
        return result(.solved, pass: pass)
      }
      pass += 1

      let build = makeConstraints(
        on: board,
        neighbors: neighbors,
        adjacentMineCounts: adjacentMineCounts,
        revealed: revealed,
        knownMines: knownMines
      )
      if build.isInconsistent {
        return result(.inconsistent, pass: pass)
      }

      var safeDeductions: Set<CellCoordinate> = []
      var mineDeductions: Set<CellCoordinate> = []
      applyDirectDeductions(
        build.constraints,
        safe: &safeDeductions,
        mines: &mineDeductions
      )
      let directSafe = safeDeductions
      let directMines = mineDeductions
      applySubsetDeductions(
        build.constraints,
        safe: &safeDeductions,
        mines: &mineDeductions
      )
      if safeDeductions != directSafe || mineDeductions != directMines {
        subsetDeductionPasses += 1
      }

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
        if !exact.safe.isEmpty || !exact.mines.isEmpty {
          exactDeductionPasses += 1
        }
      }

      if !safeDeductions.isDisjoint(with: mineDeductions) {
        return result(.inconsistent, pass: pass)
      }

      mineDeductions.subtract(revealed)
      safeDeductions.subtract(knownMines)
      if safeDeductions.isEmpty && mineDeductions.isEmpty { break }

      knownMines.formUnion(mineDeductions)
      for coordinate in safeDeductions {
        // This check validates deductions after the fact; it is not used to choose a move.
        guard !board.isMine(at: coordinate) else {
          return result(.inconsistent, pass: pass)
        }
        reveal(
          coordinate,
          on: board,
          neighbors: neighbors,
          adjacentMineCounts: adjacentMineCounts,
          into: &revealed
        )
      }
    }

    let status: SolverStatus =
      revealed.count == board.configuration.safeCellCount ? .solved : .stalled
    return result(status, pass: pass)
  }

  private struct Constraint: Hashable {
    let cells: Set<CellCoordinate>
    let mines: Int
  }

  private func makeConstraints(
    on board: GeneratedBoard,
    neighbors: [[CellCoordinate]],
    adjacentMineCounts: [Int],
    revealed: Set<CellCoordinate>,
    knownMines: Set<CellCoordinate>
  ) -> (constraints: [Constraint], isInconsistent: Bool) {
    var unique: Set<Constraint> = []
    for coordinate in revealed {
      guard let index = board.configuration.index(for: coordinate) else { continue }
      let adjacent = neighbors[index]
      let knownAdjacent = adjacent.reduce(into: 0) { total, neighbor in
        if knownMines.contains(neighbor) { total += 1 }
      }
      let unknown = Set(adjacent.filter { !revealed.contains($0) && !knownMines.contains($0) })
      let remaining = adjacentMineCounts[index] - knownAdjacent
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
    neighbors: [[CellCoordinate]],
    adjacentMineCounts: [Int],
    into revealed: inout Set<CellCoordinate>
  ) {
    guard !board.isMine(at: start), !revealed.contains(start) else { return }
    var queue = [start]
    var cursor = 0
    revealed.insert(start)
    while cursor < queue.count {
      let coordinate = queue[cursor]
      cursor += 1
      guard let index = board.configuration.index(for: coordinate),
        adjacentMineCounts[index] == 0
      else { continue }
      for neighbor in neighbors[index]
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

/// Separates logical difficulty from whole-board visual repetition. Natural
/// clusters, adjacent mines, runs, and 2×2 groups remain valid; this scorer is
/// used only to detect a conspicuous global lattice signature.
/// Everything the generator measures about how mines are spread over a board.
public struct BoardDistributionMetrics: Equatable, Sendable {
  /// Largest normalized non-DC peak of the 2D periodogram. Rows, columns, diagonals,
  /// checkerboards, and arbitrary lattice slopes all show up here; local clusters do not.
  public let spectralPeak: Double
  /// Largest |z| of mine-pair co-occurrence at Chebyshev lags of four or more, so adjacency,
  /// clusters, and 2×2 groups cannot influence it.
  public let longLagCorrelationZ: Double
  /// Residue-family chi-square excess, retained as a cheap secondary check.
  public let patternPenalty: Int
  public let solidTwoByTwoBlockCount: Int
}

/// Acceptance thresholds for ``BoardDistributionMetrics``.
///
/// Measured over 250 uniformly random Extreme layouts the spectral peak stays under 12, the
/// long-lag z under 4.6, and the residue penalty under 21; deliberately cluster-heavy controls
/// score no higher. Synthetic stripe, diagonal, and checkerboard lattices score 90 and above
/// spectrally. These limits sit in the wide gap between the two.
public struct BoardDistributionLimits: Equatable, Sendable {
  public var maximumSpectralPeak: Double
  public var maximumLongLagCorrelationZ: Double
  public var maximumPatternPenalty: Int

  public init(
    maximumSpectralPeak: Double = 16,
    maximumLongLagCorrelationZ: Double = 6,
    maximumPatternPenalty: Int = 100
  ) {
    self.maximumSpectralPeak = maximumSpectralPeak
    self.maximumLongLagCorrelationZ = maximumLongLagCorrelationZ
    self.maximumPatternPenalty = maximumPatternPenalty
  }

  public func admits(_ metrics: BoardDistributionMetrics) -> Bool {
    metrics.spectralPeak <= maximumSpectralPeak
      && metrics.longLagCorrelationZ <= maximumLongLagCorrelationZ
      && metrics.patternPenalty <= maximumPatternPenalty
  }
}

public struct BoardDistributionScorer: Sendable {
  public init() {}

  public func metrics(_ board: GeneratedBoard) -> BoardDistributionMetrics {
    BoardDistributionMetrics(
      spectralPeak: spectralPeak(board),
      longLagCorrelationZ: maximumLongLagCorrelationZ(board),
      patternPenalty: patternPenalty(board),
      solidTwoByTwoBlockCount: solidTwoByTwoBlockCount(board)
    )
  }

  /// Normalized peak of the non-DC 2D periodogram, computed as two separable passes.
  ///
  /// A uniform layout spreads its power evenly and peaks near the extreme-value scale of an
  /// exponential sample; any repeated template concentrates power into the few frequencies that
  /// describe it and peaks an order of magnitude higher.
  public func spectralPeak(_ board: GeneratedBoard) -> Double {
    let height = board.configuration.height
    let width = board.configuration.width
    guard height > 1, width > 1 else { return 0 }
    let cellCount = Double(height * width)
    let density = Double(board.configuration.mineCount) / cellCount
    guard density > 0, density < 1 else { return 0 }

    var residuals = [Double](repeating: -density, count: height * width)
    for mine in board.mines {
      residuals[mine.row * width + mine.column] += 1
    }

    let columnCosines = (0..<width).map { frequency in
      (0..<width).map { cos(-2 * .pi * Double(frequency * $0) / Double(width)) }
    }
    let columnSines = (0..<width).map { frequency in
      (0..<width).map { sin(-2 * .pi * Double(frequency * $0) / Double(width)) }
    }
    let rowCosines = (0..<height).map { frequency in
      (0..<height).map { cos(-2 * .pi * Double(frequency * $0) / Double(height)) }
    }
    let rowSines = (0..<height).map { frequency in
      (0..<height).map { sin(-2 * .pi * Double(frequency * $0) / Double(height)) }
    }

    // Transform every row, then every column of the result.
    var rowRealParts = [Double](repeating: 0, count: height * width)
    var rowImaginaryParts = [Double](repeating: 0, count: height * width)
    for row in 0..<height {
      for frequency in 0..<width {
        var real = 0.0
        var imaginary = 0.0
        let cosines = columnCosines[frequency]
        let sines = columnSines[frequency]
        for column in 0..<width {
          let value = residuals[row * width + column]
          real += value * cosines[column]
          imaginary += value * sines[column]
        }
        rowRealParts[row * width + frequency] = real
        rowImaginaryParts[row * width + frequency] = imaginary
      }
    }

    let normalization = cellCount * density * (1 - density)
    var peak = 0.0
    for columnFrequency in 0..<width {
      for rowFrequency in 0..<height {
        if rowFrequency == 0 && columnFrequency == 0 { continue }
        var real = 0.0
        var imaginary = 0.0
        let cosines = rowCosines[rowFrequency]
        let sines = rowSines[rowFrequency]
        for row in 0..<height {
          let sourceReal = rowRealParts[row * width + columnFrequency]
          let sourceImaginary = rowImaginaryParts[row * width + columnFrequency]
          real += sourceReal * cosines[row] - sourceImaginary * sines[row]
          imaginary += sourceReal * sines[row] + sourceImaginary * cosines[row]
        }
        peak = max(peak, (real * real + imaginary * imaginary) / normalization)
      }
    }
    return peak
  }

  /// Largest standardized deviation of mine-pair co-occurrence over displacements of at least
  /// four cells. Ignoring the short lags keeps legitimate clustering out of the measurement.
  public func maximumLongLagCorrelationZ(_ board: GeneratedBoard) -> Double {
    let height = board.configuration.height
    let width = board.configuration.width
    let cellCount = height * width
    let mineCount = board.configuration.mineCount
    guard cellCount > 1, mineCount > 1, mineCount < cellCount else { return 0 }

    var isMine = [Bool](repeating: false, count: cellCount)
    for mine in board.mines { isMine[mine.row * width + mine.column] = true }
    let pairProbability =
      Double(mineCount) * Double(mineCount - 1) / (Double(cellCount) * Double(cellCount - 1))

    var best = 0.0
    for rowLag in -(height - 1)...(height - 1) {
      for columnLag in 0..<width {
        if rowLag <= 0 && columnLag == 0 { continue }
        if max(abs(rowLag), columnLag) < 4 { continue }
        let rowStart = max(0, -rowLag)
        let rowEnd = min(height, height - rowLag)
        guard rowStart < rowEnd else { continue }
        let overlappingPairs = (rowEnd - rowStart) * (width - columnLag)
        guard overlappingPairs >= 72 else { continue }

        var observed = 0
        for row in rowStart..<rowEnd {
          let base = row * width
          let shifted = (row + rowLag) * width + columnLag
          for column in 0..<(width - columnLag) where isMine[base + column] {
            if isMine[shifted + column] { observed += 1 }
          }
        }
        let expected = Double(overlappingPairs) * pairProbability
        let deviation = (Double(overlappingPairs) * pairProbability * (1 - pairProbability))
          .squareRoot()
        guard deviation > 0 else { continue }
        best = max(best, abs((Double(observed) - expected) / deviation))
      }
    }
    return best
  }

  public func solidTwoByTwoBlockCount(_ board: GeneratedBoard) -> Int {
    guard board.configuration.width > 1, board.configuration.height > 1 else { return 0 }
    var count = 0
    for row in 0..<(board.configuration.height - 1) {
      for column in 0..<(board.configuration.width - 1) {
        let cells = [
          CellCoordinate(row: row, column: column),
          CellCoordinate(row: row, column: column + 1),
          CellCoordinate(row: row + 1, column: column),
          CellCoordinate(row: row + 1, column: column + 1),
        ]
        if cells.allSatisfy(board.mines.contains) { count += 1 }
      }
    }
    return count
  }

  public func patternPenalty(_ board: GeneratedBoard) -> Int {
    // Clusters, adjacent mines, 2×2 groups, and short runs are all legitimate
    // Minesweeper structure and must not be optimized away. Detect only a
    // global modular/lattice signature, the fingerprint a constructed layout
    // leaves. For each prime modulus, compare mine occupancy across every normalized
    // linear residue. A random or naturally clustered board stays near its
    // expected density; a repeated diagonal template concentrates mines into
    // a small residue family and produces a large chi-square outlier.
    let density = Double(board.configuration.mineCount)
      / Double(board.configuration.cellCount)
    let moduli = [5, 7, 11, 13, 17]
    var penalty = 0

    func addResiduePenalty(modulus: Int, slope: Int?) {
      var cellCounts = Array(repeating: 0, count: modulus)
      var mineCounts = Array(repeating: 0, count: modulus)
      for row in 0..<board.configuration.height {
        for column in 0..<board.configuration.width {
          let raw = slope.map { row + $0 * column } ?? column
          let residue = ((raw % modulus) + modulus) % modulus
          cellCounts[residue] += 1
          if board.isMine(at: CellCoordinate(row: row, column: column)) {
            mineCounts[residue] += 1
          }
        }
      }

      var chiSquare = 0.0
      for residue in 0..<modulus {
        let expected = Double(cellCounts[residue]) * density
        guard expected > 0 else { continue }
        let difference = Double(mineCounts[residue]) - expected
        chiSquare += difference * difference / expected
      }
      // The expected random value is roughly modulus - 1. Leave generous
      // headroom for organic clustering and score only obvious global bias.
      let excess = max(0, chiSquare - Double(modulus) * 2.4)
      penalty += Int((excess * 8).rounded(.down))
    }

    for modulus in moduli {
      addResiduePenalty(modulus: modulus, slope: nil)
      for slope in 0..<modulus {
        addResiduePenalty(modulus: modulus, slope: slope)
      }
    }
    return penalty
  }
}

public struct HardNoGuessBoardGenerator: BoardGenerating, Sendable {
  public var maximumAttempts: Int
  public var randomAttemptsBeforeFallback: Int
  public var solver: NoGuessSolver
  public var scorer: BoardDifficultyScorer
  public var distributionScorer: BoardDistributionScorer
  /// Independent random layouts the organic search is allowed to start from.
  public var organicRestarts: Int
  /// Guided swaps attempted on one starting layout before abandoning it.
  public var organicPerturbations: Int
  /// Consecutive rejected swaps that force acceptance so the walk can leave a local optimum.
  public var organicPatience: Int
  /// Times a swap is resampled in search of one that does not reopen the board.
  public var openingAwareResamples: Int
  /// Zero cells left uncapped besides the first reveal. Each one floods a region on a single
  /// click, so this trades a little 3BV for the clustering a fully capped board loses.
  public var openingAllowance: Int
  public var minimumThreeBV: Int
  public var minimumDeductionPasses: Int
  public var minimumAdvancedDeductionPasses: Int
  public var distributionLimits: BoardDistributionLimits

  public init(
    maximumAttempts: Int = 2_048,
    randomAttemptsBeforeFallback: Int = 1_920,
    solver: NoGuessSolver = NoGuessSolver(),
    scorer: BoardDifficultyScorer = BoardDifficultyScorer(),
    distributionScorer: BoardDistributionScorer = BoardDistributionScorer(),
    organicRestarts: Int = 3,
    organicPerturbations: Int = 300,
    organicPatience: Int = 12,
    openingAwareResamples: Int = 12,
    openingAllowance: Int = 4,
    minimumThreeBV: Int = 350,
    minimumDeductionPasses: Int = 20,
    minimumAdvancedDeductionPasses: Int = 4,
    distributionLimits: BoardDistributionLimits = BoardDistributionLimits()
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.randomAttemptsBeforeFallback = max(0, min(randomAttemptsBeforeFallback, maximumAttempts))
    self.solver = solver
    self.scorer = scorer
    self.distributionScorer = distributionScorer
    self.organicRestarts = max(1, organicRestarts)
    self.organicPerturbations = max(1, organicPerturbations)
    self.organicPatience = max(1, organicPatience)
    self.openingAwareResamples = max(1, openingAwareResamples)
    self.openingAllowance = max(0, openingAllowance)
    self.minimumThreeBV = minimumThreeBV
    self.minimumDeductionPasses = minimumDeductionPasses
    self.minimumAdvancedDeductionPasses = minimumAdvancedDeductionPasses
    self.distributionLimits = distributionLimits
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

    // Uniform layouts at Extreme's 26% density are almost never no-guess, so the generator
    // repairs one instead of resampling it. Solve the layout, look at where the deduction chain
    // stalls, move a mine off that ambiguous frontier into territory no clue touches yet, and
    // solve again. Simon Tatham's mines.c uses the same solver-directed perturbation. Because no
    // template is ever imposed, the result keeps a random layout's statistics — adjacency, runs,
    // clusters, and 2×2 mine groups all occur at their natural rates.
    if configuration.mineCount * 5 >= configuration.cellCount {
      return try organicNoGuessBoard(
        configuration: configuration,
        firstReveal: firstReveal,
        candidates: candidates,
        seed: seed,
        random: &random
      )
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

  /// Repairs a uniformly random layout into a verified no-guess board.
  ///
  /// Two ideas do the work. First, openings are capped before the solver ever runs: a random
  /// layout at this density scatters roughly fifty zero cells, each of which floods a large
  /// region on one click and costs the board most of its 3BV, so every zero cell is covered by
  /// a mine donated from a spot that will not become a new zero. Second, the layout is repaired
  /// rather than resampled — solve it, find the ambiguous frontier where the deduction chain
  /// stalls, move one mine between that frontier and the territory no clue touches yet, and
  /// solve again, as Simon Tatham's mines.c does. Swaps that would reopen the board are
  /// resampled before the solver is consulted, so the walk stays in the high-3BV region.
  ///
  /// No template is ever imposed, so adjacency, runs, clusters, and 2×2 mine groups all occur
  /// at the rates a random layout produces them.
  private func organicNoGuessBoard(
    configuration: BoardConfiguration,
    firstReveal: CellCoordinate,
    candidates: [CellCoordinate],
    seed: UInt64,
    random: inout SplitMix64
  ) throws -> GeneratedBoard {
    let topology = BoardTopologyCache.shared.topology(for: configuration)
    guard let openingIndex = configuration.index(for: firstReveal) else {
      throw BoardGenerationError.invalidFirstReveal
    }
    var protectedCells: Set<CellCoordinate> = [firstReveal]
    protectedCells.formUnion(configuration.neighbors(of: firstReveal))
    var solveCount = 0
    var fallback: (board: GeneratedBoard, threeBV: Int, isDistributionClean: Bool)?

    for _ in 0..<organicRestarts {
      var layout = MineLayout(
        configuration: configuration,
        topology: topology,
        mines: randomMineSet(from: candidates, count: configuration.mineCount, random: &random)
      )
      capOpenings(
        in: &layout,
        candidates: candidates,
        protectedCells: protectedCells,
        openingIndex: openingIndex,
        random: &random
      )

      var board = GeneratedBoard(configuration: configuration, seed: seed, mines: layout.mines)
      var analysis = solver.analyze(board, firstReveal: firstReveal)
      solveCount += 1
      var rejections = 0

      for _ in 0..<organicPerturbations {
        if analysis.report.isSolved {
          let threeBV = scorer.threeBV(board)
          let isDistributionClean = distributionLimits.admits(distributionScorer.metrics(board))
          if threeBV >= minimumThreeBV,
            analysis.report.deductionPasses >= minimumDeductionPasses,
            analysis.report.advancedDeductionPasses >= minimumAdvancedDeductionPasses,
            isDistributionClean
          {
            return board
          }
          // Solvable but not hard enough to ship. Keep it as a floor and shake the layout
          // instead of discarding a verified starting point. A layout that passes the
          // distribution check outranks a harder one that does not, so the last resort is
          // never a patterned board when an unpatterned one was seen.
          let rank = (isDistributionClean ? 1 : 0, threeBV)
          let bestRank = fallback.map { ($0.isDistributionClean ? 1 : 0, $0.threeBV) } ?? (-1, -1)
          if rank > bestRank {
            fallback = (board, threeBV, isDistributionClean)
          }
          rejections = organicPatience
        }

        guard
          let proposedLayout = repairProposal(
            for: layout,
            analysis: analysis,
            candidates: candidates,
            openingIndex: openingIndex,
            swaps: rejections >= organicPatience ? 3 : 1,
            random: &random
          )
        else { break }
        let proposedBoard = GeneratedBoard(
          configuration: configuration,
          seed: seed,
          mines: proposedLayout.mines
        )
        let proposedAnalysis = solver.analyze(proposedBoard, firstReveal: firstReveal)
        solveCount += 1

        let improves =
          proposedAnalysis.report.revealedSafeCells >= analysis.report.revealedSafeCells
        if improves || rejections >= organicPatience {
          layout = proposedLayout
          board = proposedBoard
          analysis = proposedAnalysis
          // Reset on a forced acceptance too. Carrying the count past the kick would leave
          // the walk permanently above the patience threshold, turning the hill climb into an
          // undirected random walk for the rest of the restart.
          rejections = 0
        } else {
          rejections += 1
        }
      }
    }

    if let fallback { return fallback.board }
    throw BoardGenerationError.unableToGenerateNoGuessBoard(attempts: solveCount)
  }

  /// Covers every zero cell outside the first reveal by moving a mine onto one of its neighbors,
  /// taken from a mine whose removal leaves no new zero behind. Purely local bookkeeping — the
  /// solver is not involved.
  private func capOpenings(
    in layout: inout MineLayout,
    candidates: [CellCoordinate],
    protectedCells: Set<CellCoordinate>,
    openingIndex: Int,
    random: inout SplitMix64
  ) {
    for _ in 0..<(2 * layout.configuration.cellCount) {
      let openings = layout.openings(excluding: openingIndex)
      guard openings.count > openingAllowance else { return }
      // Capping in index order would always leave the surviving openings in one corner.
      let opening = openings[random.next(upperBound: openings.count)]
      let capSites = layout.topology.neighborIndices[opening].compactMap {
        neighborIndex -> CellCoordinate? in
        guard !layout.isMine(at: neighborIndex),
          let coordinate = layout.configuration.coordinate(for: neighborIndex),
          !protectedCells.contains(coordinate)
        else { return nil }
        return coordinate
      }
      guard let cap = element(of: capSites, random: &random) else { return }
      let donors = candidates.filter { layout.contains($0) && layout.isSafeToVacate($0, cap: cap) }
      guard let donor = element(of: donors, random: &random) else { return }
      layout.move(from: donor, to: cap)
    }
  }

  /// Moves mines between the solver's ambiguous frontier and the cells no clue reaches,
  /// preferring swaps that do not reopen the board.
  private func repairProposal(
    for layout: MineLayout,
    analysis: SolverAnalysis,
    candidates: [CellCoordinate],
    openingIndex: Int,
    swaps: Int,
    random: inout SplitMix64
  ) -> MineLayout? {
    var frontier: [CellCoordinate] = []
    var untouched: [CellCoordinate] = []
    for candidate in candidates
    where !analysis.revealed.contains(candidate) && !analysis.knownMines.contains(candidate) {
      if layout.configuration.neighbors(of: candidate).contains(where: analysis.revealed.contains) {
        frontier.append(candidate)
      } else {
        untouched.append(candidate)
      }
    }
    // A solved layout has no ambiguity left to aim at, so shake it anywhere.
    if frontier.isEmpty {
      frontier = candidates
      untouched = candidates
    }

    let openingBudget = layout.openingCount(excluding: openingIndex)
    var best: MineLayout?
    for _ in 0..<openingAwareResamples {
      var revised = layout
      var applied = 0
      for _ in 0..<max(1, swaps) {
        guard let pivot = element(of: frontier, random: &random) else { break }
        if revised.contains(pivot) {
          guard
            let destination = element(
              of: untouched, matching: { !revised.contains($0) }, random: &random)
              ?? element(of: candidates, matching: { !revised.contains($0) }, random: &random)
          else { break }
          revised.move(from: pivot, to: destination)
        } else {
          guard
            let source = element(of: untouched, matching: { revised.contains($0) }, random: &random)
              ?? element(of: candidates, matching: { revised.contains($0) }, random: &random)
          else { break }
          revised.move(from: source, to: pivot)
        }
        applied += 1
      }
      guard applied > 0 else { continue }
      best = revised
      if revised.openingCount(excluding: openingIndex) <= openingBudget { return revised }
    }
    return best
  }

  private func element(
    of values: [CellCoordinate],
    random: inout SplitMix64
  ) -> CellCoordinate? {
    values.isEmpty ? nil : values[random.next(upperBound: values.count)]
  }

  /// Samples uniformly, then falls back to a scan so a sparse pool still resolves.
  private func element(
    of values: [CellCoordinate],
    matching predicate: (CellCoordinate) -> Bool,
    random: inout SplitMix64
  ) -> CellCoordinate? {
    guard !values.isEmpty else { return nil }
    for _ in 0..<24 {
      let candidate = values[random.next(upperBound: values.count)]
      if predicate(candidate) { return candidate }
    }
    let matches = values.filter(predicate)
    guard !matches.isEmpty else { return nil }
    return matches[random.next(upperBound: matches.count)]
  }

  private func randomMineSet(
    from candidates: [CellCoordinate],
    count: Int,
    random: inout SplitMix64
  ) -> Set<CellCoordinate> {
    var pool = candidates
    shuffle(&pool, using: &random)
    return Set(pool.prefix(count))
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
