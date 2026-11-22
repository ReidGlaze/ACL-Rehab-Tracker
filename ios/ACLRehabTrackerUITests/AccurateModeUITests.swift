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

    /// hip, knee, ankle (x,y each, 0...1 from the top left) from `accuracy/knee_pose_run.sh` on seated.jpg.
    private static let seatedKeypoints = "0.4031,0.4318,0.5603,0.4702,0.5479,0.6936"

    // MARK: - Helpers

    private func launch(mode: String?, photo: String? = nil, extra: [String] = []) throws {
        var args = ["-onboardingComplete", "YES", "-aiAnalysisConsented", "YES"]
        // A launch argument pins the mode for the whole run (it overrides what the chooser saves),
        // so tests that switch modes pass nil, which starts from "nothing saved" like a new install.
        if let mode { args += ["-measureMode", mode] } else { args += ["-resetMeasureMode", "YES"] }
        if let photo {
            guard let photoDir else { throw XCTSkip("Set TEST_RUNNER_PHOTO_DIR to run photo tests.") }
            let path = "\(photoDir)/\(photo)"
            guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Missing test photo \(path)") }
            args += ["-testPhoto", path]
            // Apple's body pose request does not run in the simulator, so for the seated photo the
            // app is given the points the same estimator finds for it on a Mac (it reads 84 there).
            if photo == "seated.jpg" { args += ["-testKeypoints", Self.seatedKeypoints] }
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
        try launch(mode: nil)

        let row = app.buttons["measureMode.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Standard photo"), "Standard photo is what the row shows by default")
        XCTAssertTrue(app.staticTexts["measure.instruction"].label.contains("capture from the side"),
                      "The original instruction text is unchanged in Standard")
        XCTAssertFalse(app.buttons["measure.poseGuide"].exists, "Standard photo has no pose guide button")
        XCTAssertFalse(app.buttons["measure.selfTimer"].exists, "Standard photo has no self-timer")
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

        // The first switch to Accurate mode shows how to pose, once.
        XCTAssertTrue(app.buttons["poseGuide.done"].waitForExistence(timeout: 5))
        shot("05a-pose-guide-first-time")
        app.swipeUp()
        app.buttons["poseGuide.done"].tap()

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

    // MARK: - Pose guide and self-timer

    @MainActor
    func testPoseGuideShowsBothMovementsForTheSavedLeg() throws {
        try launch(mode: "accurate", extra: ["-testInjuredKnee", "left"])

        let guide = app.buttons["measure.poseGuide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["poseGuide.done"].exists, "The guide only opens by itself the first time the mode is chosen")
        guide.tap()

        XCTAssertTrue(app.buttons["poseGuide.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["poseGuide.extension"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["poseGuide.flexion"].exists)
        shot("12-pose-guide-extension")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Your left leg nearest the camera"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Phone propped at knee height"].exists)
        shot("13-pose-guide-rules")
        app.buttons["poseGuide.done"].tap()

        // Flexion puts the flexion drawing first.
        app.buttons["Flexion"].tap()
        guide.tap()
        XCTAssertTrue(app.buttons["poseGuide.done"].waitForExistence(timeout: 5))
        shot("14-pose-guide-flexion")
        app.swipeUp()
        app.buttons["poseGuide.done"].tap()
    }

    @MainActor
    func testSelfTimerCountsDownAndCanBeCancelled() throws {
        try launch(mode: "accurate", extra: ["-resetSelfTimer", "YES"])

        let timer = app.buttons["measure.selfTimer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertEqual(timer.label, "Self-timer off")
        timer.tap()
        XCTAssertEqual(timer.label, "Self-timer 5 seconds")
        timer.tap()
        XCTAssertEqual(timer.label, "Self-timer 10 seconds")
        shot("15-self-timer-10s")

        let capture = app.buttons["measure.capture"]
        capture.tap()
        let count = app.staticTexts["measure.countdown"]
        XCTAssertTrue(count.waitForExistence(timeout: 2), "The count is on screen")
        let first = Int(count.label) ?? 0
        XCTAssertTrue((9...10).contains(first), "Starts at 10, got \(count.label)")
        shot("16-self-timer-counting")
        sleep(3)
        XCTAssertLessThan(Int(count.label) ?? 99, first, "The count goes down")

        capture.tap()
        XCTAssertFalse(count.waitForExistence(timeout: 2), "Tapping the button again cancels")
        XCTAssertTrue(timer.exists)

        timer.tap()
        XCTAssertEqual(timer.label, "Self-timer off")
    }

    // MARK: - Measuring

    @MainActor
    func testWrongSideFacingTheCameraShowsANote() throws {
        // The seated photo shows the right side of the body.
        try launch(mode: "accurate", photo: "seated.jpg", extra: ["-testInjuredKnee", "left"])
        XCTAssertNotNil(angle())
        let note = app.staticTexts["measure.accurateNote"].label
        XCTAssertTrue(note.contains("right side is facing the camera"), note)
        XCTAssertTrue(note.contains("left knee"), note)
        shot("17-accurate-wrong-side-note")
    }

    @MainActor
    func testUnknownSideShowsASofterNoteAndMatchingSideShowsNone() throws {
        try launch(mode: "accurate", photo: "seated.jpg", extra: ["-testInjuredKnee", "left", "-testFacing", "unknown"])
        XCTAssertNotNil(angle())
        XCTAssertTrue(app.staticTexts["measure.accurateNote"].label.contains("Couldn't tell which side"))
        app.terminate()

        try launch(mode: "accurate", photo: "seated.jpg", extra: ["-testInjuredKnee", "right"])
        XCTAssertNotNil(angle())
        XCTAssertTrue(app.staticTexts["measure.accurateNote"].label.hasPrefix("Measured on your phone"))
    }

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
    func testNetwork1_StandardFlowStillMeasuresAndSavesTheOriginalWay() throws {
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
    func testNetwork2_AccurateSaveAppearsInHistoryNextToOlderMeasurements() throws {
        guard networkTestsEnabled else { throw XCTSkip("Set TEST_RUNNER_ACL_NETWORK=1 to save a measurement.") }
        try launch(mode: "accurate", photo: "seated.jpg")

        XCTAssertNotNil(angle())
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Measurement saved!"].waitForExistence(timeout: 30))

        app.tabBars.buttons["History"].tap()
        let tagged = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Accurate mode'")).firstMatch
        XCTAssertTrue(tagged.waitForExistence(timeout: 20), "The Accurate-mode measurement is labelled in History")
        // Standard-photo saves have no `method` field, exactly like every measurement saved before
        // Accurate mode existed. They must still be listed, without the label.
        let untagged = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'history.rowTime' AND NOT (label CONTAINS 'Accurate mode')")).firstMatch
        XCTAssertTrue(untagged.exists, "Measurements without a method field still show in History")
        shot("11-history")
    }
}
