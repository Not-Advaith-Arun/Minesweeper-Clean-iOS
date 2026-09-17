import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppStore {
  var navigation: [AppRoute] = []
  var selectedDifficulty: ReplicaDifficulty {
    didSet { defaults.set(selectedDifficulty.rawValue, forKey: AppConstants.difficultyStorageKey) }
  }
  var showAbout = false
  var showReplacementWarning = false
  var pendingDifficulty: ReplicaDifficulty?

  private(set) var settings: UserSettings
  private(set) var themeID: String
  private(set) var records: [ReplicaTimeRecord]
  private(set) var savedGames: [ReplicaDifficulty: SavedGameSummary] = [:]
  private(set) var persistenceReady = false

  private let defaults: UserDefaults
  private var preferredActionToggleVisibility: Bool

  init(defaults: UserDefaults = .standard) {
    Self.resetStateForUITestingIfRequested(defaults: defaults)
    self.defaults = defaults
    self.selectedDifficulty =
      defaults.string(forKey: AppConstants.difficultyStorageKey)
      .flatMap(ReplicaDifficulty.init(rawValue:)) ?? .beginner
    let loadedSettings =
      Self.decode(UserSettings.self, key: AppConstants.settingsStorageKey, defaults: defaults)
      ?? .default
    self.settings = loadedSettings
    self.preferredActionToggleVisibility =
      defaults.object(forKey: AppConstants.actionTogglePreferenceStorageKey) as? Bool
      ?? loadedSettings.showActionToggle
    let storedTheme = defaults.string(forKey: AppConstants.themeStorageKey)
    self.themeID =
      storedTheme.flatMap { identifier in
        ThemeCatalog.isSelectable(id: identifier) ? identifier : nil
      } ?? ThemeCatalog.fallback.id
    self.records =
      Self.decode([ReplicaTimeRecord].self, key: AppConstants.recordsStorageKey, defaults: defaults)
      ?? []
    normalizeSettings()
#if DEBUG
    let environment = ProcessInfo.processInfo.environment
    if let requestedTheme = environment["MINESWEEPER_UI_TEST_THEME"],
      ThemeCatalog.all.contains(where: { $0.id == requestedTheme })
    {
      themeID = requestedTheme
    }
    if environment["MINESWEEPER_UI_TEST_CELL_BORDERS"] == "1" {
      settings.cellBorders = true
    }
    let previewDifficulty = environment["MINESWEEPER_UI_TEST_DIFFICULTY"]
      .flatMap(ReplicaDifficulty.init(rawValue:)) ?? .medium
    if let requestedDifficulty = environment["MINESWEEPER_UI_TEST_DIFFICULTY"]
      .flatMap(ReplicaDifficulty.init(rawValue:))
    {
      selectedDifficulty = requestedDifficulty
    }
    if environment["MINESWEEPER_UI_TEST_RECORDS"] == "1" {
      selectedDifficulty = previewDifficulty
      records = Self.previewRecords(for: previewDifficulty)
    }
    if environment["MINESWEEPER_UI_TEST_GAME_STATE"] == "won" {
      selectedDifficulty = previewDifficulty
      records = Self.previewRecords(for: previewDifficulty)
      navigation = [.game(previewDifficulty, resume: false)]
    } else if ["lost", "near_win", "near_loss", "topology"].contains(
      ProcessInfo.processInfo.environment["MINESWEEPER_UI_TEST_GAME_STATE"]
    ) {
      selectedDifficulty = previewDifficulty
      navigation = [.game(previewDifficulty, resume: false)]
    }
#endif
  }

#if DEBUG
  private static func previewRecords(for difficulty: ReplicaDifficulty) -> [ReplicaTimeRecord] {
    let ids = [
      UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
      AppConstants.previewCompletionID,
      UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
      UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
    ]
    return [17, 20, 21, 26, 50].enumerated().map { index, seconds in
      ReplicaTimeRecord(
        id: ids[index],
        difficulty: difficulty,
        seconds: seconds,
        date: Date(timeIntervalSince1970: 1_593_216_000 + Double(index * 86_400))
      )
    }
  }
#endif

  var theme: AppTheme { ThemeCatalog.theme(id: themeID) }

  func chooseTheme(_ theme: AppTheme) {
    guard themeID != theme.id else { return }
    withAnimation(ReplicaMotion.standard(speedPercent: settings.animationSpeed)) {
      themeID = theme.id
    }
    defaults.set(theme.id, forKey: AppConstants.themeStorageKey)
    haptic(.selection)
  }

  func updateSettings(_ change: (inout UserSettings) -> Void) {
    let previous = settings
    var revised = settings
    change(&revised)
    if previous.longPressEnabled, !revised.longPressEnabled {
      preferredActionToggleVisibility = previous.showActionToggle
      defaults.set(
        preferredActionToggleVisibility,
        forKey: AppConstants.actionTogglePreferenceStorageKey
      )
      revised.showActionToggle = true
    } else if !previous.longPressEnabled, revised.longPressEnabled {
      revised.showActionToggle = preferredActionToggleVisibility
    } else if revised.longPressEnabled,
      revised.showActionToggle != previous.showActionToggle
    {
      preferredActionToggleVisibility = revised.showActionToggle
      defaults.set(
        preferredActionToggleVisibility,
        forKey: AppConstants.actionTogglePreferenceStorageKey
      )
    }
    if !revised.longPressEnabled { revised.showActionToggle = true }
    settings = revised
    persistSettings()
  }

  func resetSettings() {
    settings = .default
    preferredActionToggleVisibility = UserSettings.default.showActionToggle
    defaults.set(
      preferredActionToggleVisibility,
      forKey: AppConstants.actionTogglePreferenceStorageKey
    )
    persistSettings()
  }

  func beginNewGame(for difficulty: ReplicaDifficulty) {
    selectedDifficulty = difficulty
    if savedGames[difficulty] != nil {
      pendingDifficulty = difficulty
      showReplacementWarning = true
    } else {
      navigation.append(.game(difficulty, resume: false))
    }
  }

  func confirmReplacement() {
    guard let difficulty = pendingDifficulty else { return }
    savedGames[difficulty] = nil
    pendingDifficulty = nil
    showReplacementWarning = false
    navigation.append(.game(difficulty, resume: false))
    Task { await GamePersistenceBridge.shared.removeGame(for: difficulty) }
  }

  func resume(_ difficulty: ReplicaDifficulty) {
    selectedDifficulty = difficulty
    navigation.append(.game(difficulty, resume: true))
  }

  func replaceCurrentGame(with difficulty: ReplicaDifficulty) {
    selectedDifficulty = difficulty
    if case .game = navigation.last { navigation.removeLast() }
    navigation.append(.game(difficulty, resume: false))
  }

  func registerSavedGame(_ summary: SavedGameSummary?) {
    guard let summary else { return }
    savedGames[summary.difficulty] = summary
  }

  func clearSavedGame(_ difficulty: ReplicaDifficulty) {
    savedGames[difficulty] = nil
    Task { await GamePersistenceBridge.shared.removeGame(for: difficulty) }
  }

  func addRecord(difficulty: ReplicaDifficulty, seconds: Int) {
    addRecord(ReplicaTimeRecord(difficulty: difficulty, seconds: seconds))
  }

  func addRecord(_ record: ReplicaTimeRecord) {
    records.removeAll { $0.id == record.id }
    records.append(record)
    records.sort { lhs, rhs in
      guard lhs.difficulty == rhs.difficulty else {
        return lhs.difficulty.rawValue < rhs.difficulty.rawValue
      }
      return lhs.seconds == rhs.seconds ? lhs.date < rhs.date : lhs.seconds < rhs.seconds
    }
    persistRecords()
  }

  func deleteRecord(id: UUID) {
    guard let record = records.first(where: { $0.id == id }) else { return }
    records.removeAll { $0.id == id }
    persistRecords()
    Task { await GamePersistenceBridge.shared.removeRecord(record) }
  }

  func records(for difficulty: ReplicaDifficulty) -> [ReplicaTimeRecord] {
    records.filter { $0.difficulty == difficulty }.sorted { $0.seconds < $1.seconds }
  }

  func haptic(_ event: HapticEvent) {
    guard settings.vibrationEnabled else { return }
    Haptics.shared.play(event, durationMilliseconds: settings.vibrationDurationMilliseconds)
  }

  private func normalizeSettings() {
    settings.longPressDelayMilliseconds = min(500, max(100, settings.longPressDelayMilliseconds))
    settings.animationSpeed = min(200, max(0, settings.animationSpeed))
    settings.vibrationDurationMilliseconds = min(
      200, max(5, settings.vibrationDurationMilliseconds))
    if !settings.longPressEnabled { settings.showActionToggle = true }
  }

  private func persistSettings() {
    if let encoded = try? JSONEncoder().encode(settings) {
      defaults.set(encoded, forKey: AppConstants.settingsStorageKey)
    }
  }

  private func persistRecords() {
    if let encoded = try? JSONEncoder().encode(records) {
      defaults.set(encoded, forKey: AppConstants.recordsStorageKey)
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults)
    -> T?
  {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  func hydrateFromDisk() async {
    let overview = await GamePersistenceBridge.shared.loadOverview()
    savedGames = overview.savedGames
    if overview.records.isEmpty, !records.isEmpty {
      for record in records { await GamePersistenceBridge.shared.addRecord(record) }
    } else {
      records = overview.records
    }
    persistRecords()
    persistenceReady = true
  }

  private static func resetStateForUITestingIfRequested(defaults: UserDefaults) {
    let environment = ProcessInfo.processInfo.environment
    guard environment["MINESWEEPER_UI_TESTING"] == "1",
      environment["MINESWEEPER_UI_TEST_RESET"] == "1"
    else { return }

    for key in [
      AppConstants.settingsStorageKey,
      AppConstants.themeStorageKey,
      AppConstants.recordsStorageKey,
      AppConstants.difficultyStorageKey,
      AppConstants.actionTogglePreferenceStorageKey,
    ] {
      defaults.removeObject(forKey: key)
    }

    guard
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else { return }
    let appData = support.appendingPathComponent("MinesweeperCleanReplica", isDirectory: true)
    try? FileManager.default.removeItem(at: appData)
  }
}
