import Foundation

public enum PersistenceError: Error, Sendable {
  case applicationSupportUnavailable
  case invalidDocument
}

public struct SettingsState: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var settings: GameSettings
  public var selectedTheme: ThemeIdentifier

  public init(
    schemaVersion: Int = SettingsState.currentSchemaVersion,
    settings: GameSettings = .default,
    selectedTheme: ThemeIdentifier = .alpine
  ) {
    self.schemaVersion = schemaVersion
    self.settings = settings
    self.settings.normalizeDependencies()
    self.selectedTheme = selectedTheme
  }
}

public protocol GamePersisting: Sendable {
  func load(for difficulty: Difficulty) async throws -> GameSnapshot?
  func save(_ snapshot: GameSnapshot) async throws
  func remove(for difficulty: Difficulty) async throws
}

public protocol TimeRecording: Sendable {
  func records(for difficulty: Difficulty) async throws -> [TimeRecord]
  func add(_ record: TimeRecord) async throws
  func remove(id: UUID, from difficulty: Difficulty) async throws
}

enum PersistenceLocations {
  static func defaultRoot() throws -> URL {
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else {
      throw PersistenceError.applicationSupportUnavailable
    }
    return support.appendingPathComponent("MinesweeperCleanReplica", isDirectory: true)
  }
}

enum JSONDocument {
  static func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  static func remove(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }
}

public actor SettingsRepository {
  private let fileURL: URL

  public init(rootURL: URL? = nil) throws {
    fileURL = try (rootURL ?? PersistenceLocations.defaultRoot())
      .appendingPathComponent("settings.json", isDirectory: false)
  }

  public func loadState() -> SettingsState {
    guard let state = try? JSONDocument.read(SettingsState.self, from: fileURL),
      state.schemaVersion == SettingsState.currentSchemaVersion
    else { return SettingsState() }
    var normalized = state
    normalized.settings.normalizeDependencies()
    return normalized
  }

  public func save(_ state: SettingsState) throws {
    var normalized = state
    normalized.schemaVersion = SettingsState.currentSchemaVersion
    normalized.settings.normalizeDependencies()
    try JSONDocument.write(normalized, to: fileURL)
  }

  public func load() -> GameSettings { loadState().settings }

  public func save(_ settings: GameSettings) throws {
    var state = loadState()
    state.settings = settings
    try save(state)
  }
}

public actor GameSnapshotRepository: GamePersisting {
  private let directoryURL: URL

  public init(rootURL: URL? = nil) throws {
    directoryURL = try (rootURL ?? PersistenceLocations.defaultRoot())
      .appendingPathComponent("games", isDirectory: true)
  }

  public func load(for difficulty: Difficulty) throws -> GameSnapshot? {
    let url = fileURL(for: difficulty)
    guard let snapshot = try? JSONDocument.read(GameSnapshot.self, from: url) else { return nil }
    guard snapshot.schemaVersion == GameSnapshot.currentSchemaVersion,
      snapshot.difficulty == difficulty,
      snapshot.configuration == difficulty.configuration
    else { return nil }
    return snapshot
  }

  public func save(_ snapshot: GameSnapshot) throws {
    guard snapshot.schemaVersion == GameSnapshot.currentSchemaVersion,
      snapshot.configuration == snapshot.difficulty.configuration
    else { throw PersistenceError.invalidDocument }
    try JSONDocument.write(snapshot, to: fileURL(for: snapshot.difficulty))
  }

  public func remove(for difficulty: Difficulty) throws {
    try JSONDocument.remove(fileURL(for: difficulty))
  }

  public func removeAll() throws {
    for difficulty in Difficulty.allCases { try remove(for: difficulty) }
  }

  private func fileURL(for difficulty: Difficulty) -> URL {
    directoryURL.appendingPathComponent("\(difficulty.rawValue).json", isDirectory: false)
  }
}

private struct TimeRecordDocument: Codable, Sendable {
  static let currentSchemaVersion = 1
  let schemaVersion: Int
  var records: [TimeRecord]

  init(records: [TimeRecord]) {
    schemaVersion = Self.currentSchemaVersion
    self.records = records
  }
}

public actor TimeRecordRepository: TimeRecording {
  private let directoryURL: URL

  public init(rootURL: URL? = nil) throws {
    directoryURL = try (rootURL ?? PersistenceLocations.defaultRoot())
      .appendingPathComponent("times", isDirectory: true)
  }

  public func records(for difficulty: Difficulty) throws -> [TimeRecord] {
    let document = try? JSONDocument.read(TimeRecordDocument.self, from: fileURL(for: difficulty))
    guard let document, document.schemaVersion == TimeRecordDocument.currentSchemaVersion else {
      return []
    }
    return document.records
      .filter { $0.difficulty == difficulty }
      .sorted { lhs, rhs in
        lhs.duration == rhs.duration
          ? lhs.completedAt < rhs.completedAt : lhs.duration < rhs.duration
      }
  }

  public func bestRecords(for difficulty: Difficulty, limit: Int = 5) throws -> [TimeRecord] {
    Array(try records(for: difficulty).prefix(max(0, limit)))
  }

  public func add(_ record: TimeRecord) throws {
    var values = try records(for: record.difficulty)
    values.removeAll { $0.id == record.id }
    values.append(record)
    try JSONDocument.write(TimeRecordDocument(records: values), to: fileURL(for: record.difficulty))
  }

  public func remove(id: UUID, from difficulty: Difficulty) throws {
    var values = try records(for: difficulty)
    values.removeAll { $0.id == id }
    try JSONDocument.write(TimeRecordDocument(records: values), to: fileURL(for: difficulty))
  }

  public func removeAll(for difficulty: Difficulty) throws {
    try JSONDocument.remove(fileURL(for: difficulty))
  }

  private func fileURL(for difficulty: Difficulty) -> URL {
    directoryURL.appendingPathComponent("\(difficulty.rawValue).json", isDirectory: false)
  }
}

public struct PreparedBoard: Codable, Hashable, Sendable {
  public let board: GeneratedBoard
  public let firstReveal: CellCoordinate

  public init(board: GeneratedBoard, firstReveal: CellCoordinate) {
    precondition(board.configuration.contains(firstReveal) && !board.isMine(at: firstReveal))
    self.board = board
    self.firstReveal = firstReveal
  }
}

private struct PreparedBoardDocument: Codable, Sendable {
  static let currentSchemaVersion = 1
  let schemaVersion: Int
  var boards: [PreparedBoard]

  init(boards: [PreparedBoard]) {
    schemaVersion = Self.currentSchemaVersion
    self.boards = boards
  }
}

/// Optional persistent cache for asynchronously generated boards keyed by difficulty.
public actor ReadyBoardRepository {
  private let directoryURL: URL

  public init(rootURL: URL? = nil) throws {
    directoryURL = try (rootURL ?? PersistenceLocations.defaultRoot())
      .appendingPathComponent("ready-boards", isDirectory: true)
  }

  public func boards(for difficulty: Difficulty) -> [PreparedBoard] {
    guard
      let document = try? JSONDocument.read(
        PreparedBoardDocument.self, from: fileURL(for: difficulty)),
      document.schemaVersion == PreparedBoardDocument.currentSchemaVersion
    else { return [] }
    return document.boards.filter { $0.board.configuration == difficulty.configuration }
  }

  public func replace(_ boards: [PreparedBoard], for difficulty: Difficulty) throws {
    let valid = boards.filter { $0.board.configuration == difficulty.configuration }
    try JSONDocument.write(PreparedBoardDocument(boards: valid), to: fileURL(for: difficulty))
  }

  public func enqueue(_ board: PreparedBoard, for difficulty: Difficulty, maximumCount: Int = 3)
    throws
  {
    guard board.board.configuration == difficulty.configuration else {
      throw PersistenceError.invalidDocument
    }
    var values = boards(for: difficulty)
    values.append(board)
    values = Array(values.suffix(max(1, maximumCount)))
    try replace(values, for: difficulty)
  }

  public func dequeue(for difficulty: Difficulty) throws -> PreparedBoard? {
    var values = boards(for: difficulty)
    guard !values.isEmpty else { return nil }
    let first = values.removeFirst()
    try replace(values, for: difficulty)
    return first
  }

  private func fileURL(for difficulty: Difficulty) -> URL {
    directoryURL.appendingPathComponent("\(difficulty.rawValue).json", isDirectory: false)
  }
}
