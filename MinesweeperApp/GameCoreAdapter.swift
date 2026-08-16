import Foundation
import MinesweeperCore
import Observation

// This is the only UI file that knows the MinesweeperCore API. Views consume the
// replica-facing presentation types so the renderer and design layer stay decoupled.

struct PersistenceOverview: Sendable {
  let savedGames: [ReplicaDifficulty: SavedGameSummary]
  let records: [ReplicaTimeRecord]
}

/// Keeps one solver-verified Extreme board ready away from the main actor.
///
/// Extreme deliberately has a fixed first reveal, so its expensive no-guess
/// verification can happen before the player enters the board. The actor
/// serializes consumption while the detached task does the CPU-heavy work.
/// Once consumed, it deliberately stays idle so generation cannot compete
/// with reveal and camera animation. A later restart schedules its own fresh,
/// independently seeded board while the ready screen remains responsive.
actor ExtremeReadyBoardPool {
  static let shared = ExtremeReadyBoardPool()
  static let fixedStart = CellCoordinate(row: 16, column: 9)

  private struct PendingBoard: Sendable {
    let identifier: UInt64
    let task: Task<PreparedBoard, Error>
  }

  private var pendingBoard: PendingBoard?
  private var nextIdentifier: UInt64 = 0

  /// Starts the app-launch warmup without waiting for generation to finish.
  func warm() {
    scheduleGenerationIfNeeded()
  }

  func consume() async throws -> PreparedBoard {
    scheduleGenerationIfNeeded()
    guard let pendingBoard else {
      throw BoardGenerationError.unableToGenerateNoGuessBoard(attempts: 0)
    }

    do {
      let prepared = try await pendingBoard.task.value
      // Actor methods are re-entrant while awaiting. If another session
      // consumed this task first, wait for its freshly scheduled successor.
      guard self.pendingBoard?.identifier == pendingBoard.identifier else {
        return try await consume()
      }
      self.pendingBoard = nil
      return prepared
    } catch {
      if self.pendingBoard?.identifier == pendingBoard.identifier {
        self.pendingBoard = nil
        scheduleGenerationIfNeeded()
      }
      throw error
    }
  }

  private func scheduleGenerationIfNeeded() {
    guard pendingBoard == nil else { return }
    nextIdentifier &+= 1
    let identifier = nextIdentifier
    let seed = UInt64.random(in: .min ... .max)
    let firstReveal = Self.fixedStart
    let configuration = Difficulty.extreme.configuration
    let generator = HardNoGuessBoardGenerator(
      maximumAttempts: 2_048,
      randomAttemptsBeforeFallback: 1_920
    )
    // The player is waiting behind this: Extreme shows a preparation screen until the board
    // arrives. Background QoS gets starved whenever anything else is running and stretched
    // that wait into tens of seconds, so ask for the same priority as a direct interaction.
    let task = Task.detached(priority: .userInitiated) {
      let board = try generator.generate(
        configuration: configuration,
        firstReveal: firstReveal,
        seed: seed
      )
      return PreparedBoard(board: board, firstReveal: firstReveal)
    }
    pendingBoard = PendingBoard(identifier: identifier, task: task)
  }
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
  private(set) var isReplaying = false
  private(set) var isReplayCovering = false
  private(set) var replayCoverSequence = 0
  private(set) var isExtremeStartEnabled = false

  let difficulty: ReplicaDifficulty
  private var engine: GameEngine
  private var explodedMine: CellCoordinate?
  private var settings: UserSettings
  private var replayFrames: [GameReplayFrame] = []
  private var completedReplayBoard: BoardPresentation?
  private var replayTask: Task<Void, Never>?
  private var replayGeneration = 0
  private var extremePreparationTask: Task<Void, Never>?
  private var extremePreparationGeneration = 0
  private var hasQueuedExtremeOpening = false
  private var hasAppeared = false
  private var deferredExtremePreparationFlags: Set<CellCoordinate>?

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
    var isPreviewSession = false
#if DEBUG
    if let preview = Self.previewEngine(for: difficulty) {
      isPreviewSession = true
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
    resetReplayHistory(includeCurrentBoard: phase != .ready)

    if resume {
      isLoading = true
      Task { [weak self] in await self?.restore() }
    } else if difficulty == .extreme, !isPreviewSession {
      beginExtremePreparation()
    }
  }

  var fixedStartCoordinate: CellCoordinate? {
    difficulty == .extreme && phase == .ready ? ExtremeReadyBoardPool.fixedStart : nil
  }

  /// SwiftUI evaluates the `State(initialValue:)` expression on every render of `GameView`, so a
  /// session controller is built and thrown away many times per game. Extreme preparation must
  /// wait for the instance that is actually on screen: otherwise each discarded controller takes
  /// the verified board the live session is waiting for, and the generator keeps running for the
  /// whole game while the ready canvas never leaves its preparing state.
  func viewDidAppear() {
    guard !hasAppeared else { return }
    hasAppeared = true
    guard let flags = deferredExtremePreparationFlags else { return }
    deferredExtremePreparationFlags = nil
    beginExtremePreparation(restoringFlags: flags)
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
    stopWinReplay(restoreCompletedBoard: false)
    extremePreparationGeneration += 1
    extremePreparationTask?.cancel()
    extremePreparationTask = nil
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
    isExtremeStartEnabled = false
    hasQueuedExtremeOpening = false
    refreshPresentation()
    completedReplayBoard = nil
    resetReplayHistory(includeCurrentBoard: false)
    if difficulty == .extreme { beginExtremePreparation() }
  }

  /// Replays the exact board states produced by the player's successful game.
  /// Clean One starts from its covered slab, compresses the recorded actions
  /// into a short timelapse, then closes the board with a centered circular
  /// wipe before looping. Keeping the timeline in the session means flags,
  /// chords, and large clearing cascades retain their real chronological order.
  func beginWinReplay(animationSpeed: Double) {
    guard phase == .won, animationSpeed > 0 else { return }

    stopWinReplay()
    let generation = replayGeneration
    let finalBoard = board
    completedReplayBoard = finalBoard

    var timeline = replayFrames
    let coveredBoard = BoardPresentation(columns: board.columns, rows: board.rows)
    if timeline.first?.board != coveredBoard {
      timeline.insert(
        GameReplayFrame(board: coveredBoard, changedCoordinates: [], actionCoordinate: nil),
        at: 0
      )
    }
    if timeline.last?.board != finalBoard {
      timeline.append(
        GameReplayFrame(
          board: finalBoard,
          changedCoordinates: Self.differences(from: timeline.last?.board, to: finalBoard),
          actionCoordinate: lastActionCoordinate
        )
      )
    }

    let actionCount = max(1, timeline.count - 1)
    // The native 220-mine reference spends about eleven seconds on the
    // action history. Short boards are deliberately kept around two seconds
    // so their replay still reads as a miniature game rather than a flash.
    let historyDuration = min(10.4, max(2.2, Double(actionCount) * 0.034))
    let stepDuration = historyDuration / Double(actionCount)
    let speedScale = ReplicaMotion.durationScale(speedPercent: animationSpeed)
    let openingHold = 0.42 * speedScale
    let finalHold = 0.42 * speedScale
    let wipeDuration = 0.92 * speedScale
    let loopHold = 0.48 * speedScale

    isReplaying = true
    isReplayCovering = false
    board = coveredBoard
    lastChangedCoordinates = []
    lastActionCoordinate = nil

    replayTask = Task { [weak self] in
      guard let self else { return }
      while self.replayGeneration == generation,
        self.phase == .won,
        !Task.isCancelled
      {
        self.isReplayCovering = false
        self.board = coveredBoard
        self.lastChangedCoordinates = []
        self.lastActionCoordinate = nil
        guard await self.holdReplay(
          for: openingHold, generation: generation)
        else { return }

        for frame in timeline.dropFirst() {
          guard self.replayGeneration == generation, !Task.isCancelled else { return }
          self.board = frame.board
          self.lastChangedCoordinates = frame.changedCoordinates
          self.lastActionCoordinate = frame.actionCoordinate
          guard await self.holdReplay(
            for: stepDuration * speedScale, generation: generation)
          else { return }
        }

        guard await self.holdReplay(for: finalHold, generation: generation) else { return }
        self.replayCoverSequence += 1
        self.isReplayCovering = true
        guard await self.holdReplay(for: wipeDuration, generation: generation) else { return }

        // Replace the now-fully-covered visual with the real covered board
        // before removing the overlay, so no completed-board frame can flash.
        self.board = coveredBoard
        self.lastChangedCoordinates = []
        self.lastActionCoordinate = nil
        self.isReplayCovering = false
        guard await self.holdReplay(for: loopHold, generation: generation) else { return }
      }
    }
  }

  func stopWinReplay(restoreCompletedBoard: Bool = true) {
    replayGeneration += 1
    replayTask?.cancel()
    replayTask = nil
    isReplayCovering = false
    isReplaying = false
    if restoreCompletedBoard, phase == .won, let completedReplayBoard {
      board = completedReplayBoard
      lastChangedCoordinates = []
      lastActionCoordinate = nil
    }
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

  func dismissError() {
    errorMessage = nil
    if difficulty == .extreme, phase == .ready, !isExtremeStartEnabled, !isLoading {
      beginExtremePreparation()
    }
  }

  private func restore() async {
    guard let snapshot = await GamePersistenceBridge.shared.loadGame(for: difficulty) else {
      refreshPresentation()
      if difficulty == .extreme {
        beginExtremePreparation()
      } else {
        isLoading = false
      }
      return
    }
    do {
      engine = try GameEngine(snapshot: snapshot, generator: Self.generator(for: difficulty))
      actionMode = engine.actionMode == .dig ? .dig : .flag
      refreshPresentation()
      resetReplayHistory(includeCurrentBoard: phase != .ready)
      if difficulty == .extreme, phase == .ready {
        let flaggedCoordinates: Set<CellCoordinate> = Set(
          engine.cells.indices.compactMap { index in
            guard engine.cells[index].isFlagged else { return nil }
            return engine.configuration.coordinate(for: index)
          }
        )
        beginExtremePreparation(restoringFlags: flaggedCoordinates)
        return
      }
      isLoading = false
      resumeTimerIfNeeded()
    } catch {
      errorMessage = "The saved game could not be restored. A fresh board was created."
      await GamePersistenceBridge.shared.removeGame(for: difficulty)
      restart()
    }
  }

  private func perform(primary: Bool, column: Int, row: Int) {
    guard !phase.isFinished else { return }
    let coordinate = CellCoordinate(row: row, column: column)
    let isFixedExtremeOpening = difficulty == .extreme && phase == .ready
    if isFixedExtremeOpening {
      guard coordinate == ExtremeReadyBoardPool.fixedStart else { return }
      guard isExtremeStartEnabled else {
        // Remember an early press on the one valid opening while generation
        // finishes. The GameEngine is still initialized before the reveal is
        // applied; this simply avoids making the player tap the target twice.
        if isLoading {
          hasQueuedExtremeOpening = true
          lastActionCoordinate = coordinate
        }
        return
      }
    }
    guard !isLoading else { return }
    isLoading = true
    let requestedAction =
      isFixedExtremeOpening
      ? PrimaryAction.dig
      : primary
      ? actionMode
      : (actionMode == .dig ? PrimaryAction.flag : PrimaryAction.dig)
    // Publish the touch immediately so Extreme can show responsive visual
    // feedback while the already-verified opening is applied off-main.
    lastActionCoordinate = coordinate
    let currentEngine = engine
    let coreSettings = settings.coreValue

    Task { [weak self] in
      let outcome = await Task.detached(priority: .userInitiated) {
        var revised = currentEngine
        do {
          let result: GameActionResult
          if isFixedExtremeOpening {
            // The fixed cell is an opening affordance, not a flaggable cell.
            // This remains true when Flag is the user's default action or the
            // opening arrives through the secondary/long-press gesture.
            result = try revised.perform(.dig, at: coordinate, settings: coreSettings)
          } else {
            result =
              try primary
              ? revised.performPrimaryAction(at: coordinate, settings: coreSettings)
              : revised.performSecondaryAction(at: coordinate, settings: coreSettings)
          }
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
      self.lastChangedCoordinates = visuallyChanged
      self.isLoading = false
      let didChange = outcome.result?.didChange == true
      if didChange {
        if !outcome.engine.phase.isFinished {
          self.feedbackAction = requestedAction
          self.feedbackSequence += 1
        }
        self.persistAfterAction()
      }
      self.refreshPresentation()
      if didChange, self.phase != .lost {
        self.appendReplayFrame(
          changedCoordinates: visuallyChanged,
          actionCoordinate: coordinate
        )
      }
    }
  }

  private func beginExtremePreparation(
    restoringFlags: Set<CellCoordinate> = []
  ) {
    guard difficulty == .extreme else { return }
    isLoading = true
    isExtremeStartEnabled = false
    lastActionCoordinate = nil
    // Hold off until this controller is the one on screen; see viewDidAppear().
    guard hasAppeared else {
      deferredExtremePreparationFlags = restoringFlags
      return
    }
    extremePreparationGeneration += 1
    let generation = extremePreparationGeneration
    extremePreparationTask?.cancel()

    extremePreparationTask = Task { [weak self] in
      do {
        let prepared = try await ExtremeReadyBoardPool.shared.consume()
        guard let self,
          !Task.isCancelled,
          self.extremePreparationGeneration == generation
        else { return }

        var revised = GameEngine(
          board: prepared.board,
          difficulty: .extreme,
          actionMode: self.actionMode == .dig ? .dig : .flag,
          generator: Self.generator(for: .extreme)
        )
        // A legacy ready snapshot can contain pre-opening flags. Preserve
        // those on resume, except for the now-reserved opening coordinate.
        for coordinate in restoringFlags where coordinate != prepared.firstReveal {
          _ = try? revised.toggleFlag(at: coordinate)
        }
        self.engine = revised
        self.explodedMine = nil
        self.lastChangedCoordinates = []
        self.lastActionCoordinate = nil
        self.refreshPresentation()
        self.resetReplayHistory(includeCurrentBoard: false)
        self.isLoading = false
        self.isExtremeStartEnabled = true
        self.extremePreparationTask = nil
        if self.hasQueuedExtremeOpening {
          self.hasQueuedExtremeOpening = false
          self.perform(
            primary: true,
            column: prepared.firstReveal.column,
            row: prepared.firstReveal.row
          )
        }
      } catch {
        guard let self,
          !Task.isCancelled,
          self.extremePreparationGeneration == generation
        else { return }
        self.isLoading = false
        self.isExtremeStartEnabled = false
        self.extremePreparationTask = nil
        self.errorMessage = "A verified Extreme board could not be prepared. Please try again."
      }
    }
  }

  private func resetReplayHistory(includeCurrentBoard: Bool) {
    let coveredBoard = BoardPresentation(columns: board.columns, rows: board.rows)
    replayFrames = [
      GameReplayFrame(board: coveredBoard, changedCoordinates: [], actionCoordinate: nil)
    ]
    guard includeCurrentBoard, board != coveredBoard else { return }
    replayFrames.append(
      GameReplayFrame(
        board: board,
        changedCoordinates: Self.differences(from: coveredBoard, to: board),
        actionCoordinate: nil
      )
    )
  }

  private func appendReplayFrame(
    changedCoordinates: Set<CellCoordinate>,
    actionCoordinate: CellCoordinate?
  ) {
    guard replayFrames.last?.board != board else { return }
    replayFrames.append(
      GameReplayFrame(
        board: board,
        changedCoordinates: changedCoordinates,
        actionCoordinate: actionCoordinate
      )
    )
  }

  private func holdReplay(for duration: Double, generation: Int) async -> Bool {
    do {
      try await Task.sleep(for: .seconds(max(0, duration)))
    } catch {
      return false
    }
    return !Task.isCancelled && replayGeneration == generation && phase == .won
  }

  private static func differences(
    from oldBoard: BoardPresentation?,
    to newBoard: BoardPresentation
  ) -> Set<CellCoordinate> {
    guard let oldBoard,
      oldBoard.columns == newBoard.columns,
      oldBoard.rows == newBoard.rows
    else {
      return Set(
        (0..<newBoard.rows).flatMap { row in
          (0..<newBoard.columns).map { column in CellCoordinate(row: row, column: column) }
        }
      )
    }
    var changed: Set<CellCoordinate> = []
    for index in newBoard.cells.indices where oldBoard.cells[index] != newBoard.cells[index] {
      changed.insert(
        CellCoordinate(row: index / newBoard.columns, column: index % newBoard.columns)
      )
    }
    return changed
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
            if coordinate != explodedMine, cell.isFlagged { return .flaggedMine }
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
      ["won", "lost", "near_win", "near_loss", "topology"].contains(rawState)
    else { return nil }

    let configuration = difficulty.coreValue.configuration
    let centerIndex = configuration.index(
      for: CellCoordinate(row: max(0, configuration.height / 2 - 1), column: configuration.width / 2)
    )!
    let topologyIsolatedIndex = configuration.index(
      for: CellCoordinate(row: 1, column: 1)
    )!
    let topologyDiagonalIndices = Set([
      configuration.index(for: CellCoordinate(row: 5, column: 2))!,
      configuration.index(for: CellCoordinate(row: 6, column: 3))!,
    ])
    let topologyProtectedIndices: Set<Int> = rawState == "topology"
      ? Set(
        [topologyIsolatedIndex] +
          configuration.neighbors(of: CellCoordinate(row: 1, column: 1)).compactMap(
            configuration.index(for:)
          ) + Array(topologyDiagonalIndices)
      )
      : []
    let topologyMineIndices = [
      CellCoordinate(row: 0, column: 4),
      CellCoordinate(row: 0, column: 5),
      CellCoordinate(row: 2, column: 4),
      CellCoordinate(row: 3, column: 5),
      CellCoordinate(row: 4, column: 6),
      CellCoordinate(row: 5, column: 5),
      CellCoordinate(row: 7, column: 0),
      CellCoordinate(row: 7, column: 1),
      CellCoordinate(row: 8, column: 4),
      CellCoordinate(row: 9, column: 5),
    ].compactMap(configuration.index(for:))
    var mineIndices: Set<Int> = switch rawState {
    case "near_loss": [centerIndex]
    case "topology": Set(topologyMineIndices.prefix(configuration.mineCount))
    default: []
    }
    var candidate = 0
    while mineIndices.count < configuration.mineCount {
      let index = (candidate * 37 + 11) % configuration.cellCount
      if (rawState != "near_win" || index != centerIndex),
        !topologyProtectedIndices.contains(index)
      {
        mineIndices.insert(index)
      }
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
      let isFlagged = rawState == "topology"
        ? isMine
        : index == correctFlagIndex || index == wrongFlagIndex
      let adjacent = configuration.neighbors(of: coordinate).reduce(0) { count, neighbor in
        count + (configuration.index(for: neighbor).map(mineIndices.contains) == true ? 1 : 0)
      }
      let isTopologyReveal = index == topologyIsolatedIndex
        || (coordinate.row >= 4 && !topologyDiagonalIndices.contains(index))
      return Cell(
        isMine: isMine,
        isRevealed: isFlagged
          ? false
          : rawState == "topology"
            ? isTopologyReveal
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

private struct GameReplayFrame {
  let board: BoardPresentation
  let changedCoordinates: Set<CellCoordinate>
  let actionCoordinate: CellCoordinate?
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
