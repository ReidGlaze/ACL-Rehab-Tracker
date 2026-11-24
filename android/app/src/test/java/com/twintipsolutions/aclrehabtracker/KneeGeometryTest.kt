package com.twintipsolutions.aclrehabtracker

import com.twintipsolutions.aclrehabtracker.data.model.MeasureMode
import com.twintipsolutions.aclrehabtracker.data.model.Measurement
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType
import com.twintipsolutions.aclrehabtracker.data.pose.KneeBend
import com.twintipsolutions.aclrehabtracker.data.pose.KneeGeometry
import com.twintipsolutions.aclrehabtracker.data.pose.KneeKeypoints
import com.twintipsolutions.aclrehabtracker.data.pose.KneeLeg
import com.twintipsolutions.aclrehabtracker.data.pose.KneePoseEstimate
import com.twintipsolutions.aclrehabtracker.data.pose.KneeSkeleton
import com.twintipsolutions.aclrehabtracker.data.pose.NPoint
import com.twintipsolutions.aclrehabtracker.data.pose.SideFit
import com.twintipsolutions.aclrehabtracker.data.pose.SkeletonLeg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The angle maths, leg choice, side check and saved-data rules, mirroring iOS knee_math_test. */
class KneeGeometryTest {
    private fun leg(hx: Double, hy: Double, kx: Double, ky: Double, ax: Double, ay: Double) =
        KneeKeypoints(NPoint(hx, hy), NPoint(kx, ky), NPoint(ax, ay))

    private val straight = leg(0.5, 0.2, 0.5, 0.5, 0.5, 0.8)
    private val rightAngle = leg(0.2, 0.5, 0.5, 0.5, 0.5, 0.8)

    @Test fun straightLegIsZeroAndRightAngleIsNinety() {
        assertEquals(0.0, KneeGeometry.flexion(straight, 1000, 1000)!!, 0.01)
        assertEquals(90.0, KneeGeometry.flexion(rightAngle, 1000, 1000)!!, 0.01)
    }

    @Test fun angleUsesPixelsSoANonSquarePhotoIsNotDistorted() {
        // The same right angle in pixels, on a photo twice as wide as it is tall.
        val wide = leg(0.35, 0.5, 0.5, 0.5, 0.5, 0.8)
        assertEquals(90.0, KneeGeometry.flexion(wide, 2000, 1000)!!, 0.01)
    }

    @Test fun samePointsGiveTheSameAngleWhateverTheZoom() {
        // Dots are fractions of the image; nothing about the screen enters the calculation.
        val a = KneeGeometry.flexion(rightAngle, 1200, 900)
        val b = KneeGeometry.flexion(rightAngle, 2400, 1800)
        assertEquals(a!!, b!!, 1e-9)
    }

    @Test fun displayRoundsAndClamps() {
        assertEquals(84, KneeGeometry.display(84.4))
        assertEquals(0, KneeGeometry.display(-3.0))
        assertEquals(180, KneeGeometry.display(190.0))
    }

    @Test fun theLegDoingTheMovementIsChosenWhenTheLegsClearlyDiffer() {
        val s = KneeSkeleton(
            left = SkeletonLeg(straight.hip, straight.knee, straight.ankle, 0.9),
            right = SkeletonLeg(rightAngle.hip, rightAngle.knee, rightAngle.ankle, 0.9),
        )
        assertEquals(KneeLeg.RIGHT, KneeGeometry.chooseLeg(s, KneeLeg.LEFT, KneeBend.FLEXION, 1000, 1000))
        assertEquals(KneeLeg.LEFT, KneeGeometry.chooseLeg(s, KneeLeg.RIGHT, KneeBend.EXTENSION, 1000, 1000))
    }

    @Test fun theSavedLegIsUsedWhenTheLegsLookAlikeAndConfidenceWithoutOne() {
        val s = KneeSkeleton(
            left = SkeletonLeg(straight.hip, straight.knee, straight.ankle, 0.6),
            right = SkeletonLeg(straight.hip, straight.knee, straight.ankle, 0.9),
        )
        assertEquals(KneeLeg.LEFT, KneeGeometry.chooseLeg(s, KneeLeg.LEFT, KneeBend.FLEXION, 1000, 1000))
        assertEquals(KneeLeg.RIGHT, KneeGeometry.chooseLeg(s, null, KneeBend.FLEXION, 1000, 1000))
        assertNull(KneeGeometry.chooseLeg(KneeSkeleton(), KneeLeg.LEFT, KneeBend.FLEXION, 1000, 1000))
    }

    @Test fun facingRightShowsTheRightSideAndMirroringFlipsIt() {
        // Standing (up is -y), facing the right edge (+x).
        assertEquals(KneeLeg.RIGHT, KneeGeometry.sideFacingCamera(0.0, -1.0, 1.0, 0.0))
        assertEquals(KneeLeg.LEFT, KneeGeometry.sideFacingCamera(0.0, -1.0, -1.0, 0.0))
        // Lying on the back with the head at the left edge also shows the right side.
        assertEquals(KneeLeg.RIGHT, KneeGeometry.sideFacingCamera(-1.0, 0.0, 0.0, -1.0))
        // Not sideways enough to say.
        assertNull(KneeGeometry.sideFacingCamera(0.0, -1.0, 0.1, -1.0))
    }

    @Test fun aStraightLegSaysNothingAboutFacingAndDisagreementMeansUnknown() {
        assertNull(KneeGeometry.sideFacingCamera(straight, 1000, 1000))
        assertEquals(KneeLeg.RIGHT, KneeGeometry.sideFacingCamera(KneeLeg.RIGHT, true, listOf(KneeLeg.RIGHT, null)))
        assertNull(KneeGeometry.sideFacingCamera(KneeLeg.RIGHT, true, listOf(KneeLeg.LEFT)))
        assertNull("a face in view but not in profile is a front view", KneeGeometry.sideFacingCamera(null, true, listOf(KneeLeg.RIGHT)))
    }

    @Test fun sideFitAndNotes() {
        assertEquals(SideFit.NotAsked, KneeGeometry.sideFit(null, KneeLeg.LEFT))
        assertEquals(SideFit.Matches, KneeGeometry.sideFit(KneeLeg.LEFT, KneeLeg.LEFT))
        assertEquals(SideFit.Opposite(KneeLeg.RIGHT), KneeGeometry.sideFit(KneeLeg.LEFT, KneeLeg.RIGHT))
        assertEquals(SideFit.Unknown, KneeGeometry.sideFit(KneeLeg.LEFT, null))

        fun estimate(conf: Double, facing: KneeLeg?) = KneePoseEstimate(rightAngle, KneeLeg.LEFT, conf, facing)
        assertNull(KneeGeometry.resultNote(estimate(0.9, KneeLeg.LEFT), KneeLeg.LEFT))
        assertNull("no saved side, nothing to compare", KneeGeometry.resultNote(estimate(0.9, null), null))
        assertTrue(KneeGeometry.resultNote(estimate(0.9, KneeLeg.RIGHT), KneeLeg.LEFT)!!
            .startsWith("Your right side is facing the camera, but your profile says left knee."))
        assertTrue(KneeGeometry.resultNote(estimate(0.9, null), KneeLeg.LEFT)!!.startsWith("Couldn't tell which side"))
        assertTrue(KneeGeometry.resultNote(estimate(0.35, KneeLeg.LEFT), KneeLeg.LEFT)!!.startsWith("Your phone wasn't sure"))
    }

    @Test fun unrotateMapsQuarterTurnsBack() {
        val p = NPoint(0.2, 0.7)
        assertEquals(p, KneeGeometry.unrotate(p, KneeGeometry.Rotation.NONE))
        assertEquals(NPoint(0.7, 0.8), KneeGeometry.unrotate(p, KneeGeometry.Rotation.CLOCKWISE))
        assertEquals(0.3, KneeGeometry.unrotate(p, KneeGeometry.Rotation.COUNTERCLOCKWISE).x, 1e-9)
    }

    // --- Backwards compatibility ---

    @Test fun aMissingOrUnknownModeMeansStandardPhoto() {
        assertEquals(MeasureMode.STANDARD, MeasureMode.fromKey(null))
        assertEquals(MeasureMode.STANDARD, MeasureMode.fromKey("something-new"))
        assertEquals(MeasureMode.ACCURATE, MeasureMode.fromKey("accurate"))
        assertEquals("Whole-body mode", MeasureMode.ACCURATE.title)
        assertTrue(MeasureMode.ACCURATE.isBeta)
        assertFalse(MeasureMode.STANDARD.isBeta)
    }

    @Test fun oldMeasurementsStillLoadAndStandardSavesAreUnchanged() {
        // A document saved by 1.1 or earlier: no method, no adjusted.
        val old = Measurement.fromFirestore("a", mapOf("type" to "flexion", "angle" to 120L, "weekPostOp" to 6L, "photoUrl" to "u"))
        assertEquals(MeasurementType.FLEXION, old.type)
        assertEquals(120, old.angle)
        assertNull(old.method)
        assertFalse(old.isWholeBody)
        // An unexpected value must not hide the measurement.
        assertFalse(Measurement.fromFirestore("b", mapOf("type" to "extension", "angle" to 3L, "method" to 7L)).isWholeBody)

        val standard = Measurement(type = MeasurementType.EXTENSION, angle = 3, weekPostOp = 2, photoUrl = "u").toFirestore()
        assertEquals(setOf("type", "angle", "timestamp", "weekPostOp", "photoUrl"), standard.keys)
    }

    @Test fun wholeBodySavesUseTheSameFieldsAsIos() {
        val saved = Measurement(type = MeasurementType.FLEXION, angle = 84, weekPostOp = 1,
            method = Measurement.METHOD_ON_DEVICE, adjusted = true).toFirestore()
        assertEquals("on_device", saved["method"])
        assertEquals(true, saved["adjusted"])
        val back = Measurement.fromFirestore("c", saved + mapOf("angle" to 84L, "weekPostOp" to 1L))
        assertTrue(back.isWholeBody)
        assertEquals(true, back.adjusted)
    }
}
