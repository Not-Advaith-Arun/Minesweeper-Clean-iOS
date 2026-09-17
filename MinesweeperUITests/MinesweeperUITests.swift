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

  /// Extreme reserves the center-right cell of its even-sized 18 x 32 board.
  /// The ready canvas is width-fitted and vertically centered at 54% of the
  /// viewport, so the accessibility element's geometric center is not the
  /// marked cell. Resolve the same fit transform as BoardViewport so the UI
  /// test presses the visible target on every iPhone and iPad size.
  private func tapOpening(on board: XCUIElement, difficulty: String) {
    guard difficulty == "extreme" else {
      board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
      return
    }

    let viewport = board.frame
    let appFrame = app.frame
    let baseCell: CGFloat = 44
    let columns: CGFloat = 18
    let rows: CGFloat = 32
    let boardAspect = columns / rows
    if abs((viewport.width / viewport.height) - boardAspect) < 0.03 {
      board.coordinate(
        withNormalizedOffset: CGVector(dx: 9.5 / columns, dy: 16.5 / rows)
      ).tap()
      return
    }

    let scale = min(
      viewport.height / (rows * baseCell),
      viewport.width / (columns * baseCell) * 0.79
    )
    let x = viewport.midX + ((9.5 * baseCell) - (columns * baseCell / 2)) * scale
    let y = viewport.minY + viewport.height * 0.54
      + ((16.5 * baseCell) - (rows * baseCell / 2)) * scale
    app.coordinate(
      withNormalizedOffset: CGVector(
        dx: (x - appFrame.minX) / appFrame.width,
        dy: (y - appFrame.minY) / appFrame.height
      )
    ).tap()
  }

  /// The near-loss fixture's center mine can be outside the initial playing
  /// viewport on compact phones. Pick a visible unflagged fixture mine and
  /// tap in window coordinates, independent of XCTest's clipped board frame.
  private func tapVisibleExtremePreviewMine(on board: XCUIElement) {
    let columns = 18
    let rows = 32
    let zoom: CGFloat = 1.15
    let pitch: CGFloat = 44 * zoom
    let appFrame = app.frame
    let boardFrame = board.frame
    let canvasSize = CGSize(width: CGFloat(columns) * pitch, height: CGFloat(rows) * pitch)
    let canvasFrame: CGRect
    if abs(boardFrame.width - canvasSize.width) < 2,
      abs(boardFrame.height - canvasSize.height) < 2
    {
      canvasFrame = boardFrame
    } else {
      // BoardViewport opens a playing fixture at 1.15x around the viewport
      // center. Its pan insets do not move this initial visible origin.
      // Dimensions distinguish the full canvas from a clipped viewport;
      // the SE viewport coincidentally has the same aspect ratio as Extreme.
      canvasFrame = CGRect(
        x: appFrame.minX - appFrame.width * (zoom - 1) / 2,
        y: appFrame.minY - appFrame.height * (zoom - 1) / 2,
        width: canvasSize.width,
        height: canvasSize.height
      )
    }

    // Match GameSessionController.previewEngine's near_loss layout, including
    // its one correct flag, which cannot be detonated by the primary action.
    let centerIndex = (rows / 2 - 1) * columns + columns / 2
    var mines: Set<Int> = [centerIndex]
    var candidate = 0
    while mines.count < 150 {
      mines.insert((candidate * 37 + 11) % (columns * rows))
      candidate += 1
    }
    let flaggedMine = mines.filter { $0 != centerIndex }.min()
    let visibleField = appFrame.insetBy(dx: appFrame.width * 0.12, dy: appFrame.height * 0.24)
    let targets = mines.filter { $0 != flaggedMine }.map { index in
      CGPoint(
        x: canvasFrame.minX + (CGFloat(index % columns) + 0.5) * pitch,
        y: canvasFrame.minY + (CGFloat(index / columns) + 0.5) * pitch
      )
    }.filter { visibleField.contains($0) }
    guard let target = targets.min(by: {
      hypot($0.x - appFrame.midX, $0.y - appFrame.midY)
        < hypot($1.x - appFrame.midX, $1.y - appFrame.midY)
    }) else {
      XCTFail("The Extreme preview must have a mine inside the visible playing field")
      return
    }
    app.coordinate(withNormalizedOffset: CGVector(
      dx: (target.x - appFrame.minX) / appFrame.width,
      dy: (target.y - appFrame.minY) / appFrame.height
    )).tap()
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
    wait(0.25)
    try capture("easy-04-reveal-wave")
    wait(0.50)
    try capture("easy-05-zoom-start")
    wait(0.25)
    try capture("easy-06-zoom-glide")
    wait(0.40)
    try capture("easy-07-playing")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_win"
    app.launch()
    board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    try capture("easy-08-before-final-tap")
    // The board accessibility frame follows the full 7 x 10 canvas. The final
    // safe cell in the deterministic near-win fixture is row 4, column 3.
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    try capture("easy-09-final-tap")
    wait(0.25)
    try capture("easy-10-win-settle")
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 3))
    try capture("easy-11-result-dialog")
    app.buttons["game.dismissResult"].tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 2))
    try capture("easy-12-completed")
  }

  func testCaptureRestartTransition() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "kawa"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launch()

    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 3))
    try capture("restart-01-finished")

    app.buttons["game.startNew"].tap()
    wait(0.18)
    try capture("restart-02-controls-dismiss")
    wait(0.22)
    try capture("restart-03-old-board-fade")
    wait(0.24)
    try capture("restart-04-slab-crossfade")
    wait(0.30)
    try capture("restart-05-slab-grow")
    wait(0.48)
    try capture("restart-06-ready")
  }

  func testCapturePostWinReplayTimeline() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "kawa"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_win"
    app.launch()

    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 3))
    app.buttons["game.dismissResult"].tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 2))

    wait(0.15)
    try capture("replay-01-covered")
    wait(0.50)
    try capture("replay-02-history")
    wait(1.25)
    try capture("replay-03-completed")
    wait(1.35)
    try capture("replay-04-wipe-start")
    wait(0.42)
    try capture("replay-05-wipe-expand")
    wait(0.50)
    try capture("replay-06-loop-reset")
  }

  func testCaptureBoardCornerRegression() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "blue_amoled"
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

  func testCaptureBoardTopologyPolishAcrossThemes() throws {
    for theme in ["material_you_amoled", "amoled", "blue_amoled", "alpine", "aurum", "monokai"] {
      app.terminate()
      app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = theme
      app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
      app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "topology"
      app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_CELL_BORDERS")
      app.launch()

      XCTAssertTrue(app.otherElements["game.board"].waitForExistence(timeout: 4))
      wait(0.35)
      try capture("topology-polish-\(theme)")
    }
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

  func testCaptureExtremeLossCinematic() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "kawa"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "extreme"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launch()

    let board = app.otherElements["game.board"]
    let actionToggle = app.buttons["Dig"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    XCTAssertTrue(actionToggle.waitForExistence(timeout: 2))
    try capture("extreme-loss-01-before-mine")

    tapVisibleExtremePreviewMine(on: board)
    XCTAssertTrue(actionToggle.exists, "The action capsule must remain during the mine wave")
    try capture("extreme-loss-02-detonation")
    wait(0.12)
    try capture("extreme-loss-03-first-neighbor")
    wait(0.22)
    try capture("extreme-loss-04-zoom-begins")
    wait(0.32)
    try capture("extreme-loss-05-zoom-settles")
    wait(0.34)
    try capture("extreme-loss-06-wave-settles")

    XCTAssertEqual(board.value as? String, "Lost", "The visible fixture mine must detonate")
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 2))
    XCTAssertFalse(actionToggle.exists)
    try capture("extreme-loss-07-controls")
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
      tapOpening(on: board, difficulty: difficulty)
      let opened = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == 'Playing' OR value == 'Won'"),
        object: board
      )
      XCTAssertEqual(
        XCTWaiter.wait(for: [opened], timeout: difficulty == "extreme" ? 120 : 15),
        .completed,
        "First reveal did not enter play for \(difficulty)"
      )
      wait(1.1)
      try capture("difficulty-\(difficulty)-revealed")
    }
  }

  /// Plays the real generated Extreme board — no scripted state — until it detonates, so the
  /// settled frame shows the entire mine layout the generator actually produced.
  func testCaptureExtremeGeneratedLayoutReveal() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "extreme"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()

    let newGame = app.buttons["home.newGame"]
    XCTAssertTrue(newGame.waitForExistence(timeout: 6))
    newGame.tap()

    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 8))

    // Extreme verifies its board off the interaction path, so the canvas reports "preparing"
    // until the warm pool hands one over. Waiting for that is what makes the opening tap land.
    var preparationTicks = 0
    while board.label.localizedCaseInsensitiveContains("preparing"), preparationTicks < 90 {
      wait(2.0)
      preparationTicks += 1
    }
    XCTAssertFalse(
      board.label.localizedCaseInsensitiveContains("preparing"),
      "Extreme still preparing after \(preparationTicks) polls"
    )
    try capture("extreme-layout-01-ready")

    tapOpening(on: board, difficulty: "extreme")
    let opened = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Playing'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 120), .completed)
    wait(1.1)
    try capture("extreme-layout-02-first-reveal")

    // The zoomed canvas extends beyond the screen. Probe window coordinates
    // inside the visible field, away from the header and action capsule.
    let startNew = app.buttons["game.startNew"]
    for row in 0..<6 where board.value as? String == "Playing" {
      for column in 0..<6 where board.value as? String == "Playing" {
        app.coordinate(withNormalizedOffset: CGVector(
          dx: 0.18 + CGFloat(column) * 0.128,
          dy: 0.28 + CGFloat(row) * 0.084
        )).tap()
      }
    }

    XCTAssertEqual(board.value as? String, "Lost", "Visible probes must expose a mine")
    XCTAssertTrue(startNew.waitForExistence(timeout: 8), "Extreme probing never found a mine")
    wait(1.5)
    try capture("extreme-layout-03-mines-revealed")
  }

  func testCaptureVisualBaseline() throws {
    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
    try capture("home")

    app.buttons["home.quickThemes"].tap()
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

    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    try capture("game-ready")

    board.coordinate(withNormalizedOffset: CGVector(dx: 6.5 / 12, dy: 10.5 / 22)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    XCTAssertTrue(app.buttons["Dig"].waitForExistence(timeout: 5))
    wait(0.35)
    try capture("game-active")

    app.buttons["Theme picker"].tap()
    try capture("game-palette")
  }

  func testCaptureGlassChromeInAMOLEDTheme() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "blue_amoled"
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
    wait(0.2)
    XCTAssertTrue(app.buttons["Flag"].exists)
    try capture("glass-amoled-flagged")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "won"
    app.launch()
    XCTAssertTrue(app.buttons["game.dismissResult"].waitForExistence(timeout: 4))
    try capture("glass-amoled-result")
  }

  func testCaptureMonoOLEDThemeAcrossPrimaryStates() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_THEME"] = "monochrome_oled"
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()

    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
    try capture("mono-oled-home")
    app.buttons["home.newGame"].tap()
    var board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.staticTexts["game.timer"].waitForExistence(timeout: 4))
    wait(0.9)
    try capture("mono-oled-playing")

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_loss"
    app.launch()
    board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 4))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 4))
    try capture("mono-oled-loss")
  }

  /// Opt-in visual audit used to confirm that the cached Extreme topology does
  /// not turn into a cached final mine layout. Run this test with
  /// MINESWEEPER_CAPTURE_EXTREME_VARIETY=1 to capture five fresh sessions that
  /// all use the same first-reveal coordinate.
  func testCaptureMultipleExtremeSessions() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["MINESWEEPER_CAPTURE_EXTREME_VARIETY"] == "1",
      "Opt-in Extreme variety capture"
    )

    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "extreme"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")

    for sample in 1...5 {
      app.terminate()
      app.launch()
      XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 4))
      app.buttons["home.newGame"].tap()

      let board = app.otherElements["game.board"]
      XCTAssertTrue(board.waitForExistence(timeout: 4))
      tapOpening(on: board, difficulty: "extreme")
      let timer = app.staticTexts["game.timer"].firstMatch
      XCTAssertTrue(
        timer.waitForExistence(timeout: 15),
        "Extreme board did not finish preparing for sample \(sample)"
      )
      wait(0.55)
      try capture(String(format: "extreme-random-%02d", sample))

      // Expose the complete random layout for the pattern audit. Extreme is
      // dense enough that this deterministic scatter reliably reaches a mine,
      // while each tap remains inside the visible board and away from chrome.
      let lossCandidates = [
        CGVector(dx: 0.22, dy: 0.35), CGVector(dx: 0.78, dy: 0.35),
        CGVector(dx: 0.22, dy: 0.47), CGVector(dx: 0.78, dy: 0.47),
        CGVector(dx: 0.22, dy: 0.59), CGVector(dx: 0.78, dy: 0.59),
        CGVector(dx: 0.34, dy: 0.39), CGVector(dx: 0.66, dy: 0.39),
        CGVector(dx: 0.34, dy: 0.55), CGVector(dx: 0.66, dy: 0.55),
        CGVector(dx: 0.42, dy: 0.34), CGVector(dx: 0.58, dy: 0.62),
        CGVector(dx: 0.50, dy: 0.40), CGVector(dx: 0.50, dy: 0.58),
        CGVector(dx: 0.28, dy: 0.66), CGVector(dx: 0.40, dy: 0.66),
        CGVector(dx: 0.60, dy: 0.66), CGVector(dx: 0.72, dy: 0.66),
        CGVector(dx: 0.30, dy: 0.30), CGVector(dx: 0.70, dy: 0.30),
      ]
      for candidate in lossCandidates where !app.buttons["game.startNew"].exists {
        app.coordinate(withNormalizedOffset: candidate).tap()
        wait(0.10)
      }
      XCTAssertTrue(
        app.buttons["game.startNew"].waitForExistence(timeout: 4),
        "Extreme audit must reach a mine and reveal the full layout"
      )
      try capture(String(format: "extreme-random-loss-%02d", sample))
    }
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
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
    for destination in [
      CGVector(dx: 0.55, dy: 0.30),
      CGVector(dx: 0.55, dy: 0.80),
      CGVector(dx: 0.22, dy: 0.55),
      CGVector(dx: 0.88, dy: 0.55),
    ] {
      center.press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: destination)
      )
    }
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
    XCTAssertTrue(app.buttons["home.quickThemes"].exists)
    XCTAssertTrue(app.buttons["home.times"].exists)
    XCTAssertTrue(app.buttons["home.previousDifficulty"].exists)
    XCTAssertFalse(app.buttons["home.themes"].exists)
    XCTAssertFalse(app.buttons["home.about"].exists)
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

  func testActionToggleSelectionInGame() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launch()
    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 3))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).tap()
    XCTAssertTrue(app.buttons["Flag"].waitForExistence(timeout: 4))
    let flag = app.buttons["Flag"]
    let dig = app.buttons["Dig"]
    XCTAssertEqual(dig.value as? String, "Selected")
    flag.tap()
    wait(0.25)
    try capture("action-toggle-flag-selected")

    let mines = app.descendants(matching: .any)["game.mines"]
    XCTAssertTrue(mines.waitForExistence(timeout: 2))
    let initialMineCount = mines.label
    let candidateCells = [
      CGVector(dx: 0.25, dy: 0.36),
      CGVector(dx: 0.75, dy: 0.36),
      CGVector(dx: 0.25, dy: 0.58),
      CGVector(dx: 0.75, dy: 0.58),
    ]
    for candidate in candidateCells where mines.label == initialMineCount {
      app.coordinate(withNormalizedOffset: candidate).tap()
    }
    XCTAssertNotEqual(mines.label, initialMineCount, "Flag mode must place a flag on a covered cell")
  }

  func testSettingsLongPressDependencyAndReset() {
    app.buttons["home.settings"].tap()
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2))

    let longPress = app.switches["settings.longPress"]
    let actionToggle = app.switches["settings.actionToggle"]
    XCTAssertTrue(longPress.waitForExistence(timeout: 2))
    XCTAssertTrue(actionToggle.exists)
    XCTAssertTrue(app.sliders["settings.animationSpeed"].exists)

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
    app.buttons["home.quickThemes"].tap()
    XCTAssertTrue(app.staticTexts["Themes"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["theme.blue_amoled"].exists)
    app.buttons["theme.blue_amoled"].tap()
    app.buttons["replica.back"].tap()

    app.buttons["home.times"].tap()
    XCTAssertTrue(app.staticTexts["Top times"].waitForExistence(timeout: 2))
    app.buttons["replica.back"].tap()

  }

  func testThemeSelectionPersistsAcrossRelaunch() {
    app.buttons["home.quickThemes"].tap()
    XCTAssertTrue(app.buttons["theme.blue_amoled"].waitForExistence(timeout: 2))
    app.buttons["theme.blue_amoled"].tap()
    XCTAssertTrue(app.buttons["theme.blue_amoled"].isSelected)

    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "0"
    app.launch()
    XCTAssertTrue(app.buttons["home.quickThemes"].waitForExistence(timeout: 3))
    app.buttons["home.quickThemes"].tap()
    XCTAssertTrue(app.buttons["theme.blue_amoled"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["theme.blue_amoled"].isSelected)
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

  func testHomeControlsKeepTheirSpacingWithResume() throws {
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
    try capture("polish-home-resume")
  }

  func testAnimationOffFinishesAndRestartsWithoutStaleControls() throws {
    for outcome in ["near_win", "near_loss"] {
      app.terminate()
      app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
      app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = outcome
      app.launchEnvironment["MINESWEEPER_UI_TEST_ANIMATION_SPEED"] = "0"
      app.launch()
      let board = app.otherElements["game.board"]
      XCTAssertTrue(board.waitForExistence(timeout: 5))
      board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
      if outcome == "near_win" {
        let dismiss = app.buttons["game.dismissResult"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 2))
        try capture("polish-animation-off-win")
        dismiss.tap()
      } else {
        try capture("polish-animation-off-loss")
      }
      let restart = app.buttons["game.startNew"]
      XCTAssertTrue(restart.waitForExistence(timeout: 2))
      restart.tap()
      wait(1.6)
      XCTAssertTrue(board.exists)
      XCTAssertFalse(restart.exists)
      XCTAssertFalse(app.buttons["game.dismissResult"].exists)
      XCTAssertFalse(app.buttons["Dig"].exists)
      try capture("polish-animation-off-\(outcome)-restarted")
    }
  }

  func testRestartDuringWinReplayReturnsToReadyBoard() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_win"
    // Slow the wipe enough for XCTest to interrupt it through real controls.
    app.launchEnvironment["MINESWEEPER_UI_TEST_ANIMATION_SPEED"] = "25"
    app.launch()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
    let dismiss = app.buttons["game.dismissResult"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
    dismiss.tap()
    let restart = app.buttons["game.startNew"]
    XCTAssertTrue(restart.waitForExistence(timeout: 3))
    try capture("replay-interrupt-01-before-restart")
    restart.tap()
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Ready'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    wait(4.7)
    XCTAssertFalse(restart.exists)
    XCTAssertFalse(dismiss.exists)
    XCTAssertFalse(app.buttons["Dig"].exists)
    try capture("replay-interrupt-02-ready")
  }

  func testWinResultSurvivesBackgroundingBeforePresentation() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "near_win"
    app.launchEnvironment["MINESWEEPER_UI_TEST_ANIMATION_SPEED"] = "25"
    app.launch()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
    XCUIDevice.shared.press(.home)
    app.activate()
    try capture("background-win-01-returned")
    let dismiss = app.buttons["game.dismissResult"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["game.startNew"].exists)
    try capture("background-win-02-result")
    dismiss.tap()
    XCTAssertTrue(app.buttons["game.startNew"].waitForExistence(timeout: 3))
    try capture("background-win-03-replay")
  }

  func testCaptureSelectableThemesAndSettings() throws {
    for theme in ["material_you_amoled", "amoled", "blue_amoled", "alpine", "aurum", "monokai"] {
      app.buttons["home.quickThemes"].tap()
      let choice = app.buttons["theme.\(theme)"]
      XCTAssertTrue(choice.waitForExistence(timeout: 3))
      choice.tap()
      XCTAssertTrue(choice.isSelected)
      try capture("polish-themes-\(theme)")
      app.buttons["replica.back"].tap()
      try capture("polish-home-\(theme)")
      app.buttons["home.settings"].tap()
      let dig = app.buttons["settings.primaryAction.dig"]
      let flag = app.buttons["settings.primaryAction.flag"]
      if !flag.isHittable { app.swipeUp() }
      XCTAssertTrue(flag.waitForExistence(timeout: 3))
      flag.tap()
      XCTAssertTrue(flag.isSelected)
      XCTAssertFalse(dig.isSelected)
      try capture("polish-settings-\(theme)-flag")
      dig.tap()
      XCTAssertTrue(dig.isSelected)
      try capture("polish-settings-\(theme)-dig")
      app.buttons["replica.back"].tap()
    }
  }

  func testRemovingLastReadyFlagClearsResume() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launch()
    app.buttons["home.newGame"].tap()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    let mineCount = app.descendants(matching: .any)["game.mines"]
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.5)
    expectation(for: NSPredicate(format: "label == '9'"), evaluatedWith: mineCount)
    waitForExpectations(timeout: 3)
    app.buttons["game.back"].tap()
    let resume = app.buttons["home.resume"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.tap()
    expectation(for: NSPredicate(format: "label == '9'"), evaluatedWith: mineCount)
    waitForExpectations(timeout: 5)
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.5)
    expectation(for: NSPredicate(format: "label == '10'"), evaluatedWith: mineCount)
    waitForExpectations(timeout: 3)
    app.buttons["game.back"].tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: resume)
    waitForExpectations(timeout: 3)
    try capture("edge-last-flag-home")
    app.buttons["home.newGame"].tap()
    XCTAssertFalse(app.alerts["Start a new game?"].exists)
    XCTAssertTrue(board.waitForExistence(timeout: 3))
    XCTAssertEqual(board.value as? String, "Ready")
  }

  func testBackgroundDuringRestorePreservesSavedBoardAndPausedTime() throws {
    app.terminate()
    app.launchEnvironment["MINESWEEPER_UI_TEST_DIFFICULTY"] = "easy"
    app.launchEnvironment["MINESWEEPER_UI_TEST_GAME_STATE"] = "topology"
    app.launch()
    let board = app.otherElements["game.board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    let timer = app.staticTexts["game.timer"]
    let savedSeconds = try XCTUnwrap(Int(timer.label.dropLast()))
    app.buttons["game.back"].tap()
    XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
    wait(0.5)
    app.terminate()
    app.launchEnvironment.removeValue(forKey: "MINESWEEPER_UI_TEST_GAME_STATE")
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "0"
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESTORE_DELAY"] = "4"
    app.launch()
    let resume = app.buttons["home.resume"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    resume.tap()
    XCUIDevice.shared.press(.home)
    wait(12)
    app.activate()
    let playing = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Playing'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
    let resumedSeconds = try XCTUnwrap(Int(timer.label.dropLast()))
    XCTAssertLessThanOrEqual(
      resumedSeconds - savedSeconds, 6, "Background time must not count during restoration")
    XCTAssertEqual(app.descendants(matching: .any)["game.mines"].label, "0")
    try capture("edge-background-restore-playing")
    app.buttons["game.back"].tap()
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
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
    restart.tap()
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Ready'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
      .press(forDuration: 0.05,
             thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)))
    board.pinch(withScale: 1.5, velocity: 2)
    try capture("edge-restart-gesture-attempt")
    wait(5)
    XCTAssertEqual(board.value as? String, "Ready")
    XCTAssertFalse(restart.exists)
    try capture("edge-restart-gesture-settled")
    board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let playing = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == 'Playing' OR value == 'Won'"), object: board)
    XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
  }

}
