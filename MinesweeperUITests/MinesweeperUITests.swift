import XCTest

@MainActor
final class MinesweeperUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["MINESWEEPER_UI_TESTING"] = "1"
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "1"
    app.launch()
  }

  private func wait(_ seconds: TimeInterval) {
    let settled = expectation(description: "Wait \(seconds) seconds")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
    waitForExpectations(timeout: seconds + 1)
  }

  func testActualFinalMovesReachWinAndLossPresentation() {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_win"
    app.launch()
    var board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    // Medium's deterministic terminal cell is row 10, column 6 on a 12×22 canvas.
    board.coordinate(withNormalizedOffset: CGVector(dx: 6.5 / 12, dy: 10.5 / 22)).tap()
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 3))
    // The score card owns the hierarchy while presented; the restart panel
    // must not compete behind it.
    XCTAssertFalse(app.buttons["game.startNew"].exists)
    app.buttons["game.dismissResult"].tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 2))

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launch()
    board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 6.5 / 12, dy: 10.5 / 22)).tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["game.dismissResult"].exists)
  }

  func testGameCanRevealFlagPersistAndResume() {
    let newGame = app.buttons["home.newGame"]
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newGame)
    waitForExpectations(timeout: 3)
    newGame.tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 3))

    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    let timer = app.staticTexts["game.timer"]
    XCTAssertTrue(timer.waitForExistence(timeout: 4))
    expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: timer)
    waitForExpectations(timeout: 4)

    board.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.60))
      .press(forDuration: 0.4)
    app.buttons["game.back"].tap()
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 3))

    let saveSettled = expectation(description: "The atomic save reaches disk")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { saveSettled.fulfill() }
    waitForExpectations(timeout: 1)

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "0"
    app.launch()
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 3))
    app.buttons["home.resume"].tap()
    XCTAssertTrue(app.otherElements["game.board"].waitForExistence(timeout: 3))
  }

  private func verifyHomeSpacingWithResume() throws {
    let newGame = app.buttons["home.newGame"]
    XCTAssertTrue(newGame.waitForExistence(timeout: 5))
    newGame.tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    // A pre-opening flag creates a resumable game without random generation.
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.5)
    app.buttons["game.back"].tap()
    let resume = app.buttons["home.resume"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    let previous = app.buttons["home.previousDifficulty"]
    XCTAssertGreaterThanOrEqual(newGame.frame.minY - previous.frame.maxY, 8)
    XCTAssertGreaterThanOrEqual(resume.frame.minY - newGame.frame.maxY, 12)
    XCTAssertGreaterThanOrEqual(
      app.buttons["home.settings"].frame.minY - resume.frame.maxY, 12)
  }

  func testSlowRestartKeepsGesturesFromMovingTheReadyBoard() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launchEnvironment["MINESWEEPER_UI_TEST_ANIMATION_SPEED"] = "25"
    app.launch()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
    let restart = app.buttons["game.startNew"]
    XCTAssertTrue(restart.waitForExistence(timeout: 10))
    // At 25% speed the control exists before its entrance reaches the tap
    // position. This check targets gestures during the restart itself.
    wait(1.5)
    XCTAssertTrue(restart.isHittable)
    restart.tap()
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Ready'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
      .press(forDuration: 0.05,
             thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)))
    board.pinch(withScale: 1.5, velocity: 2)
    wait(5)
    XCTAssertEqual(board.value as? String, "Ready")
    XCTAssertFalse(restart.exists)
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let playing = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Playing' OR value == 'Won'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
  }

  func testLargestTextHomeThemesAndSettingsRemainUsable() throws {
    app.terminate()
    app.launchArguments = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    XCTAssertGreaterThan(app.buttons["home.newGame"].frame.height, 44)
    let difficulty = app.descendants(matching: .any)["home.difficulty"]
    app.buttons["home.nextDifficulty"].tap()
    XCTAssertTrue(difficulty.label.contains("Easy"))
    app.buttons["home.previousDifficulty"].tap()
    XCTAssertTrue(difficulty.label.contains("Beginner"))
    try verifyHomeSpacingWithResume()
    for _ in 0..<4 where !app.buttons["home.quickThemes"].isHittable { app.swipeDown() }
    app.buttons["home.quickThemes"].tap()
    let material = app.buttons["theme.material_you_amoled"]
    XCTAssertTrue(material.waitForExistence(timeout: 3))
    XCTAssertGreaterThan(material.frame.width, 250)
    XCTAssertGreaterThan(material.frame.height, 56)
    let monokai = app.buttons["theme.monokai"]
    for _ in 0..<6 where !monokai.isHittable { app.swipeUp() }
    XCTAssertTrue(monokai.isHittable)
    monokai.tap()
    XCTAssertTrue(monokai.isSelected)
    app.buttons["replica.back"].tap()
    for _ in 0..<4 where !app.buttons["home.settings"].isHittable { app.swipeUp() }
    app.buttons["home.settings"].tap()
    let flag = app.buttons["settings.primaryAction.flag"]
    for _ in 0..<12 where !flag.isHittable { app.swipeUp() }
    XCTAssertTrue(flag.isHittable)
    flag.tap()
    XCTAssertTrue(flag.isSelected)
    let reset = app.buttons["settings.reset"]
    for _ in 0..<14 where !reset.isHittable { app.swipeUp() }
    XCTAssertTrue(reset.isHittable)
    reset.tap()
    let confirmation = app.alerts["Reset settings?"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
    confirmation.buttons["Cancel"].tap()
    for _ in 0..<14 where !flag.isHittable { app.swipeDown() }
    XCTAssertTrue(flag.isSelected)
  }


}
