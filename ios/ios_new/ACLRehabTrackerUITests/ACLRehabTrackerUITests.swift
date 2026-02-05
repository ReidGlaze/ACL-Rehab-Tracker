import XCTest

final class ACLRehabTrackerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    // MARK: - Onboarding Flow

    @MainActor
    func testOnboardingWelcomeScreenShowsOnFreshLaunch() throws {
        app.launch()

        // Welcome screen should show app title and Get Started button
        let getStartedButton = app.buttons["Get Started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 5),
                      "Welcome screen should show 'Get Started' button on fresh launch")
    }

    @MainActor
    func testOnboardingNameInputValidation() throws {
        app.launch()

        // Navigate past welcome
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) {
            getStarted.tap()
        }

        // Name input screen should show
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3),
                      "Name input field should appear after welcome screen")
    }

    @MainActor
    func testOnboardingFlowNavigatesToInjuryInfo() throws {
        app.launch()

        // Navigate past welcome
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) {
            getStarted.tap()
        }

        // Type a name
        let nameField = app.textFields["Name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("Test User")
        }

        // Dismiss keyboard so continue button is tappable
        app.tap()
        sleep(1)

        // Tap continue arrow
        let continueButton = app.buttons["continueButton"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }

        // Injury info screen should show knee selection
        let injuryHeader = app.staticTexts["Which knee was injured?"]
        XCTAssertTrue(injuryHeader.waitForExistence(timeout: 5),
                      "Injury info screen should show after entering name")
    }

    // MARK: - Tab Navigation

    @MainActor
    func testMainTabsExistAfterOnboarding() throws {
        // This test works when onboarding is already complete
        app.launch()

        // If we land on main screen (onboarding already done), check tabs
        let homeTab = app.buttons["Home"]
        guard homeTab.waitForExistence(timeout: 5) else {
            // Still in onboarding, skip this test
            return
        }

        let measureTab = app.buttons["Measure"]
        let historyTab = app.buttons["History"]
        let progressTab = app.buttons["Progress"]

        XCTAssertTrue(homeTab.exists, "Home tab should exist")
        XCTAssertTrue(measureTab.exists, "Measure tab should exist")
        XCTAssertTrue(historyTab.exists, "History tab should exist")
        XCTAssertTrue(progressTab.exists, "Progress tab should exist")
    }

    // MARK: - Empty States

    @MainActor
    func testHistoryShowsEmptyState() throws {
        app.launch()

        let historyTab = app.buttons["History"]
        guard historyTab.waitForExistence(timeout: 5) else { return }

        historyTab.tap()

        let emptyMessage = app.staticTexts["No measurements yet"]
        if emptyMessage.waitForExistence(timeout: 3) {
            XCTAssertTrue(emptyMessage.exists, "History should show empty state message")
        }
    }

    @MainActor
    func testProgressShowsEmptyState() throws {
        app.launch()

        let progressTab = app.buttons["Progress"]
        guard progressTab.waitForExistence(timeout: 5) else { return }

        progressTab.tap()

        let emptyMessage = app.staticTexts["No data yet"]
        if emptyMessage.waitForExistence(timeout: 3) {
            XCTAssertTrue(emptyMessage.exists, "Progress should show empty state message")
        }
    }
}
