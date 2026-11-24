package com.twintipsolutions.aclrehabtracker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.os.ParcelFileDescriptor
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.doubleClick
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pinch
import androidx.compose.ui.test.swipe
import androidx.compose.ui.geometry.Offset
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import com.google.firebase.analytics.FirebaseAnalytics
import com.twintipsolutions.aclrehabtracker.data.model.KneeSide
import com.twintipsolutions.aclrehabtracker.data.model.MeasureMode
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.ui.screens.history.MeasurementRow
import com.twintipsolutions.aclrehabtracker.ui.screens.measure.MeasureScreen
import com.twintipsolutions.aclrehabtracker.ui.screens.measure.MeasureTestHooks
import com.twintipsolutions.aclrehabtracker.ui.theme.ACLRehabTrackerTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

/**
 * Drives the Measure tab on an emulator, like iOS `AccurateModeUITests`. Pose detection is the real
 * ML Kit model (it runs on the emulator), on photos pushed to the device first:
 *
 *   adb push seated.jpg closeup.jpg /data/local/tmp/acl-test/
 *
 * Photos of people are not kept in git. Tests that need one are skipped when it is missing.
 * Nothing here signs in, saves a measurement or calls a server.
 */
@RunWith(AndroidJUnit4::class)
class WholeBodyModeTest {
    @get:Rule val permission: GrantPermissionRule = GrantPermissionRule.grant(Manifest.permission.CAMERA)
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    /**
     * Whether a camera is really there. An emulator started with no cameras still advertises the
     * camera feature, so the list of actual cameras is checked as well.
     */
    private val hasCamera: Boolean get() =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) &&
            runCatching { (context.getSystemService(Context.CAMERA_SERVICE) as CameraManager).cameraIdList.isNotEmpty() }.getOrDefault(false)

    @Before fun setUp() {
        FirebaseAnalytics.getInstance(context).setAnalyticsCollectionEnabled(false)
        context.getSharedPreferences(MeasureMode.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    /** Copies a pushed test photo into the app's cache (the app can't read /data/local/tmp itself). */
    private fun photo(name: String): String {
        val out = File(context.cacheDir, "test-$name")
        val fd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cat /data/local/tmp/acl-test/$name")
        ParcelFileDescriptor.AutoCloseInputStream(fd).use { input -> FileOutputStream(out).use { input.copyTo(it) } }
        assumeTrue("Push $name to /data/local/tmp/acl-test/ to run this test", out.length() > 1000)
        return out.absolutePath
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        val dir = File(context.getExternalFilesDir(null), "shots").apply { mkdirs() }
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun launch(mode: MeasureMode? = null, photo: String? = null, knee: KneeSide? = null) {
        rule.setContent { ACLRehabTrackerTheme { MeasureScreen(MeasureTestHooks(photoPath = photo, injuredKnee = knee, mode = mode)) } }
    }

    private fun text(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text } ?: ""

    private fun description(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString("") ?: ""

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    /** Taps the library button (the test photo stands in for the picker) and waits for the result. */
    private fun measure(): Int {
        rule.onNodeWithTag("measure.library").performClick()
        rule.waitUntil(30_000) { exists("measure.angle") || exists("retake.message") }
        assertTrue("An angle should appear, measured on the device", exists("measure.angle"))
        return text("measure.angle").filter(Char::isDigit).toInt()
    }

    // --- Choosing a mode ---

    @Test fun standardPhotoIsTheDefaultAndTheChooserSwitchesBothWays() {
        launch()
        assertEquals("Measuring method: Standard photo", description("measureMode.row"))
        assertEquals("Straighten your leg as much as possible and capture from the side", text("measure.instruction"))
        assertTrue("Standard photo has no pose button", !exists("measure.poseGuide"))
        assertTrue("Standard photo has no self-timer", !exists("measure.selfTimer"))
        shot("01-measure-standard")

        rule.onNodeWithTag("measureMode.row").performClick()
        rule.onNodeWithText("How do you want to measure?").assertIsDisplayed()
        rule.onNodeWithText("HOW WHOLE-BODY MODE WORKS").assertExists()
        shot("02-chooser")
        rule.onNodeWithTag("measureMode.accurate").performClick()
        assertTrue(description("measureMode.accurate").startsWith("Whole-body mode, beta"))
        shot("03-chooser-whole-body-selected")
        rule.onNodeWithTag("measureMode.done").performScrollTo()
        shot("04-chooser-explainer")
        rule.onNodeWithTag("measureMode.done").performClick()

        // The first switch to Whole-body mode shows how to pose, once.
        rule.onNodeWithTag("poseGuide.done").assertExists()
        shot("05-pose-guide-first-time")
        rule.onNodeWithTag("poseGuide.done").performScrollTo().performClick()

        assertEquals("Measuring method: Whole-body mode, beta", description("measureMode.row"))
        assertTrue(text("measure.instruction").contains("whole body"))
        if (hasCamera) {
            rule.onNodeWithTag("measure.poseGuide").assertExists()
            rule.onNodeWithTag("measure.selfTimer").assertExists()
        }
        shot("06-measure-whole-body")

        // And back again, so the choice is never a one-way door. No second pose guide.
        rule.onNodeWithTag("measureMode.row").performClick()
        rule.onNodeWithTag("measureMode.standard").performClick()
        rule.onNodeWithTag("measureMode.done").performScrollTo().performClick()
        assertEquals("Measuring method: Standard photo", description("measureMode.row"))
        assertTrue(!exists("poseGuide.done"))
    }

    // --- Measuring ---

    @Test fun wholeBodyModeMeasuresOnTheDeviceAndDraggingADotChangesTheAngle() {
        launch(MeasureMode.ACCURATE, photo("seated.jpg"), KneeSide.RIGHT)
        val measured = measure()
        assertTrue("Seated at about a right angle, got $measured", measured in 65..105)
        assertTrue(text("measure.accurateNote").startsWith("Measured on your phone"))
        rule.onNodeWithText("Save").assertExists()
        shot("07-whole-body-result")

        rule.onNodeWithTag("keypoint.ankle").performTouchInput { swipe(center, center + Offset(120f, 0f), 300) }
        rule.waitForIdle()
        assertNotEquals("Moving the ankle dot should change the angle", measured, text("measure.angle").filter(Char::isDigit).toInt())
        shot("08-whole-body-result-adjusted")

        rule.onNodeWithText("Retake").performClick()
        rule.onNodeWithTag("measureMode.row").assertExists()
    }

    @Test fun photoZoomsForPlacingDotsWithoutChangingTheAngle() {
        launch(MeasureMode.ACCURATE, photo("seated.jpg"), KneeSide.RIGHT)
        val measured = measure()
        fun angle() = text("measure.angle").filter(Char::isDigit).toInt()
        fun zoomState() = rule.onNodeWithTag("keypoint.photo").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription) ?: ""
        assertEquals("Not zoomed", zoomState())
        assertTrue(!exists("keypoint.resetZoom"))

        // Double tap zooms in around the tap. The dots are stored on the image, so the angle stays put.
        val knee = rule.onNodeWithTag("keypoint.knee").fetchSemanticsNode().boundsInRoot.center
        val photo = rule.onNodeWithTag("keypoint.photo").fetchSemanticsNode().boundsInRoot
        val near = Offset(knee.x - photo.left - 150f, knee.y - photo.top + 120f)
        rule.onNodeWithTag("keypoint.photo").performTouchInput { doubleClick(near) }
        rule.waitUntil(3_000) { exists("keypoint.resetZoom") }
        assertTrue(zoomState().startsWith("Zoomed in 2.5"))
        assertEquals("Zooming must not change the measured angle", measured, angle())
        shot("09-zoomed-in")

        // Dots can still be dragged while zoomed, and the number follows.
        rule.onNodeWithTag("keypoint.knee").performTouchInput { swipe(center, center + Offset(0f, -140f), 300) }
        rule.waitForIdle()
        val moved = angle()
        assertNotEquals("Moving a dot while zoomed should change the angle", measured, moved)
        shot("10-zoomed-dot-moved")

        // One finger on the photo pans it: the dots move on screen with the photo, the angle doesn't.
        val before = rule.onNodeWithTag("keypoint.knee").fetchSemanticsNode().boundsInRoot.center
        rule.onNodeWithTag("keypoint.photo").performTouchInput { swipe(near, near + Offset(-90f, -60f), 300) }
        rule.waitForIdle()
        val after = rule.onNodeWithTag("keypoint.knee").fetchSemanticsNode().boundsInRoot.center
        assertEquals("Panning moves the photo and its dots", before.x - 90f, after.x, 25f)
        assertEquals("Panning must not change the angle", moved, angle())

        // Reset keeps the adjusted dots where they were put on the photo.
        rule.onNodeWithTag("keypoint.resetZoom").performClick()
        rule.waitUntil(3_000) { !exists("keypoint.resetZoom") }
        assertEquals("Resetting the zoom must not change the angle", moved, angle())

        // Pinching zooms in, and pinching back out returns to the whole photo.
        rule.onNodeWithTag("keypoint.photo").performTouchInput {
            pinch(near + Offset(-20f, 0f), near + Offset(-160f, 0f), near + Offset(20f, 0f), near + Offset(160f, 0f), 400)
        }
        rule.waitUntil(3_000) { exists("keypoint.resetZoom") }
        assertEquals("Pinching must not change the angle", moved, angle())
        rule.onNodeWithTag("keypoint.photo").performTouchInput {
            pinch(center + Offset(-300f, 0f), center + Offset(-15f, 0f), center + Offset(300f, 0f), center + Offset(15f, 0f), 400)
        }
        rule.waitUntil(3_000) { !exists("keypoint.resetZoom") }
        assertEquals("Zooming out must not change the angle", moved, angle())
    }

    @Test fun aKneeCloseUpAsksForARetake() {
        launch(MeasureMode.ACCURATE, photo("closeup.jpg"))
        rule.onNodeWithTag("measure.library").performClick()
        rule.waitUntil(30_000) { exists("measure.angle") || exists("retake.message") }
        rule.onNodeWithTag("retake.message").assertExists()
        rule.onNodeWithTag("retake.useStandard").assertExists()
        shot("11-closeup-retake")
        rule.onNodeWithTag("retake.retake").performClick()
        rule.onNodeWithTag("measureMode.row").assertExists()
    }

    @Test fun wrongSideFacingTheCameraShowsANote() {
        // The seated photo shows the person's right side; the profile says left knee.
        launch(MeasureMode.ACCURATE, photo("seated.jpg"), KneeSide.LEFT)
        measure()
        val note = text("measure.accurateNote")
        assertTrue(note, note.startsWith("Your right side is facing the camera, but your profile says left knee."))
        shot("12-wrong-side-note")
    }

    // --- Pose guide and self-timer ---

    @Test fun poseGuideShowsBothMovementsForTheSavedLeg() {
        assumeTrue("The pose button sits on the camera preview", hasCamera)
        launch(MeasureMode.ACCURATE, knee = KneeSide.LEFT)
        rule.onNodeWithTag("measure.poseGuide").performClick()
        rule.onNodeWithTag("poseGuide.extension").assertExists()
        rule.onNodeWithTag("poseGuide.flexion").assertExists()
        rule.onNodeWithText("•  Your left leg nearest the camera").assertExists()
        shot("13-pose-guide")
        rule.onNodeWithTag("poseGuide.done").performScrollTo().performClick()
        assertTrue(!exists("poseGuide.done"))
    }

    @Test fun selfTimerCountsDownAndCanBeCancelled() {
        assumeTrue("The self-timer needs a camera", hasCamera)
        launch(MeasureMode.ACCURATE)
        assertEquals("Self-timer off", description("measure.selfTimer"))
        rule.onNodeWithTag("measure.selfTimer").performClick()
        assertEquals("Self-timer 5 seconds", description("measure.selfTimer"))
        rule.onNodeWithTag("measure.selfTimer").performClick()
        assertEquals("Self-timer 10 seconds", description("measure.selfTimer"))
        shot("14-self-timer-10s")

        rule.waitUntil(15_000) { rule.onNodeWithTag("measure.capture").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Disabled) == null }
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("measure.capture").performClick()
        rule.mainClock.advanceTimeBy(500)
        assertEquals("10", text("measure.countdown"))
        rule.mainClock.advanceTimeBy(2_000)
        assertEquals("8", text("measure.countdown"))
        assertEquals("Cancel self-timer", description("measure.capture"))
        shot("15-self-timer-counting")
        rule.onNodeWithTag("measure.capture").performClick()
        rule.mainClock.advanceTimeBy(300)
        assertTrue("Tapping the button again cancels the count", !exists("measure.countdown"))
        rule.mainClock.autoAdvance = true
        rule.onNodeWithTag("measure.selfTimer").performClick()
        assertEquals("Self-timer off", description("measure.selfTimer"))
    }

    // --- A device with no camera (this crashed Shoulder Rehab once) ---

    @Test fun aDeviceWithoutACameraShowsAMessageAndStillMeasuresFromTheLibrary() {
        assumeTrue("Run on an emulator started with -camera-back none -camera-front none", !hasCamera)
        launch(MeasureMode.ACCURATE, photo("seated.jpg"), KneeSide.RIGHT)
        rule.waitUntil(15_000) { exists("measure.noCamera") }
        rule.onNodeWithText("Camera not available").assertIsDisplayed()
        shot("16-no-camera")
        // The shutter does nothing, and the library still works.
        rule.onNodeWithTag("measure.capture").performTouchInput { click() }
        assertTrue(measure() in 65..105)
    }

    @Test fun standardPhotoOnADeviceWithoutACameraDoesNotCrash() {
        assumeTrue(!hasCamera)
        launch()
        rule.waitUntil(15_000) { exists("measure.noCamera") }
        assertEquals("Measuring method: Standard photo", description("measureMode.row"))
    }

    // --- History ---

    @Test fun historyLabelsWholeBodyRowsAndLeavesOlderRowsAlone() {
        rule.setContent {
            ACLRehabTrackerTheme {
                androidx.compose.foundation.layout.Column {
                    MeasurementRow(Measurement(id = "new", type = MeasurementType.FLEXION, angle = 84, method = Measurement.METHOD_ON_DEVICE)) {}
                    // No method field: exactly like every measurement saved before this mode existed.
                    MeasurementRow(Measurement(id = "old", type = MeasurementType.EXTENSION, angle = 3)) {}
                }
            }
        }
        // Each row is one tappable element, so its texts are looked up in the unmerged tree.
        val methods = rule.onAllNodesWithTag("history.rowMethod", useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals(1, methods.size)
        assertEquals(2, rule.onAllNodesWithTag("history.rowTime", useUnmergedTree = true).fetchSemanticsNodes().size)
        assertEquals("Whole-body mode", methods[0].config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text })
        rule.onNodeWithText("Beta", useUnmergedTree = true).assertExists()
        shot("17-history-rows")
    }
}
