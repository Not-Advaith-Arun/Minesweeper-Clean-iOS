import XCTest

@MainActor
final class MinesweeperUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["MINESWEEPER_UI_TESTING"] = "1"
    if !name.contains("LiveBorderCorner") {
      app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "1"
    }
    app.launch()
  }

  private func capture(_ name: String) throws {
    let screenshot = XCUIScreen.main.screenshot()
    let url = URL(fileURLWithPath: "/private/tmp/minesweeper-\(name).png")
    try screenshot.pngRepresentation.write(to: url, options: .atomic)
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func wait(_ seconds: TimeInterval) {
    let settled = expectation(description: "Wait \(seconds) seconds")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
    waitForExpectations(timeout: seconds + 1)
  }

  func testCaptureCompleteEasyGameJourney() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()
    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
    try capture("easy-01-home")

    app.buttons["home.newGame"].tap()
    var board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    try capture("easy-02-ready")
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    try capture("easy-03-first-tap")
    wait(0.20)
    try capture("easy-04-reveal-wave")
    wait(0.45)
    try capture("easy-05-zoom-settle")
    wait(0.50)
    try capture("easy-06-playing")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_win"
    app.launch()
    board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    try capture("easy-07-before-final-tap")
    // The board accessibility frame follows the full 7 x 10 canvas. The final
    // safe cell in the deterministic near-win fixture is row 4, column 3.
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    try capture("easy-08-final-tap")
    wait(0.25)
    try capture("easy-09-win-settle")
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 3))
    try capture("easy-10-result-dialog")
    app.buttons["game.dismissResult"].tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 2))
    try capture("easy-11-completed")
  }

  func testCaptureBoardCornerRegression() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "pink_amoled"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()

    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    wait(0.2)
    try capture("corner-regression-01-ready")

    // Open a cell at the left edge so both the outside silhouette and the
    // concave corners where revealed and covered regions meet are visible.
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.075, dy: 0.50)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    wait(0.8)
    try capture("corner-regression-02-edge-reveal")
  }

  func testCaptureLiveBorderCorner() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "nennau"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launchEnvironment["MINESWEEPER_UI_TEST_CELL_BORDERS"] = "1"
    app.launch()
    XCTAssertTrue(app.otherElements["game.board"].waitForExistence(timeout: 4))
    wait(0.5)
    try capture("live-border-corners-fixed")
  }

  func testCaptureEasyLossJourney() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launch()

    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    try capture("easy-loss-01-before-mine")

    // The deterministic Easy mine is row 4, column 3.
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    try capture("easy-loss-02-mine-hit")
    wait(0.20)
    try capture("easy-loss-03-mine-cascade")
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 3))
    try capture("easy-loss-04-settled")
  }

  func testCaptureEveryDifficultyFirstReveal() throws {
    for difficulty in ["beginner", "easy", "medium", "hard", "huge", "extreme"] {
      app.terminate()
      app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = difficulty
      app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
      app.launch()

      let newGame = app.buttons["home.newGame"]
      XCTAssertTrue(newGame.waitForExistence(timeout: 4), "Missing New Game for \(difficulty)")
      newGame.tap()

      let board = app.otherElements["game.board"]
      XCTAssertTrue(board.waitForExistence(timeout: 4), "Missing board for \(difficulty)")
      try capture("difficulty-\(difficulty)-ready")
      board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
      XCTAssertTrue(
        app.staticTexts["game.timer"].waitForExistence(timeout: 4),
        "First reveal did not enter play for \(difficulty)"
      )
      wait(1.1)
      try capture("difficulty-\(difficulty)-revealed")
    }
  }

  func testCaptureVisualBaseline() throws {
    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
    try capture("home")

    app.buttons["home.themes"].tap()
    XCTAssertTrue(app.staticTexts["Themes"].waitForExistence(timeout: 2))
    try capture("themes")
    app.buttons["replica.back"].tap()

    app.buttons["home.settings"].tap()
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2))
    try capture("settings")
    app.buttons["replica.back"].tap()

    app.buttons["home.times"].tap()
    XCTAssertTrue(app.staticTexts["Top times"].waitForExistence(timeout: 2))
    try capture("times")
    app.buttons["replica.back"].tap()

    app.buttons["home.about"].tap()
    XCTAssertTrue(app.buttons["about.done"].waitForExistence(timeout: 2))
    try capture("about")
    app.buttons["about.done"].tap()

    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    try capture("game-ready")

    board.coordinate(withNormalizedOffset: CGVector(dx: 6.5 / 12, dy: 10.5 / 22)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    try capture("game-active")

    app.buttons["Theme picker"].tap()
    try capture("game-palette")
  }

  func testCaptureGlassChromeInAMOLEDTheme() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "pink_amoled"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()

    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
    try capture("glass-amoled-home")
    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    wait(0.8)
    try capture("glass-amoled-playing")
    app.buttons["Theme picker"].tap()
    try capture("glass-amoled-palette")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launch()
    let flagBoard = app.otherElements["game.board"]
    XCTAssertTrue(flagBoard.waitForExistence(timeout: 4))
    app.buttons["Flag"].tap()
    flagBoard.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    wait(0.2)
    XCTAssertLessThan(Int(app.staticTexts["game.mines"].label) ?? 10, 10)
    try capture("glass-amoled-flagged")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "won"
    app.launch()
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 4))
    try capture("glass-amoled-result")
  }

  func testCapturePopulatedTimesAndDeleteConfirmation() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "medium"
    app.launchEnvironment["MINESWEEPER_UI_TEST_RECORDS"] = "1"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()

    XCTAssertTrue(app.buttons["home.times"].waitForExistence(timeout: 4))
    app.buttons["home.times"].tap()
    XCTAssertTrue(app.staticTexts["17S"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["50S"].exists)
    try capture("times-populated")

    app.cells.firstMatch.swipeLeft()
    XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
    app.buttons["Delete"].tap()
    XCTAssertTrue(app.alerts["Delete this time?"].waitForExistence(timeout: 2))
    try capture("times-delete-confirmation")
    app.alerts["Delete this time?"].buttons["Cancel"].tap()
    XCTAssertTrue(app.staticTexts["17S"].exists)
  }

  func testCaptureEndGameStates() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "won"
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 4))
    try capture("game-win-dialog")
    app.buttons["game.dismissResult"].tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 2))
    try capture("game-won")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "lost"
    app.launch()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 4))
    try capture("game-lost")
  }

  func testExerciseFirstRevealMotion() {
    let newGame = app.buttons["home.newGame"]
    XCTAssertTrue(newGame.waitForExistence(timeout: 4))
    newGame.tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    let motionSettled = expectation(description: "First-reveal motion settles")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { motionSettled.fulfill() }
    waitForExpectations(timeout: 2)
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

  func testBoardPinchAndPanKeepOverlaysFixed() throws {
    let newGame = app.buttons["home.newGame"]
    XCTAssertTrue(newGame.waitForExistence(timeout: 4))
    newGame.tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))

    let back = app.buttons["game.back"]
    let palette = app.buttons["Theme picker"]
    let backFrame = back.frame
    let paletteFrame = palette.frame
    board.pinch(withScale: 1.8, velocity: 2.0)
    // After a pinch, XCUITest reports the board accessibility frame in the
    // transformed canvas coordinate space. Use stable window coordinates so
    // the follow-up pan stays in the visible board and away from system edges.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.62))
      .press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.42))
      )
    // Preserve the pre-gesture frames and verify the fixed overlays did not
    // participate in the board's zoom or pan transform.
    XCTAssertFalse(backFrame.isEmpty)
    XCTAssertFalse(paletteFrame.isEmpty)
    XCTAssertEqual(back.frame.origin.x, backFrame.origin.x, accuracy: 1)
    XCTAssertEqual(back.frame.origin.y, backFrame.origin.y, accuracy: 1)
    XCTAssertEqual(palette.frame.origin.x, paletteFrame.origin.x, accuracy: 1)
    XCTAssertEqual(palette.frame.origin.y, paletteFrame.origin.y, accuracy: 1)
    XCTAssertTrue(back.exists)
    XCTAssertTrue(palette.exists)
    try capture("game-pan-overlays")
    board.pinch(withScale: 0.1, velocity: -2.0)
    XCTAssertTrue(board.exists)
  }

  func testHomeExposesPrimaryReplicaControls() {
    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["home.settings"].exists)
    XCTAssertTrue(app.buttons["home.themes"].exists)
    XCTAssertTrue(app.buttons["home.times"].exists)
    XCTAssertTrue(app.buttons["home.about"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["home.difficulty"].exists)
  }

  func testDifficultyCarouselAndReplacementWarning() {
    let difficulty = app.descendants(matching: .any)["home.difficulty"]
    XCTAssertTrue(difficulty.waitForExistence(timeout: 3))
    XCTAssertTrue(difficulty.label.contains("Beginner"))
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.445))
      .press(
        forDuration: 0.08,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.445))
      )
    expectation(
      for: NSPredicate(format: "label CONTAINS 'Easy'"),
      evaluatedWith: difficulty
    )
    waitForExpectations(timeout: 3)

    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 3))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    app.buttons["game.back"].tap()
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 3))

    app.buttons["home.newGame"].tap()
    let warning = app.alerts["Start a new game?"]
    XCTAssertTrue(warning.waitForExistence(timeout: 2))
    XCTAssertTrue(warning.staticTexts["Your unfinished Easy game will be replaced."].exists)
    warning.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["home.resume"].exists)

    app.buttons["home.newGame"].tap()
    XCTAssertTrue(warning.waitForExistence(timeout: 2))
    warning.buttons["Replace"].tap()
    XCTAssertTrue(app.otherElements["game.board"].waitForExistence(timeout: 3))
  }

  func testActionToggleSelectionInGame() {
    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 3))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.buttons["Flag"].waitForExistence(timeout: 4))
    XCTAssertTrue(app.buttons["Dig"].isSelected)
    app.buttons["Flag"].tap()
    XCTAssertTrue(app.buttons["Flag"].isSelected)
    XCTAssertFalse(app.buttons["Dig"].isSelected)
  }

  func testSettingsLongPressDependencyAndReset() {
    app.buttons["home.settings"].tap()
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2))

    let longPress = app.switches["settings.longPress"]
    let actionToggle = app.switches["settings.actionToggle"]
    XCTAssertTrue(longPress.waitForExistence(timeout: 2))
    XCTAssertTrue(actionToggle.exists)

    if actionToggle.value as? String == "1" {
      actionToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
    expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: actionToggle)
    waitForExpectations(timeout: 3)

    if longPress.value as? String == "1" {
      longPress.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
    expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: longPress)
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: actionToggle)
    expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: actionToggle)
    waitForExpectations(timeout: 3)
    XCTAssertEqual(actionToggle.value as? String, "1")
    XCTAssertFalse(actionToggle.isEnabled)

    longPress.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: longPress)
    expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: actionToggle)
    expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: actionToggle)
    waitForExpectations(timeout: 3)
    XCTAssertEqual(actionToggle.value as? String, "0")
    XCTAssertTrue(actionToggle.isEnabled)

    app.buttons["settings.reset"].tap()
    app.alerts["Reset settings?"].buttons["Reset"].tap()
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: longPress)
    waitForExpectations(timeout: 3)
    XCTAssertEqual(longPress.value as? String, "1")
  }

  func testAllMajorDestinationsOpen() {
    app.buttons["home.themes"].tap()
    XCTAssertTrue(app.staticTexts["Themes"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["theme.pink_amoled"].exists)
    app.buttons["theme.pink_amoled"].tap()
    app.buttons["replica.back"].tap()

    app.buttons["home.times"].tap()
    XCTAssertTrue(app.staticTexts["Top times"].waitForExistence(timeout: 2))
    app.buttons["replica.back"].tap()

    app.buttons["home.about"].tap()
    XCTAssertTrue(app.buttons["about.done"].waitForExistence(timeout: 2))
    app.buttons["about.done"].tap()
  }

  func testThemeSelectionPersistsAcrossRelaunch() {
    app.buttons["home.themes"].tap()
    XCTAssertTrue(app.buttons["theme.pink_amoled"].waitForExistence(timeout: 2))
    app.buttons["theme.pink_amoled"].tap()
    XCTAssertTrue(app.buttons["theme.pink_amoled"].isSelected)

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "0"
    app.launch()
    XCTAssertTrue(app.buttons["home.themes"].waitForExistence(timeout: 3))
    app.buttons["home.themes"].tap()
    XCTAssertTrue(app.buttons["theme.pink_amoled"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["theme.pink_amoled"].isSelected)
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

  func testPortraitOnlyContract() {
    let window = app.windows.element(boundBy: 0)
    XCTAssertGreaterThan(window.frame.height, window.frame.width)
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 2))
    XCTAssertGreaterThan(window.frame.height, window.frame.width)
    XCUIDevice.shared.orientation = .portrait
  }
}
