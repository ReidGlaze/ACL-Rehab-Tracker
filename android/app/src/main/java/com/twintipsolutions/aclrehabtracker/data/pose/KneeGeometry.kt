package com.twintipsolutions.aclrehabtracker.data.pose

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.roundToInt

/** A point in normalized image coordinates: (0,0) is the top-left corner, (1,1) the bottom-right. */
data class NPoint(val x: Double, val y: Double) {
    val clamped: NPoint get() = NPoint(x.coerceIn(0.0, 1.0), y.coerceIn(0.0, 1.0))
}

/** The three points that define a knee angle: thigh runs hip to knee, shin runs knee to ankle. */
data class KneeKeypoints(val hip: NPoint, val knee: NPoint, val ankle: NPoint)

enum class KneeBend { FLEXION, EXTENSION }

enum class KneeLeg(val key: String) {
    LEFT("left"), RIGHT("right");

    val opposite: KneeLeg get() = if (this == LEFT) RIGHT else LEFT
}

/** One leg as the detector reported it. `confidence` is the lowest of its three joints, 0..1. */
data class SkeletonLeg(
    val hip: NPoint? = null,
    val knee: NPoint? = null,
    val ankle: NPoint? = null,
    val confidence: Double = 0.0,
) {
    val keypoints: KneeKeypoints?
        get() = if (hip != null && knee != null && ankle != null) KneeKeypoints(hip, knee, ankle) else null
}

data class KneeSkeleton(
    val left: SkeletonLeg = SkeletonLeg(),
    val right: SkeletonLeg = SkeletonLeg(),
    /** Which side of the body is toward the camera, when the photo is clearly a side view. */
    val sideFacingCamera: KneeLeg? = null,
) {
    fun leg(side: KneeLeg) = if (side == KneeLeg.LEFT) left else right

    /** Confidence of the better complete leg, or 0 when neither leg is complete. */
    val bestConfidence: Double
        get() = KneeLeg.entries.mapNotNull { if (leg(it).keypoints == null) null else leg(it).confidence }.maxOrNull() ?: 0.0
}

data class KneePoseEstimate(
    val keypoints: KneeKeypoints,
    val measuredLeg: KneeLeg,
    val confidence: Double,
    /** Null when it can't be told (a front view, or the head and the knees disagree). */
    val sideFacingCamera: KneeLeg?,
)

/** How the side the user is rehabbing compares with the side the camera can see. */
sealed interface SideFit {
    /** No side is saved in the profile, so there is nothing to compare. */
    data object NotAsked : SideFit
    data object Matches : SideFit
    data class Opposite(val facing: KneeLeg) : SideFit
    data object Unknown : SideFit
}

/**
 * Angle maths and leg choice for Whole-body mode. A straight port of the iOS `KneeAngleMath` and
 * `KneeGeometry`, kept free of Android classes so it runs in plain unit tests. Keep the two in step.
 */
object KneeGeometry {
    /** How much more bent (or straighter) one leg must be before it overrides the requested leg. */
    const val CLEARLY_DIFFERENT_MARGIN = 20.0
    /** How far sideways (as a share of its own length) a "forward" clue must point before it counts. */
    const val MINIMUM_SIDEWAYS = 0.35
    /** Shoulders this far apart, as a share of the torso's length, mean a front or back view. */
    const val MAXIMUM_SHOULDER_SPREAD_FOR_SIDE_VIEW = 0.45
    /** A knee has to be bent at least this much before its direction says which way the body faces. */
    const val MINIMUM_BEND_FOR_FACING = 25.0
    /** Below this the result carries a "check the dots" note. */
    const val LOW_CONFIDENCE = 0.5

    /** Angle at `vertex` between the rays to `a` and `b`, in degrees (0..180). Points in pixels. */
    fun angle(vx: Double, vy: Double, ax: Double, ay: Double, bx: Double, by: Double): Double? {
        val x1 = ax - vx; val y1 = ay - vy
        val x2 = bx - vx; val y2 = by - vy
        val l1 = hypot(x1, y1); val l2 = hypot(x2, y2)
        if (l1 < 1e-9 || l2 < 1e-9) return null
        return Math.toDegrees(acos(((x1 * x2 + y1 * y2) / (l1 * l2)).coerceIn(-1.0, 1.0)))
    }

    /**
     * Knee flexion the way the app has always reported it: a straight leg is 0 and a right-angle
     * bend is 90. Normalized points are scaled to pixels first, or a non-square photo distorts it.
     */
    fun flexion(p: KneeKeypoints, width: Int, height: Int): Double? {
        if (width <= 0 || height <= 0) return null
        val inner = angle(
            p.knee.x * width, p.knee.y * height,
            p.hip.x * width, p.hip.y * height,
            p.ankle.x * width, p.ankle.y * height,
        ) ?: return null
        return 180 - inner
    }

    /** Whole degrees, the precision the app stores and shows. */
    fun display(degrees: Double): Int = degrees.roundToInt().coerceIn(0, 180)

    /**
     * Picks the leg to measure. In a side view detectors often swap left and right, and in most
     * rehab photos only one leg is doing the movement. So when the two legs clearly differ, the
     * one doing the movement wins: the more bent leg for flexion, the straighter one for
     * extension. Otherwise the requested leg, then the one the detector is surer of.
     */
    fun chooseLeg(skeleton: KneeSkeleton, requested: KneeLeg?, bend: KneeBend, width: Int, height: Int): KneeLeg? {
        val usable = KneeLeg.entries.filter { skeleton.leg(it).keypoints != null }
        if (usable.isEmpty()) return null
        if (usable.size == 1) return usable.first()
        val left = skeleton.left.keypoints?.let { flexion(it, width, height) }
        val right = skeleton.right.keypoints?.let { flexion(it, width, height) }
        if (left != null && right != null && abs(left - right) >= CLEARLY_DIFFERENT_MARGIN) {
            val moreBent = if (left > right) KneeLeg.LEFT else KneeLeg.RIGHT
            return if (bend == KneeBend.FLEXION) moreBent else moreBent.opposite
        }
        if (requested != null) return requested
        return if (skeleton.left.confidence >= skeleton.right.confidence) KneeLeg.LEFT else KneeLeg.RIGHT
    }

    /**
     * Which side of the body is toward the camera, from one clue: a direction that runs up the
     * body and a direction that points to the body's front. Pixels, y down. Someone standing and
     * facing the right edge of the photo shows the camera their right side.
     */
    fun sideFacingCamera(upX: Double, upY: Double, forwardX: Double, forwardY: Double): KneeLeg? {
        val lu = hypot(upX, upY); val lf = hypot(forwardX, forwardY)
        if (lu < 1e-6 || lf < 1e-6) return null
        val cross = (upX * forwardY - upY * forwardX) / (lu * lf)
        if (abs(cross) < MINIMUM_SIDEWAYS) return null
        return if (cross > 0) KneeLeg.RIGHT else KneeLeg.LEFT
    }

    /** The same question asked of one leg: a bent knee points to the body's front. */
    fun sideFacingCamera(leg: KneeKeypoints, width: Int, height: Int): KneeLeg? {
        val bend = flexion(leg, width, height) ?: return null
        if (bend < MINIMUM_BEND_FOR_FACING) return null
        val hx = leg.hip.x * width; val hy = leg.hip.y * height
        val kx = leg.knee.x * width; val ky = leg.knee.y * height
        val ax = leg.ankle.x * width; val ay = leg.ankle.y * height
        return sideFacingCamera(hx - ax, hy - ay, kx - (hx + ax) / 2, ky - (hy + ay) / 2)
    }

    /**
     * Combines the head's answer with the bent knees'. Any disagreement means "can't tell", and so
     * does a face that is in view but not in profile (a front or back view).
     */
    fun sideFacingCamera(head: KneeLeg?, headInView: Boolean, legs: List<KneeLeg?>): KneeLeg? {
        if (headInView && head == null) return null
        val votes = (listOf(head) + legs).filterNotNull()
        val first = votes.firstOrNull() ?: return null
        return if (votes.all { it == first }) first else null
    }

    fun sideFit(requested: KneeLeg?, facing: KneeLeg?): SideFit = when {
        requested == null -> SideFit.NotAsked
        facing == null -> SideFit.Unknown
        facing == requested -> SideFit.Matches
        else -> SideFit.Opposite(facing)
    }

    /** Quarter turns applied to the photo before detection (people doing heel slides are lying down). */
    enum class Rotation(val degrees: Float) { NONE(0f), CLOCKWISE(90f), COUNTERCLOCKWISE(-90f) }

    /** Maps a point found in a rotated copy of the photo back onto the original photo. */
    fun unrotate(p: NPoint, rotation: Rotation): NPoint = when (rotation) {
        Rotation.NONE -> p
        Rotation.CLOCKWISE -> NPoint(p.y, 1 - p.x)
        Rotation.COUNTERCLOCKWISE -> NPoint(1 - p.y, p.x)
    }

    /**
     * The note under the angle, or null when nothing needs saying. `kneeName` is "left"/"right"
     * from the profile. Same wording and order as iOS `MeasureView.resultNote`.
     */
    fun resultNote(estimate: KneePoseEstimate, requested: KneeLeg?): String? {
        val name = requested?.key ?: ""
        val fit = sideFit(requested, estimate.sideFacingCamera)
        if (fit is SideFit.Opposite) {
            return "Your ${fit.facing.key} side is facing the camera, but your profile says $name knee. " +
                "Check the dots are on your $name leg, or retake with it nearest the camera."
        }
        if (estimate.confidence < LOW_CONFIDENCE) {
            return "Your phone wasn't sure about this photo. Check the dots and drag any that are off."
        }
        if (fit == SideFit.Unknown) {
            return "Couldn't tell which side is facing the camera. Check the dots are on your $name leg."
        }
        return null
    }
}
