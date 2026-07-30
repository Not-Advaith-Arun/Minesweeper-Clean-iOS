import XCTest

@MainActor
final class MinesweeperUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["MINESWEEPER_UI_TESTING"] = "1"
    app.launchEnvironment["MINESWEEPER_UI_TEST_RESET"] = "1"
    app.launch()
  }

  func testHomeExposesPrimaryReplicaControls() {
    XCTAssertTrue(app.buttons["home.newGame"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["home.settings"].exists)
    XCTAssertTrue(app.buttons["home.themes"].exists)
    XCTAssertTrue(app.buttons["home.times"].exists)
    XCTAssertTrue(app.buttons["home.about"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["home.difficulty"].exists)
  }

  func testSettingsLongPressDependencyAndReset() {
    app.buttons["home.settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

    let longPress = app.switches["settings.longPress"]
    let actionToggle = app.switches["settings.actionToggle"]
    XCTAssertTrue(longPress.waitForExistence(timeout: 2))
    XCTAssertTrue(actionToggle.exists)

    if longPress.value as? String == "1" {
      longPress.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
    expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: longPress)
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: actionToggle)
    expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: actionToggle)
    waitForExpectations(timeout: 3)
    XCTAssertEqual(actionToggle.value as? String, "1")
    XCTAssertFalse(actionToggle.isEnabled)

    app.buttons["settings.reset"].tap()
    app.alerts["Reset settings?"].buttons["Reset"].tap()
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: longPress)
    waitForExpectations(timeout: 3)
    XCTAssertEqual(longPress.value as? String, "1")
  }

  func testAllMajorDestinationsOpen() {
    app.buttons["home.themes"].tap()
    XCTAssertTrue(app.navigationBars["Themes"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["theme.pink_amoled"].exists)
    app.buttons["theme.pink_amoled"].tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()

    app.buttons["home.times"].tap()
    XCTAssertTrue(app.navigationBars["Top times"].waitForExistence(timeout: 2))
    app.navigationBars.buttons.element(boundBy: 0).tap()

    app.buttons["home.about"].tap()
    XCTAssertTrue(app.buttons["about.done"].waitForExistence(timeout: 2))
    app.buttons["about.done"].tap()
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
