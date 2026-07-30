import Foundation

public struct GameSnapshot: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let difficulty: Difficulty
  public let configuration: BoardConfiguration
  public let seed: UInt64
  public let cells: [Cell]
  public let phase: GamePhase
  public let actionMode: ActionMode
  public let elapsedTime: TimeInterval
  public let savedAt: Date

  public init(
    schemaVersion: Int = GameSnapshot.currentSchemaVersion,
    difficulty: Difficulty,
    configuration: BoardConfiguration,
    seed: UInt64,
    cells: [Cell],
    phase: GamePhase,
    actionMode: ActionMode,
    elapsedTime: TimeInterval,
    savedAt: Date = Date()
  ) {
    self.schemaVersion = schemaVersion
    self.difficulty = difficulty
    self.configuration = configuration
    self.seed = seed
    self.cells = cells
    self.phase = phase
    self.actionMode = actionMode
    self.elapsedTime = max(0, elapsedTime)
    self.savedAt = savedAt
  }
}

public enum GameEngineError: Error, Equatable, Sendable {
  case coordinateOutsideBoard
  case invalidSnapshot
  case unsupportedSnapshotVersion(Int)
  case generationFailed(BoardGenerationError)
}

public struct GameEngine: Sendable {
  public let difficulty: Difficulty
  public let configuration: BoardConfiguration
  public let seed: UInt64
  public private(set) var cells: [Cell]
  public private(set) var phase: GamePhase
  public private(set) var actionMode: ActionMode
  public private(set) var elapsedTime: TimeInterval

  private var timerStartedAt: Date?
  private var hasMaterializedBoard: Bool
  private let generator: any BoardGenerating

  public var flaggedCellCount: Int { cells.reduce(0) { $0 + ($1.isFlagged ? 1 : 0) } }
  public var remainingMineCount: Int { configuration.mineCount - flaggedCellCount }
  public var revealedSafeCellCount: Int {
    cells.reduce(0) { $0 + ($1.isRevealed && !$1.isMine ? 1 : 0) }
  }
  public var isTimerRunning: Bool { timerStartedAt != nil }

  public init(
    difficulty: Difficulty,
    seed: UInt64 = UInt64.random(in: .min ... .max),
    actionMode: ActionMode = .dig,
    generator: any BoardGenerating = NoGuessBoardGenerator()
  ) {
    self.difficulty = difficulty
    configuration = difficulty.configuration
    self.seed = seed
    cells = Array(repeating: Cell(), count: configuration.cellCount)
    phase = .ready
    self.actionMode = actionMode
    elapsedTime = 0
    timerStartedAt = nil
    hasMaterializedBoard = false
    self.generator = generator
  }

  /// Creates a game around a known board. This is useful for ready-board queues and deterministic tests.
  public init(
    board: GeneratedBoard,
    difficulty: Difficulty,
    actionMode: ActionMode = .dig,
    phase: GamePhase = .ready,
    generator: any BoardGenerating = NoGuessBoardGenerator()
  ) {
    self.difficulty = difficulty
    configuration = board.configuration
    seed = board.seed
    cells = board.makeCells()
    self.phase = phase
    self.actionMode = actionMode
    elapsedTime = 0
    timerStartedAt = nil
    hasMaterializedBoard = true
    self.generator = generator
  }

  public init(
    snapshot: GameSnapshot,
    generator: any BoardGenerating = NoGuessBoardGenerator()
  ) throws {
    guard snapshot.schemaVersion == GameSnapshot.currentSchemaVersion else {
      throw GameEngineError.unsupportedSnapshotVersion(snapshot.schemaVersion)
    }
    guard snapshot.cells.count == snapshot.configuration.cellCount,
      snapshot.configuration == snapshot.difficulty.configuration,
      snapshot.cells.filter(\.isMine).count == 0
        || snapshot.cells.filter(\.isMine).count == snapshot.configuration.mineCount
    else {
      throw GameEngineError.invalidSnapshot
    }
    difficulty = snapshot.difficulty
    configuration = snapshot.configuration
    seed = snapshot.seed
    cells = snapshot.cells
    phase = snapshot.phase
    actionMode = snapshot.actionMode
    elapsedTime = max(0, snapshot.elapsedTime)
    timerStartedAt = nil  // Background time never counts after restoration.
    hasMaterializedBoard = snapshot.cells.contains(where: \.isMine)
    self.generator = generator
  }

  public func cell(at coordinate: CellCoordinate) -> Cell? {
    configuration.index(for: coordinate).map { cells[$0] }
  }

  public mutating func setActionMode(_ mode: ActionMode) {
    actionMode = mode
  }

  @discardableResult
  public mutating func toggleActionMode() -> ActionMode {
    actionMode = actionMode.secondary
    return actionMode
  }

  public func elapsedTime(at date: Date = Date()) -> TimeInterval {
    guard let timerStartedAt else { return elapsedTime }
    return elapsedTime + max(0, date.timeIntervalSince(timerStartedAt))
  }

  public mutating func startTimer(at date: Date = Date()) {
    guard phase == .playing, timerStartedAt == nil else { return }
    timerStartedAt = date
  }

  public mutating func pauseTimer(at date: Date = Date()) {
    guard let timerStartedAt else { return }
    elapsedTime += max(0, date.timeIntervalSince(timerStartedAt))
    self.timerStartedAt = nil
  }

  public mutating func updateElapsedTime(to value: TimeInterval) {
    elapsedTime = max(0, value)
    if timerStartedAt != nil { timerStartedAt = Date() }
  }

  @discardableResult
  public mutating func perform(
    _ action: GameAction,
    at coordinate: CellCoordinate,
    settings: GameSettings = .default,
    now: Date = Date()
  ) throws -> GameActionResult {
    switch action {
    case .dig:
      if cell(at: coordinate)?.isRevealed == true, settings.easyDiggingEnabled {
        return try chord(at: coordinate, now: now)
      }
      return try reveal(at: coordinate, now: now)
    case .flag:
      if cell(at: coordinate)?.isRevealed == true, settings.easyFlaggingEnabled {
        return try flagChord(at: coordinate)
      }
      return try toggleFlag(at: coordinate)
    case .chord:
      return try chord(at: coordinate, now: now)
    }
  }

  @discardableResult
  public mutating func performPrimaryAction(
    at coordinate: CellCoordinate,
    settings: GameSettings = .default,
    now: Date = Date()
  ) throws -> GameActionResult {
    try perform(actionMode == .dig ? .dig : .flag, at: coordinate, settings: settings, now: now)
  }

  @discardableResult
  public mutating func performSecondaryAction(
    at coordinate: CellCoordinate,
    settings: GameSettings = .default,
    now: Date = Date()
  ) throws -> GameActionResult {
    try perform(actionMode == .dig ? .flag : .dig, at: coordinate, settings: settings, now: now)
  }

  @discardableResult
  public mutating func reveal(
    at coordinate: CellCoordinate,
    now: Date = Date()
  ) throws -> GameActionResult {
    let index = try checkedIndex(for: coordinate)
    let oldPhase = phase
    guard !phase.isFinished, !cells[index].isFlagged, !cells[index].isRevealed else {
      return unchangedResult(from: oldPhase)
    }

    if phase == .ready {
      if !hasMaterializedBoard {
        do {
          let flagged = Set(
            cells.indices.compactMap {
              cells[$0].isFlagged ? configuration.coordinate(for: $0) : nil
            })
          let board = try generator.generate(
            configuration: configuration, firstReveal: coordinate, seed: seed)
          cells = board.makeCells()
          hasMaterializedBoard = true
          for flaggedCoordinate in flagged {
            if let flaggedIndex = configuration.index(for: flaggedCoordinate) {
              cells[flaggedIndex].isFlagged = true
            }
          }
        } catch let error as BoardGenerationError {
          throw GameEngineError.generationFailed(error)
        }
      }
      phase = .playing
      startTimer(at: now)
    }

    if cells[index].isMine {
      var changed: Set<CellCoordinate> = []
      for cellIndex in cells.indices where cells[cellIndex].isMine && !cells[cellIndex].isRevealed {
        cells[cellIndex].isRevealed = true
        if let mine = configuration.coordinate(for: cellIndex) { changed.insert(mine) }
      }
      phase = .lost
      pauseTimer(at: now)
      return GameActionResult(
        changedCoordinates: changed,
        previousPhase: oldPhase,
        phase: phase,
        explodedMine: coordinate
      )
    }

    let changed = floodReveal(from: coordinate)
    finishIfWon(at: now)
    return GameActionResult(changedCoordinates: changed, previousPhase: oldPhase, phase: phase)
  }

  @discardableResult
  public mutating func toggleFlag(at coordinate: CellCoordinate) throws -> GameActionResult {
    let index = try checkedIndex(for: coordinate)
    let oldPhase = phase
    guard !phase.isFinished, !cells[index].isRevealed else {
      return unchangedResult(from: oldPhase)
    }
    cells[index].isFlagged.toggle()
    return GameActionResult(changedCoordinates: [coordinate], previousPhase: oldPhase, phase: phase)
  }

  @discardableResult
  public mutating func chord(
    at coordinate: CellCoordinate,
    now: Date = Date()
  ) throws -> GameActionResult {
    let index = try checkedIndex(for: coordinate)
    let oldPhase = phase
    guard phase == .playing, cells[index].isRevealed, cells[index].adjacentMineCount > 0 else {
      return unchangedResult(from: oldPhase)
    }
    let neighbors = configuration.neighbors(of: coordinate)
    let adjacentFlags = neighbors.reduce(0) { total, neighbor in
      total + ((cell(at: neighbor)?.isFlagged == true) ? 1 : 0)
    }
    guard adjacentFlags == cells[index].adjacentMineCount else {
      return unchangedResult(from: oldPhase)
    }

    var changed: Set<CellCoordinate> = []
    for neighbor in neighbors {
      guard let neighborIndex = configuration.index(for: neighbor),
        !cells[neighborIndex].isFlagged,
        !cells[neighborIndex].isRevealed
      else { continue }
      if cells[neighborIndex].isMine {
        for mineIndex in cells.indices where cells[mineIndex].isMine && !cells[mineIndex].isRevealed
        {
          cells[mineIndex].isRevealed = true
          if let mine = configuration.coordinate(for: mineIndex) { changed.insert(mine) }
        }
        phase = .lost
        pauseTimer(at: now)
        return GameActionResult(
          changedCoordinates: changed,
          previousPhase: oldPhase,
          phase: phase,
          explodedMine: neighbor
        )
      }
      changed.formUnion(floodReveal(from: neighbor))
    }
    finishIfWon(at: now)
    return GameActionResult(changedCoordinates: changed, previousPhase: oldPhase, phase: phase)
  }

  @discardableResult
  public mutating func flagChord(at coordinate: CellCoordinate) throws -> GameActionResult {
    let index = try checkedIndex(for: coordinate)
    let oldPhase = phase
    guard phase == .playing, cells[index].isRevealed, cells[index].adjacentMineCount > 0 else {
      return unchangedResult(from: oldPhase)
    }
    let neighbors = configuration.neighbors(of: coordinate)
    let covered = neighbors.filter { neighbor in
      guard let cell = cell(at: neighbor) else { return false }
      return !cell.isRevealed && !cell.isFlagged
    }
    let flagged = neighbors.reduce(0) { $0 + ((cell(at: $1)?.isFlagged == true) ? 1 : 0) }
    let remaining = cells[index].adjacentMineCount - flagged
    guard remaining > 0, covered.count == remaining else { return unchangedResult(from: oldPhase) }
    for neighbor in covered {
      if let neighborIndex = configuration.index(for: neighbor) {
        cells[neighborIndex].isFlagged = true
      }
    }
    return GameActionResult(changedCoordinates: Set(covered), previousPhase: oldPhase, phase: phase)
  }

  public func snapshot(at date: Date = Date()) -> GameSnapshot {
    GameSnapshot(
      difficulty: difficulty,
      configuration: configuration,
      seed: seed,
      cells: cells,
      phase: phase,
      actionMode: actionMode,
      elapsedTime: elapsedTime(at: date),
      savedAt: date
    )
  }

  private func checkedIndex(for coordinate: CellCoordinate) throws -> Int {
    guard let index = configuration.index(for: coordinate) else {
      throw GameEngineError.coordinateOutsideBoard
    }
    return index
  }

  private func unchangedResult(from oldPhase: GamePhase) -> GameActionResult {
    GameActionResult(previousPhase: oldPhase, phase: phase)
  }

  private mutating func floodReveal(from start: CellCoordinate) -> Set<CellCoordinate> {
    guard let startIndex = configuration.index(for: start),
      !cells[startIndex].isMine,
      !cells[startIndex].isFlagged,
      !cells[startIndex].isRevealed
    else { return [] }

    var changed: Set<CellCoordinate> = [start]
    var queue = [start]
    var cursor = 0
    cells[startIndex].isRevealed = true
    while cursor < queue.count {
      let coordinate = queue[cursor]
      cursor += 1
      guard let index = configuration.index(for: coordinate), cells[index].adjacentMineCount == 0
      else { continue }
      for neighbor in configuration.neighbors(of: coordinate) {
        guard let neighborIndex = configuration.index(for: neighbor),
          !cells[neighborIndex].isMine,
          !cells[neighborIndex].isFlagged,
          !cells[neighborIndex].isRevealed
        else { continue }
        cells[neighborIndex].isRevealed = true
        changed.insert(neighbor)
        if cells[neighborIndex].adjacentMineCount == 0 { queue.append(neighbor) }
      }
    }
    return changed
  }

  private mutating func finishIfWon(at date: Date) {
    guard phase == .playing, revealedSafeCellCount == configuration.safeCellCount else { return }
    phase = .won
    pauseTimer(at: date)
  }
}
