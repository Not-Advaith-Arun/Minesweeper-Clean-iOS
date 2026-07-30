import Foundation
import XCTest

@testable import MinesweeperCore

final class PersistenceTests: XCTestCase {
  private func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func testSettingsRoundTripAndMissingDefaults() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SettingsRepository(rootURL: root)
    let initial = await repository.loadState()
    XCTAssertEqual(initial, SettingsState())

    let expected = SettingsState(
      settings: GameSettings(defaultAction: .flag, vibrationEnabled: false),
      selectedTheme: "coffee"
    )
    try await repository.save(expected)
    let loaded = await repository.loadState()
    XCTAssertEqual(loaded, expected)
  }

  func testSnapshotsAreIndependentByDifficulty() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try GameSnapshotRepository(rootURL: root)
    let easy = GameEngine(difficulty: .easy, seed: 11).snapshot()
    let hard = GameEngine(difficulty: .hard, seed: 22).snapshot()
    try await repository.save(easy)
    try await repository.save(hard)
    let loadedEasy = try await repository.load(for: .easy)
    let loadedHard = try await repository.load(for: .hard)
    XCTAssertEqual(loadedEasy, easy)
    XCTAssertEqual(loadedHard, hard)

    try await repository.remove(for: .easy)
    let removedEasy = try await repository.load(for: .easy)
    let preservedHard = try await repository.load(for: .hard)
    XCTAssertNil(removedEasy)
    XCTAssertEqual(preservedHard, hard)
  }

  func testCorruptSnapshotDoesNotAffectOtherDifficulty() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try GameSnapshotRepository(rootURL: root)
    let hard = GameEngine(difficulty: .hard, seed: 22).snapshot()
    try await repository.save(hard)
    let games = root.appendingPathComponent("games", isDirectory: true)
    try Data("not-json".utf8).write(to: games.appendingPathComponent("easy.json"))
    let corruptEasy = try await repository.load(for: .easy)
    let preservedHard = try await repository.load(for: .hard)
    XCTAssertNil(corruptEasy)
    XCTAssertEqual(preservedHard, hard)
  }

  func testTimeRecordsSortLimitAndDelete() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try TimeRecordRepository(rootURL: root)
    let slow = TimeRecord(
      difficulty: .medium, duration: 30, completedAt: Date(timeIntervalSince1970: 1))
    let fast = TimeRecord(
      difficulty: .medium, duration: 10, completedAt: Date(timeIntervalSince1970: 2))
    let middle = TimeRecord(
      difficulty: .medium, duration: 20, completedAt: Date(timeIntervalSince1970: 3))
    try await repository.add(slow)
    try await repository.add(fast)
    try await repository.add(middle)
    let records = try await repository.records(for: .medium)
    let bestTwo = try await repository.bestRecords(for: .medium, limit: 2)
    XCTAssertEqual(records.map(\.duration), [10, 20, 30])
    XCTAssertEqual(bestTwo.map(\.duration), [10, 20])

    try await repository.remove(id: middle.id, from: .medium)
    let afterDelete = try await repository.records(for: .medium)
    XCTAssertEqual(afterDelete.map(\.duration), [10, 30])
  }

  func testPreparedBoardQueueIsFIFOAndBounded() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try ReadyBoardRepository(rootURL: root)
    let configuration = Difficulty.easy.configuration
    let first = CellCoordinate(row: 0, column: 0)
    func prepared(seed: UInt64) -> PreparedBoard {
      let mines = Set(
        (0..<configuration.mineCount).map {
          CellCoordinate(row: 1 + $0 / configuration.width, column: $0 % configuration.width)
        })
      return PreparedBoard(
        board: GeneratedBoard(configuration: configuration, seed: seed, mines: mines),
        firstReveal: first
      )
    }
    try await repository.enqueue(prepared(seed: 1), for: .easy, maximumCount: 2)
    try await repository.enqueue(prepared(seed: 2), for: .easy, maximumCount: 2)
    try await repository.enqueue(prepared(seed: 3), for: .easy, maximumCount: 2)
    let queued = await repository.boards(for: .easy)
    XCTAssertEqual(queued.map(\.board.seed), [2, 3])
    let dequeued = try await repository.dequeue(for: .easy)
    XCTAssertEqual(dequeued?.board.seed, 2)
  }
}
