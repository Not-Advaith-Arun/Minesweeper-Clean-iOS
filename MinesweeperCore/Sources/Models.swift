import Foundation

public struct CellCoordinate: Hashable, Codable, Sendable, Comparable {
  public let row: Int
  public let column: Int

  public init(row: Int, column: Int) {
    self.row = row
    self.column = column
  }

  public static func < (lhs: CellCoordinate, rhs: CellCoordinate) -> Bool {
    (lhs.row, lhs.column) < (rhs.row, rhs.column)
  }
}

public struct BoardConfiguration: Hashable, Codable, Sendable {
  public let width: Int
  public let height: Int
  public let mineCount: Int

  public var cellCount: Int { width * height }
  public var safeCellCount: Int { cellCount - mineCount }

  public init(width: Int, height: Int, mineCount: Int) {
    precondition(width > 0 && height > 0, "A board must have positive dimensions")
    precondition(
      mineCount >= 0 && mineCount < width * height, "Mine count must leave at least one safe cell")
    self.width = width
    self.height = height
    self.mineCount = mineCount
  }

  public func contains(_ coordinate: CellCoordinate) -> Bool {
    coordinate.row >= 0 && coordinate.row < height
      && coordinate.column >= 0 && coordinate.column < width
  }

  public func index(for coordinate: CellCoordinate) -> Int? {
    contains(coordinate) ? coordinate.row * width + coordinate.column : nil
  }

  public func coordinate(for index: Int) -> CellCoordinate? {
    guard index >= 0 && index < cellCount else { return nil }
    return CellCoordinate(row: index / width, column: index % width)
  }

  public func neighbors(of coordinate: CellCoordinate) -> [CellCoordinate] {
    guard contains(coordinate) else { return [] }
    var result: [CellCoordinate] = []
    result.reserveCapacity(8)
    for rowOffset in -1...1 {
      for columnOffset in -1...1 where rowOffset != 0 || columnOffset != 0 {
        let candidate = CellCoordinate(
          row: coordinate.row + rowOffset,
          column: coordinate.column + columnOffset
        )
        if contains(candidate) { result.append(candidate) }
      }
    }
    return result
  }

  private enum CodingKeys: String, CodingKey { case width, height, mineCount }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let width = try container.decode(Int.self, forKey: .width)
    let height = try container.decode(Int.self, forKey: .height)
    let mines = try container.decode(Int.self, forKey: .mineCount)
    guard width > 0, height > 0, mines >= 0, mines < width * height else {
      throw DecodingError.dataCorruptedError(
        forKey: .mineCount,
        in: container,
        debugDescription: "Invalid board configuration"
      )
    }
    self.width = width
    self.height = height
    self.mineCount = mines
  }
}

public enum Difficulty: String, CaseIterable, Codable, Sendable, Identifiable {
  case beginner
  case easy
  case medium
  case hard
  case huge
  case extreme

  public var id: String { rawValue }

  public var displayName: String {
    rawValue.prefix(1).uppercased() + rawValue.dropFirst()
  }

  public var configuration: BoardConfiguration {
    switch self {
    case .beginner: BoardConfiguration(width: 12, height: 22, mineCount: 12)
    case .easy: BoardConfiguration(width: 7, height: 10, mineCount: 10)
    case .medium: BoardConfiguration(width: 12, height: 22, mineCount: 40)
    case .hard: BoardConfiguration(width: 18, height: 32, mineCount: 100)
    case .huge: BoardConfiguration(width: 27, height: 48, mineCount: 220)
    case .extreme: BoardConfiguration(width: 18, height: 32, mineCount: 150)
    }
  }
}

public struct Cell: Hashable, Codable, Sendable {
  public let isMine: Bool
  public var isRevealed: Bool
  public var isFlagged: Bool
  public let adjacentMineCount: Int

  public init(
    isMine: Bool = false,
    isRevealed: Bool = false,
    isFlagged: Bool = false,
    adjacentMineCount: Int = 0
  ) {
    precondition((0...8).contains(adjacentMineCount))
    self.isMine = isMine
    self.isRevealed = isRevealed
    self.isFlagged = isFlagged
    self.adjacentMineCount = adjacentMineCount
  }
}

public enum GamePhase: String, Codable, Sendable {
  case ready
  case playing
  case won
  case lost

  public var isFinished: Bool { self == .won || self == .lost }
}

public enum ActionMode: String, CaseIterable, Codable, Sendable {
  case dig
  case flag

  public var secondary: ActionMode { self == .dig ? .flag : .dig }
}

public enum GameAction: String, Codable, Sendable {
  case dig
  case flag
  case chord
}

public struct GameActionResult: Equatable, Sendable {
  public let changedCoordinates: Set<CellCoordinate>
  public let previousPhase: GamePhase
  public let phase: GamePhase
  public let explodedMine: CellCoordinate?

  public var didChange: Bool { !changedCoordinates.isEmpty || previousPhase != phase }

  public init(
    changedCoordinates: Set<CellCoordinate> = [],
    previousPhase: GamePhase,
    phase: GamePhase,
    explodedMine: CellCoordinate? = nil
  ) {
    self.changedCoordinates = changedCoordinates
    self.previousPhase = previousPhase
    self.phase = phase
    self.explodedMine = explodedMine
  }
}

public struct GameSettings: Equatable, Codable, Sendable {
  public var cellBordersEnabled: Bool
  public var showsActionToggle: Bool
  public var defaultAction: ActionMode
  public var longPressEnabled: Bool
  public var longPressDelayMilliseconds: Int
  public var easyDiggingEnabled: Bool
  public var easyFlaggingEnabled: Bool
  public var animationSpeedPercent: Int
  public var vibrationEnabled: Bool
  public var vibrationDurationMilliseconds: Int

  public static let `default` = GameSettings()

  public init(
    cellBordersEnabled: Bool = false,
    showsActionToggle: Bool = true,
    defaultAction: ActionMode = .dig,
    longPressEnabled: Bool = true,
    longPressDelayMilliseconds: Int = 300,
    easyDiggingEnabled: Bool = true,
    easyFlaggingEnabled: Bool = false,
    animationSpeedPercent: Int = 100,
    vibrationEnabled: Bool = true,
    vibrationDurationMilliseconds: Int = 50
  ) {
    self.cellBordersEnabled = cellBordersEnabled
    self.showsActionToggle = showsActionToggle
    self.defaultAction = defaultAction
    self.longPressEnabled = longPressEnabled
    self.longPressDelayMilliseconds = longPressDelayMilliseconds.clamped(to: 100...500)
    self.easyDiggingEnabled = easyDiggingEnabled
    self.easyFlaggingEnabled = easyFlaggingEnabled
    self.animationSpeedPercent = animationSpeedPercent.clamped(to: 0...150)
    self.vibrationEnabled = vibrationEnabled
    self.vibrationDurationMilliseconds = vibrationDurationMilliseconds.clamped(to: 5...200)
    normalizeDependencies()
  }

  public mutating func normalizeDependencies() {
    longPressDelayMilliseconds = longPressDelayMilliseconds.clamped(to: 100...500)
    animationSpeedPercent = animationSpeedPercent.clamped(to: 0...150)
    vibrationDurationMilliseconds = vibrationDurationMilliseconds.clamped(to: 5...200)
    if !longPressEnabled { showsActionToggle = true }
  }
}

public struct ThemeIdentifier: RawRepresentable, Hashable, Codable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public static let alpine: ThemeIdentifier = "alpine"
}

public struct TimeRecord: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let difficulty: Difficulty
  public let duration: TimeInterval
  public let completedAt: Date

  public init(
    id: UUID = UUID(),
    difficulty: Difficulty,
    duration: TimeInterval,
    completedAt: Date = Date()
  ) {
    self.id = id
    self.difficulty = difficulty
    self.duration = max(0, duration)
    self.completedAt = completedAt
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
