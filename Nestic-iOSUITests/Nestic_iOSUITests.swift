import XCTest

final class Nestic_iOSUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = reset ? ["--demo", "--reset-demo"] : ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["home.switchNest"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor func testQuickLogPersistsAndCanBeDeleted() {
        let app = launch()
        let quickLog = app.buttons["quicklog.Milo.Pee"]
        reveal(quickLog, in: app)
        quickLog.tap()
        let note = app.descendants(matching: .any).matching(identifier: "log.note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("UI test backyard update")
        let save = app.buttons["log.saveToolbar"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["home.switchNest"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["UI test backyard update"].waitForExistence(timeout: 5))
        app.terminate()
        let reopened = launch(reset: false)
        reopened.tabBars.buttons["Activity"].tap()
        let persisted = reopened.staticTexts["UI test backyard update"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 5))
        persisted.tap()
        reopened.buttons["entry.delete"].tap()
        let confirmation = reopened.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Delete update", "entry.delete")).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(reopened.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(reopened.staticTexts["UI test backyard update"].exists)
    }

    @MainActor func testCreateSubjectAndCustomTracker() {
        let app = launch()
        app.buttons["home.addSubject"].tap()
        let name = app.textFields["subject.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Luna")
        app.buttons["subject.save"].tap()
        let subject = app.buttons["subject.open.Luna"]
        XCTAssertTrue(subject.waitForExistence(timeout: 8))
        reveal(subject, in: app); subject.tap()
        let addTracker = app.buttons["subject.addTracker"]
        reveal(addTracker, in: app); addTracker.tap()
        let trackerName = app.textFields["tracker.name"]
        XCTAssertTrue(trackerName.waitForExistence(timeout: 5))
        trackerName.tap(); trackerName.typeText("Training")
        app.buttons["tracker.save"].tap()
        XCTAssertTrue(app.staticTexts["Training"].waitForExistence(timeout: 5))
    }

    @MainActor func testNewNestIsEmptyAndOriginalNestIsPreserved() {
        let app = launch()
        app.buttons["home.switchNest"].tap()
        let name = app.textFields["nest.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Weekend crew")
        app.buttons["nest.create"].tap()
        XCTAssertTrue(app.staticTexts["A little care starts here"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["subject.open.Milo"].exists)
        app.buttons["home.switchNest"].tap()
        app.buttons["Our little nest"].tap()
        XCTAssertTrue(app.buttons["subject.open.Milo"].waitForExistence(timeout: 5))
    }
}
