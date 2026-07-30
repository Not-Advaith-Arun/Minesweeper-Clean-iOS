import Foundation
import SwiftUI

enum AppRoute: Hashable {
  case game(ReplicaDifficulty, resume: Bool)
  case settings
  case themes
  case times
}

enum ReplicaDifficulty: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
  case beginner
  case easy
  case medium
  case hard
  case huge
  case extreme

  var id: String { rawValue }

  var title: String { rawValue.capitalized }

  var size: GridSize {
    switch self {
    case .beginner: GridSize(columns: 12, rows: 22, mines: 12)
    case .easy: GridSize(columns: 7, rows: 10, mines: 10)
    case .medium: GridSize(columns: 12, rows: 22, mines: 40)
    case .hard: GridSize(columns: 18, rows: 32, mines: 100)
    case .huge: GridSize(columns: 27, rows: 48, mines: 220)
    case .extreme: GridSize(columns: 18, rows: 32, mines: 150)
    }
  }
}

struct GridSize: Codable, Hashable, Sendable {
  let columns: Int
  let rows: Int
  let mines: Int
}

enum PrimaryAction: String, Codable, CaseIterable, Identifiable {
  case dig
  case flag

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var symbol: String { self == .dig ? "hand.tap" : "flag.fill" }
}

struct UserSettings: Codable, Equatable {
  var cellBorders = false
  var showActionToggle = true
  var primaryAction: PrimaryAction = .dig
  var longPressEnabled = true
  var longPressDelayMilliseconds = 300.0
  var easyDigging = true
  var easyFlagging = false
  var animationSpeed = 100.0
  var vibrationEnabled = true
  var vibrationDurationMilliseconds = 50.0

  static let `default` = UserSettings()
}

struct SavedGameSummary: Codable, Hashable, Sendable {
  let difficulty: ReplicaDifficulty
  let elapsedSeconds: Int
  let savedAt: Date
}

struct ReplicaTimeRecord: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  let difficulty: ReplicaDifficulty
  let seconds: Int
  let date: Date

  init(id: UUID = UUID(), difficulty: ReplicaDifficulty, seconds: Int, date: Date = .now) {
    self.id = id
    self.difficulty = difficulty
    self.seconds = seconds
    self.date = date
  }
}

enum BoardCellVisual: Equatable {
  case covered
  case revealed(Int)
  case flagged
  case mine(triggered: Bool)
  case wrongFlag
}

enum ReplicaGamePhase: Equatable {
  case ready
  case playing
  case won
  case lost

  var isFinished: Bool { self == .won || self == .lost }
}

struct BoardPresentation: Equatable {
  let columns: Int
  let rows: Int
  var cells: [BoardCellVisual]

  init(columns: Int, rows: Int, cells: [BoardCellVisual]? = nil) {
    self.columns = columns
    self.rows = rows
    self.cells = cells ?? Array(repeating: .covered, count: columns * rows)
  }

  subscript(column: Int, row: Int) -> BoardCellVisual {
    let index = row * columns + column
    guard cells.indices.contains(index) else { return .covered }
    return cells[index]
  }
}

enum AppConstants {
  static let replicaName = "Minesweeper"
  static let appSubtitle = "The Clean One"
  static let settingsStorageKey = "replica.settings.v1"
  static let themeStorageKey = "replica.theme.v1"
  static let recordsStorageKey = "replica.records.v1"
  static let difficultyStorageKey = "replica.difficulty.v1"
}

extension Int {
  var clockString: String {
    let clamped = Swift.max(0, self)
    let hours = clamped / 3_600
    let minutes = (clamped % 3_600) / 60
    let seconds = clamped % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
      : String(format: "%d:%02d", minutes, seconds)
  }
}
