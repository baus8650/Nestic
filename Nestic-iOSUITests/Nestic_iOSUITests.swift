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

    @MainActor func testFirstSignedInLaunchShowsTutorialAndRemembersViewingLocally() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset-demo", "--reset-tutorial"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Getting started"].waitForExistence(timeout: 10))
        app.buttons["tutorial.skip"].tap()
        app.terminate()

        // Keep automatic presentation enabled to prove persistence prevents it.
        app.launchArguments = ["--demo", "--show-tutorial-in-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["home.switchNest"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Getting started"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Your nest"].tap()
        let guide = app.buttons["settings.tutorial"]
        reveal(guide, in: app)
        guide.tap()
        XCTAssertTrue(app.navigationBars["Getting started"].waitForExistence(timeout: 5))
        app.buttons["tutorial.skip"].tap()
    }

    @MainActor func testTutorialExplainsFreeHealthUpdatesAndProFeaturesAndCanReopen() {
        let app = launch()
        app.tabBars.buttons["Your nest"].tap()
        let guide = app.buttons["settings.tutorial"]
        reveal(guide, in: app)
        guide.tap()
        XCTAssertTrue(app.navigationBars["Getting started"].waitForExistence(timeout: 5))
        let topics = app.buttons["Jump to a topic"]
        topics.tap()
        app.buttons["Follow health events over time"].tap()
        XCTAssertTrue(app.staticTexts["Free"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "follow-up notes and progress photos")).firstMatch.exists)
        topics.tap()
        app.buttons["Group habits into routines"].tap()
        XCTAssertTrue(app.staticTexts["Nestic Pro"].waitForExistence(timeout: 3))
        topics.tap()
        app.buttons["Share on your terms"].tap()
        XCTAssertTrue(app.staticTexts["Free members · Pro caregiver links"].waitForExistence(timeout: 3))
        app.buttons["tutorial.skip"].tap()
        XCTAssertFalse(app.navigationBars["Getting started"].exists)
        reveal(guide, in: app)
        guide.tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 9"].waitForExistence(timeout: 3))
        app.buttons["tutorial.skip"].tap()
    }

    @MainActor func testLongPressShowsTrackerMenuAndLogsSelection() {
        let app = launch()
        let subject = app.buttons["subject.open.Milo"]
        reveal(subject, in: app)
        subject.press(forDuration: 0.8)
        let pee = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Daily check-in")).firstMatch
        XCTAssertTrue(pee.waitForExistence(timeout: 5), app.debugDescription)
        pee.tap()
        XCTAssertTrue(app.buttons["home.switchNest"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Milo"].exists)
        app.tabBars.buttons["Activity"].tap()
        let loggedEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Milo · Daily check-in")).firstMatch
        XCTAssertTrue(loggedEntry.waitForExistence(timeout: 5))
        app.terminate()
        let reopened = launch(reset: false)
        reopened.tabBars.buttons["Activity"].tap()
        let persisted = reopened.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Milo · Daily check-in")).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 5))
    }

    @MainActor func testHomeTabReturnsToRoot() {
        let app = launch()
        let subject = app.buttons["subject.open.Milo"]
        reveal(subject, in: app)
        subject.tap()
        XCTAssertTrue(app.navigationBars["Milo"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Home"].tap()

        XCTAssertTrue(app.buttons["home.switchNest"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Milo"].exists)
    }

    @MainActor func testRecordInsightsSwitchingPerformance() {
        let app = launch()
        let subject = app.buttons["subject.open.Milo"]
        reveal(subject, in: app)
        subject.tap()
        let picker = app.segmentedControls["subject.modePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let insights = picker.buttons["Insights"]
        let record = picker.buttons["Record"]
        measure {
            insights.tap()
            XCTAssertTrue(app.staticTexts["At a glance"].waitForExistence(timeout: 3))
            XCTAssertTrue(insights.isSelected)
            record.tap()
            XCTAssertTrue(record.isSelected)
        }
    }

    @MainActor func testIPadShowMenuRestoresHiddenSidebarOnHome() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        guard min(app.frame.width, app.frame.height) > 600 else {
            throw XCTSkip("This test exercises the regular-width iPad layout.")
        }
        XCTAssertFalse(app.buttons["ipad.showMenu"].exists)
        let toggle = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(toggle.isHittable)
        let sidebarItem = app.descendants(matching: .any).matching(identifier: "ipad.destination.settings").firstMatch
        XCTAssertTrue(sidebarItem.isHittable)
        toggle.tap()
        XCTAssertFalse(sidebarItem.isHittable)
        app.swipeUp()
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarItem.isHittable)
        XCTAssertTrue(toggle.isHittable)
    }

    @MainActor func testContactSupportOpensFeedbackWithSupportSelected() {
        let app = launch()
        app.tabBars.buttons["Your nest"].tap()
        let support = app.buttons["settings.contactSupport"]
        reveal(support, in: app)
        support.tap()
        XCTAssertTrue(app.navigationBars["Send feedback"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["Subject"].exists)
        let category = app.buttons["feedback.category"]
        XCTAssertTrue(category.exists, app.debugDescription)
        XCTAssertTrue(category.label.contains("Support"), app.debugDescription)
        XCTAssertFalse(app.buttons["Send"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Feedback"].waitForExistence(timeout: 5))
    }

    @MainActor func testSignupRequiresTermsAgreement() {
        let app = XCUIApplication()
        app.launch()
        let create = app.buttons["welcome.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let agreement = app.switches["auth.acceptTerms"]
        XCTAssertTrue(agreement.waitForExistence(timeout: 5))
        XCTAssertEqual(agreement.value as? String, "0")
        XCTAssertTrue(app.links["Read the Terms of Service"].exists, app.debugDescription)
        // Tap the switch itself: its accessibility frame also includes the
        // multiline label, whose center can fall outside the switch hit area.
        agreement.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(agreement.value as? String, "1", app.debugDescription)
        let name = app.textFields["auth.name"]
        reveal(name, in: app); name.tap(); name.typeText("Review Person")
        let email = app.textFields["auth.email"]
        email.tap(); email.typeText("review@example.com")
        let password = app.secureTextFields["auth.password"]
        reveal(password, in: app); password.tap(); password.typeText("test-password")
        let confirmation = app.secureTextFields["auth.confirmPassword"]
        reveal(confirmation, in: app); confirmation.tap(); confirmation.typeText("test-password")
        let submit = app.buttons["auth.submit"]
        reveal(submit, in: app)
        XCTAssertTrue(submit.isEnabled, app.debugDescription)
        for _ in 0..<6 {
            if agreement.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(agreement.isHittable)
        agreement.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        reveal(submit, in: app)
        XCTAssertFalse(submit.isEnabled)
        // Do not submit: this UI test must never create a production account.
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
        trackerName.tap(); trackerName.typeText("Project")
        app.buttons["tracker.save"].tap()
        XCTAssertTrue(app.staticTexts["Project"].waitForExistence(timeout: 5))
    }

    @MainActor func testNewNestIsEmptyAndOriginalNestIsPreserved() {
        let app = launch()
        app.buttons["home.switchNest"].tap()
        let name = app.textFields["nest.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Weekend crew")
        app.buttons["nest.create"].tap()
        XCTAssertTrue(app.staticTexts["Your event history starts here"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["subject.open.Milo"].exists)
        app.buttons["home.switchNest"].tap()
        app.buttons["Our little nest"].tap()
        XCTAssertTrue(app.buttons["subject.open.Milo"].waitForExistence(timeout: 5))
    }
}
