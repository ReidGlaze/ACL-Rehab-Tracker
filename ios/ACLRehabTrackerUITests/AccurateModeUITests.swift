import XCTest

/// Accurate mode, driven end to end. The simulator has no camera, so photos are fed in with the
/// DEBUG-only `-testPhoto` launch argument.
///
/// Photos are not in the repo (they are pictures of people). Point the tests at a folder with
/// `TEST_RUNNER_PHOTO_DIR=/path` containing:
///   seated.jpg    whole body, side-on, sitting with the knee at about a right angle
///   closeup.jpg   only a knee and part of the leg
/// Screenshots are written to `TEST_RUNNER_SHOTS_DIR` (default /tmp/acl-accurate-shots).
///
/// Tests that call the production AI function or save a measurement only run with
/// `TEST_RUNNER_ACL_NETWORK=1`.
final class AccurateModeUITests: XCTestCase {
    private var app: XCUIApplication!

    private var photoDir: String? { ProcessInfo.processInfo.environment["PHOTO_DIR"] }
    private var shotsDir: String { ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? "/tmp/acl-accurate-shots" }
    private var networkTestsEnabled: Bool { ProcessInfo.processInfo.environment["ACL_NETWORK"] == "1" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        try FileManager.default.createDirectory(atPath: shotsDir, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    private func launch(mode: String?, photo: String? = nil, extra: [String] = []) throws {
        var args = ["-onboardingComplete", "YES", "-aiAnalysisConsented", "YES"]
        if let mode { args += ["-measureMode", mode] }
        if let photo {
            guard let photoDir else { throw XCTSkip("Set TEST_RUNNER_PHOTO_DIR to run photo tests.") }
            let path = "\(photoDir)/\(photo)"
            guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Missing test photo \(path)") }
            args += ["-testPhoto", path]
        }
        app.launchArguments = args + extra
        app.launch()
        let measureTab = app.tabBars.buttons["Measure"]
        XCTAssertTrue(measureTab.waitForExistence(timeout: 20), "Main tabs should appear")
        measureTab.tap()
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        try? image.pngRepresentation.write(to: URL(fileURLWithPath: "\(shotsDir)/\(name).png"))
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func angle() -> Int? {
        let label = app.staticTexts["measure.angle"]
        guard label.waitForExistence(timeout: 30) else { return nil }
        return Int(label.label.filter(\.isNumber))
    }

    // MARK: - Choosing a mode

    @MainActor
    func testChooserExplainsAccurateModeAndSwitchesBothWays() throws {
        try launch(mode: "standard")

        let row = app.buttons["measureMode.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Standard photo"), "Standard photo is what the row shows by default")
        XCTAssertTrue(app.staticTexts["measure.instruction"].label.contains("capture from the side"),
                      "The original instruction text is unchanged in Standard")
        shot("01-measure-standard")

        row.tap()
        XCTAssertTrue(app.staticTexts["How do you want to measure?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HOW ACCURATE MODE WORKS"].exists)
        shot("02-chooser")

        app.buttons["measureMode.accurate"].tap()
        shot("03-chooser-accurate-selected")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["3. Your phone measures the angle"].waitForExistence(timeout: 3))
        shot("04-chooser-explainer")
        app.buttons["measureMode.done"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Accurate mode"))
        XCTAssertTrue(app.staticTexts["measure.instruction"].label.contains("whole body"))
        shot("05-measure-accurate")

        // And back again, so the choice is never a one-way door.
        row.tap()
        app.buttons["measureMode.standard"].tap()
        app.swipeUp()
        app.buttons["measureMode.done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Standard photo"))
    }

    // MARK: - Measuring

    @MainActor
    func testAccurateModeMeasuresAWholeBodyPhotoOnDevice() throws {
        try launch(mode: "accurate", photo: "seated.jpg")

        let measured = try XCTUnwrap(angle(), "An angle should appear without any server measurement")
        XCTAssertTrue((70...100).contains(measured), "Seated at about a right angle, got \(measured)")
        XCTAssertTrue(app.staticTexts["measure.accurateNote"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        shot("06-accurate-result")

        // Dragging a dot changes the number, because the number is computed from the dots.
        let ankle = app.otherElements["keypoint.ankle"].firstMatch
        if ankle.waitForExistence(timeout: 3) {
            let start = ankle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 60, dy: 0)))
            let moved = try XCTUnwrap(angle())
            XCTAssertNotEqual(moved, measured, "Moving the ankle dot should change the angle")
            shot("07-accurate-result-adjusted")
        }

        app.buttons["Retake"].tap()
        XCTAssertTrue(app.buttons["measureMode.row"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccurateModeAsksForARetakeOnACloseUp() throws {
        try launch(mode: "accurate", photo: "closeup.jpg")

        XCTAssertTrue(app.staticTexts["Couldn't measure this photo"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Retake"].exists)
        XCTAssertTrue(app.buttons["retake.useStandard"].exists, "A close-up can still be measured the original way")
        shot("08-accurate-closeup-retake")

        app.buttons["Retake"].tap()
        XCTAssertTrue(app.buttons["measureMode.row"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailedPhotoCheckOffersRetakeOrUseAnyway() throws {
        try launch(mode: "accurate", photo: "seated.jpg",
                   extra: ["-forceCheckMessage", "Turn so the camera sees the side of your leg."])

        XCTAssertTrue(app.staticTexts["Let's retake that"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["retake.message"].label, "Turn so the camera sees the side of your leg.")
        shot("09-accurate-check-failed")

        app.buttons["retake.useAnyway"].tap()
        XCTAssertNotNil(angle(), "Use anyway shows the on-device measurement")
    }

    // MARK: - Network (production AI function, saves under the simulator's own anonymous user)

    @MainActor
    func testStandardFlowStillMeasuresAndSavesTheOriginalWay() throws {
        guard networkTestsEnabled else { throw XCTSkip("Set TEST_RUNNER_ACL_NETWORK=1 to call the AI function.") }
        try launch(mode: nil, photo: "closeup.jpg")

        let label = app.staticTexts["measure.angle"]
        XCTAssertTrue(label.waitForExistence(timeout: 240), "Standard photo should return an AI angle")
        XCTAssertFalse(app.staticTexts["measure.accurateNote"].exists, "No Accurate-mode text on a Standard result")
        shot("10-standard-result")

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Measurement saved!"].waitForExistence(timeout: 30))
    }

    @MainActor
    func testAccurateSaveAppearsInHistoryNextToOlderMeasurements() throws {
        guard networkTestsEnabled else { throw XCTSkip("Set TEST_RUNNER_ACL_NETWORK=1 to save a measurement.") }
        try launch(mode: "accurate", photo: "seated.jpg")

        XCTAssertNotNil(angle())
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Measurement saved!"].waitForExistence(timeout: 30))

        app.tabBars.buttons["History"].tap()
        let tagged = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Accurate mode'")).firstMatch
        XCTAssertTrue(tagged.waitForExistence(timeout: 20), "The Accurate-mode measurement is labelled in History")
        shot("11-history")
    }
}
