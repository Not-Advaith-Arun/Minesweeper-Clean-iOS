import Foundation
import MinesweeperCore
import Observation

// This is the only UI file that knows the MinesweeperCore API. Views consume the
// replica-facing presentation types so the renderer and design layer stay decoupled.

struct PersistenceOverview: Sendable {
  let savedGames: [ReplicaDifficulty: SavedGameSummary]
  let records: [ReplicaTimeRecord]
}

@MainActor
final class GamePersistenceBridge {
  static let shared = GamePersistenceBridge()

  private let snapshots: GameSnapshotRepository?
  private let times: TimeRecordRepository?

  private init() {
    snapshots = try? GameSnapshotRepository()
    times = try? TimeRecordRepository()
  }

  func loadOverview() async -> PersistenceOverview {
    var savedGames: [ReplicaDifficulty: SavedGameSummary] = [:]
    var records: [ReplicaTimeRecord] = []

    for difficulty in ReplicaDifficulty.allCases {
      if let snapshot = try? await snapshots?.load(for: difficulty.coreValue),
        !snapshot.phase.isFinished
      {
        savedGames[difficulty] = SavedGameSummary(
          difficulty: difficulty,
          elapsedSeconds: Int(snapshot.elapsedTime),
          savedAt: snapshot.savedAt
        )
      }
      if let stored = try? await times?.records(for: difficulty.coreValue) {
        records.append(
          contentsOf: stored.map {
            ReplicaTimeRecord(
              id: $0.id,
              difficulty: difficulty,
              seconds: Int($0.duration.rounded(.down)),
              date: $0.completedAt
            )
          })
      }
    }
    return PersistenceOverview(savedGames: savedGames, records: records)
  }

  func loadGame(for difficulty: ReplicaDifficulty) async -> MinesweeperCore.GameSnapshot? {
    try? await snapshots?.load(for: difficulty.coreValue)
  }

  func saveGame(_ snapshot: MinesweeperCore.GameSnapshot) async {
    try? await snapshots?.save(snapshot)
  }

  func removeGame(for difficulty: ReplicaDifficulty) async {
    try? await snapshots?.remove(for: difficulty.coreValue)
  }

  func addRecord(_ record: ReplicaTimeRecord) async {
    let coreRecord = MinesweeperCore.TimeRecord(
      id: record.id,
      difficulty: record.difficulty.coreValue,
      duration: TimeInterval(record.seconds),
      completedAt: record.date
    )
    try? await times?.add(coreRecord)
  }

  func removeRecord(_ record: ReplicaTimeRecord) async {
    try? await times?.remove(id: record.id, from: record.difficulty.coreValue)
  }
}

@MainActor
@Observable
final class GameSessionController {
  private(set) var board: BoardPresentation
  private(set) var phase: ReplicaGamePhase = .ready
  private(set) var remainingMineCount: Int
  private(set) var actionMode: PrimaryAction
  private(set) var isLoading = false
  private(set) var errorMessage: String?
  private(set) var completionRecord: ReplicaTimeRecord?
  private(set) var feedbackSequence = 0
  private(set) var feedbackAction: PrimaryAction = .dig
  private(set) var lastChangedCoordinates: Set<CellCoordinate> = []
  private(set) var lastActionCoordinate: CellCoordinate?

  let difficulty: ReplicaDifficulty
  private var engine: GameEngine
  private var explodedMine: CellCoordinate?
  private var settings: UserSettings

  init(difficulty: ReplicaDifficulty, resume: Bool, settings: UserSettings) {
    self.difficulty = difficulty
    self.settings = settings
    let initialMode: ActionMode = settings.primaryAction == .dig ? .dig : .flag
    self.engine = GameEngine(
      difficulty: difficulty.coreValue,
      actionMode: initialMode,
      generator: Self.generator(for: difficulty)
    )
    self.board = BoardPresentation(columns: difficulty.size.columns, rows: difficulty.size.rows)
    self.remainingMineCount = difficulty.size.mines
    self.actionMode = settings.primaryAction
#if DEBUG
    if let preview = Self.previewEngine(for: difficulty) {
      self.engine = preview.engine
      self.explodedMine = preview.explodedMine
      if preview.engine.phase == .won {
        self.completionRecord = ReplicaTimeRecord(
          id: AppConstants.previewCompletionID,
          difficulty: difficulty,
          seconds: 21,
          date: Date(timeIntervalSince1970: 1_593_388_800)
        )
      }
    }
#endif
    refreshPresentation()

    if resume {
      isLoading = true
      Task { [weak self] in await self?.restore() }
    }
  }

  var elapsedSeconds: Int { Int(engine.elapsedTime(at: .now).rounded(.down)) }

  var savedSummary: SavedGameSummary? {
    guard !phase.isFinished, phase != .ready || engine.flaggedCellCount > 0 else { return nil }
    return SavedGameSummary(difficulty: difficulty, elapsedSeconds: elapsedSeconds, savedAt: .now)
  }

  func updateSettings(_ settings: UserSettings) {
    self.settings = settings
    if engine.phase == .ready,
      engine.revealedSafeCellCount == 0,
      engine.flaggedCellCount == 0
    {
      setActionMode(settings.primaryAction)
    }
  }

  func setActionMode(_ mode: PrimaryAction) {
    var revised = engine
    revised.setActionMode(mode == .dig ? .dig : .flag)
    engine = revised
    actionMode = mode
  }

  func toggleActionMode() {
    setActionMode(actionMode == .dig ? .flag : .dig)
  }

  func primaryAction(column: Int, row: Int) {
    perform(primary: true, column: column, row: row)
  }

  func secondaryAction(column: Int, row: Int) {
    guard settings.longPressEnabled else { return }
    perform(primary: false, column: column, row: row)
  }

  func restart() {
    engine = GameEngine(
      difficulty: difficulty.coreValue,
      actionMode: settings.primaryAction == .dig ? .dig : .flag,
      generator: Self.generator(for: difficulty)
    )
    explodedMine = nil
    completionRecord = nil
    errorMessage = nil
    lastChangedCoordinates = []
    lastActionCoordinate = nil
    isLoading = false
    refreshPresentation()
  }

  func saveIfNeeded() {
    guard !phase.isFinished else {
      Task { await GamePersistenceBridge.shared.removeGame(for: difficulty) }
      return
    }
    guard savedSummary != nil else {
      Task { await GamePersistenceBridge.shared.removeGame(for: difficulty) }
      return
    }
    var revised = engine
    revised.pauseTimer()
    engine = revised
    let snapshot = revised.snapshot()
    Task { await GamePersistenceBridge.shared.saveGame(snapshot) }
  }

  func resumeTimerIfNeeded() {
    guard phase == .playing else { return }
    var revised = engine
    revised.startTimer()
    engine = revised
  }

  func dismissError() { errorMessage = nil }

  private func restore() async {
    defer { isLoading = false }
    guard let snapshot = await GamePersistenceBridge.shared.loadGame(for: difficulty) else {
      refreshPresentation()
      return
    }
    do {
      engine = try GameEngine(snapshot: snapshot)
      actionMode = engine.actionMode == .dig ? .dig : .flag
      refreshPresentation()
      resumeTimerIfNeeded()
    } catch {
      errorMessage = "The saved game could not be restored. A fresh board was created."
      await GamePersistenceBridge.shared.removeGame(for: difficulty)
      restart()
    }
  }

  private func perform(primary: Bool, column: Int, row: Int) {
    guard !isLoading, !phase.isFinished else { return }
    isLoading = true
    let requestedAction =
      primary
      ? actionMode
      : (actionMode == .dig ? PrimaryAction.flag : PrimaryAction.dig)
    let coordinate = CellCoordinate(row: row, column: column)
    let currentEngine = engine
    let coreSettings = settings.coreValue

    Task { [weak self] in
      let outcome = await Task.detached(priority: .userInitiated) {
        var revised = currentEngine
        do {
          let result =
            try primary
            ? revised.performPrimaryAction(at: coordinate, settings: coreSettings)
            : revised.performSecondaryAction(at: coordinate, settings: coreSettings)
          return CoreActionOutcome(engine: revised, result: result, errorDescription: nil)
        } catch {
          return CoreActionOutcome(
            engine: revised, result: nil,
            errorDescription: "The board could not be generated. Please try again.")
        }
      }.value
      guard let self else { return }
      self.engine = outcome.engine
      self.explodedMine = outcome.result?.explodedMine
      self.errorMessage = outcome.errorDescription
      self.lastActionCoordinate = coordinate
      var visuallyChanged = outcome.result?.changedCoordinates ?? []
      if outcome.engine.phase == .won {
        // Clean One resolves a win by turning every mine into a flag in the
        // same outward wave as the final reveal.
        for (index, cell) in outcome.engine.cells.enumerated() where cell.isMine {
          if let mine = outcome.engine.configuration.coordinate(for: index) {
            visuallyChanged.insert(mine)
          }
        }
      }
      if outcome.engine.phase == .lost {
        // Wrong flags also change visual state at the terminal transition and
        // must participate in the same loss animation schedule.
        for (index, cell) in outcome.engine.cells.enumerated()
        where cell.isFlagged && !cell.isMine {
          if let flagged = outcome.engine.configuration.coordinate(for: index) {
            visuallyChanged.insert(flagged)
          }
        }
      }
      self.lastChangedCoordinates = visuallyChanged
      self.isLoading = false
      if outcome.result?.didChange == true {
        if !outcome.engine.phase.isFinished {
          self.feedbackAction = requestedAction
          self.feedbackSequence += 1
        }
        self.persistAfterAction()
      }
      self.refreshPresentation()
    }
  }

  private func persistAfterAction() {
    switch engine.phase {
    case .won:
      let record = ReplicaTimeRecord(difficulty: difficulty, seconds: elapsedSeconds)
      completionRecord = record
      Task {
        await GamePersistenceBridge.shared.addRecord(record)
        await GamePersistenceBridge.shared.removeGame(for: difficulty)
      }
    case .lost:
      Task { await GamePersistenceBridge.shared.removeGame(for: difficulty) }
    case .ready, .playing:
      let snapshot = engine.snapshot()
      Task { await GamePersistenceBridge.shared.saveGame(snapshot) }
    }
  }

  private func refreshPresentation() {
    phase = engine.phase.replicaValue
    remainingMineCount = engine.remainingMineCount
    actionMode = engine.actionMode == .dig ? .dig : .flag
    board = BoardPresentation(
      columns: engine.configuration.width,
      rows: engine.configuration.height,
      cells: engine.cells.enumerated().map { index, cell in
        if phase == .won, cell.isMine {
          return .flagged
        }
        if cell.isRevealed {
          if cell.isMine {
            let coordinate = engine.configuration.coordinate(for: index)
            return .mine(triggered: coordinate == explodedMine)
          }
          return .revealed(cell.adjacentMineCount)
        }
        if cell.isFlagged {
          return phase == .lost && !cell.isMine ? .wrongFlag : .flagged
        }
        return .covered
      }
    )
  }

  private static func generator(for difficulty: ReplicaDifficulty) -> any BoardGenerating {
    switch difficulty {
    case .extreme:
      HardNoGuessBoardGenerator(maximumAttempts: 2_048, randomAttemptsBeforeFallback: 1_920)
    case .hard, .huge:
      NoGuessBoardGenerator(maximumAttempts: 4_096, randomAttemptsBeforeFallback: 96)
    case .beginner, .easy, .medium:
      NoGuessBoardGenerator(maximumAttempts: 2_048, randomAttemptsBeforeFallback: 64)
    }
  }

#if DEBUG
  private static func previewEngine(for difficulty: ReplicaDifficulty)
    -> (engine: GameEngine, explodedMine: CellCoordinate?)?
  {
    guard let rawState = ProcessInfo.processInfo.environment["MINESWEEPER_UI_TEST_GAME_STATE"],
      ["won", "lost", "near_win", "near_loss"].contains(rawState)
    else { return nil }

    let configuration = difficulty.coreValue.configuration
    let centerIndex = configuration.index(
      for: CellCoordinate(row: max(0, configuration.height / 2 - 1), column: configuration.width / 2)
    )!
    var mineIndices: Set<Int> = rawState == "near_loss" ? [centerIndex] : []
    var candidate = 0
    while mineIndices.count < configuration.mineCount {
      let index = (candidate * 37 + 11) % configuration.cellCount
      if rawState != "near_win" || index != centerIndex { mineIndices.insert(index) }
      candidate += 1
    }
    let explodedIndex = mineIndices.sorted().first
    let correctFlagIndex = rawState == "near_loss"
      ? mineIndices.sorted().first(where: { $0 != centerIndex }) : nil
    let wrongFlagIndex = rawState == "near_loss"
      ? (0..<configuration.cellCount).first(where: {
        !mineIndices.contains($0) && $0 != centerIndex
      }) : nil
    let cells = (0..<configuration.cellCount).map { index -> Cell in
      let coordinate = configuration.coordinate(for: index)!
      let isMine = mineIndices.contains(index)
      let isFlagged = index == correctFlagIndex || index == wrongFlagIndex
      let adjacent = configuration.neighbors(of: coordinate).reduce(0) { count, neighbor in
        count + (configuration.index(for: neighbor).map(mineIndices.contains) == true ? 1 : 0)
      }
      return Cell(
        isMine: isMine,
        isRevealed: isFlagged
          ? false
          : isMine
            ? rawState == "lost"
            : !(rawState == "near_win" && index == centerIndex),
        isFlagged: isFlagged,
        adjacentMineCount: adjacent
      )
    }
    let phase: MinesweeperCore.GamePhase = switch rawState {
    case "won": .won
    case "lost": .lost
    default: .playing
    }
    let snapshot = MinesweeperCore.GameSnapshot(
      difficulty: difficulty.coreValue,
      configuration: configuration,
      seed: 21,
      cells: cells,
      phase: phase,
      actionMode: .dig,
      elapsedTime: rawState == "won" ? 21 : 19
    )
    guard let engine = try? GameEngine(snapshot: snapshot) else { return nil }
    return (
      engine,
      rawState == "lost"
        ? explodedIndex.flatMap(configuration.coordinate(for:)) : nil
    )
  }
#endif
}

private struct CoreActionOutcome: Sendable {
  let engine: GameEngine
  let result: GameActionResult?
  let errorDescription: String?
}

extension ReplicaDifficulty {
  fileprivate var coreValue: Difficulty {
    switch self {
    case .beginner: .beginner
    case .easy: .easy
    case .medium: .medium
    case .hard: .hard
    case .huge: .huge
    case .extreme: .extreme
    }
  }
}

extension MinesweeperCore.GamePhase {
  fileprivate var replicaValue: ReplicaGamePhase {
    switch self {
    case .ready: .ready
    case .playing: .playing
    case .won: .won
    case .lost: .lost
    }
  }
}

extension UserSettings {
  fileprivate var coreValue: GameSettings {
    GameSettings(
      cellBordersEnabled: cellBorders,
      showsActionToggle: showActionToggle,
      defaultAction: primaryAction == .dig ? .dig : .flag,
      longPressEnabled: longPressEnabled,
      longPressDelayMilliseconds: Int(longPressDelayMilliseconds),
      easyDiggingEnabled: easyDigging,
      easyFlaggingEnabled: easyFlagging,
      animationSpeedPercent: Int(animationSpeed),
      vibrationEnabled: vibrationEnabled,
      vibrationDurationMilliseconds: Int(vibrationDurationMilliseconds)
    )
  }
}
