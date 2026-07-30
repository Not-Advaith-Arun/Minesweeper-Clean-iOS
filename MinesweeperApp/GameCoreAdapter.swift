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

  let difficulty: ReplicaDifficulty
  private var engine: GameEngine
  private var explodedMine: CellCoordinate?
  private var settings: UserSettings

  init(difficulty: ReplicaDifficulty, resume: Bool, settings: UserSettings) {
    self.difficulty = difficulty
    self.settings = settings
    let initialMode: ActionMode = settings.primaryAction == .dig ? .dig : .flag
    self.engine = GameEngine(difficulty: difficulty.coreValue, actionMode: initialMode)
    self.board = BoardPresentation(columns: difficulty.size.columns, rows: difficulty.size.rows)
    self.remainingMineCount = difficulty.size.mines
    self.actionMode = settings.primaryAction
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
      actionMode: settings.primaryAction == .dig ? .dig : .flag
    )
    explodedMine = nil
    completionRecord = nil
    errorMessage = nil
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
