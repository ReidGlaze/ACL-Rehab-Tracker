package com.twintipsolutions.aclrehabtracker.data.service

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import com.twintipsolutions.aclrehabtracker.data.pose.KneeBend
import com.twintipsolutions.aclrehabtracker.data.pose.KneeGeometry
import com.twintipsolutions.aclrehabtracker.data.pose.KneeKeypoints
import com.twintipsolutions.aclrehabtracker.data.pose.KneeLeg
import com.twintipsolutions.aclrehabtracker.data.pose.KneePoseEstimate
import com.twintipsolutions.aclrehabtracker.data.pose.KneeSkeleton
import com.twintipsolutions.aclrehabtracker.data.pose.NPoint
import com.twintipsolutions.aclrehabtracker.data.pose.SkeletonLeg
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlin.math.hypot

/**
 * Whole-body mode's joint finder: ML Kit pose detection, entirely on the device. Nothing is
 * uploaded. The Android twin of the iOS `KneePoseEstimator` (which uses Apple Vision).
 */
object KneePoseEstimator {
    /** A joint ML Kit thinks is probably out of the frame is treated as not found. */
    private const val MIN_LIKELIHOOD = 0.3f
    /** An upright result at or above this is used as it is; below it the turned copies are tried too. */
    private const val GOOD_ENOUGH_CONFIDENCE = 0.6
    private const val MAX_DIMENSION = 1600

    /**
     * Reads a photo the way it is displayed (EXIF rotation applied), scaled so the longer side is
     * at most [MAX_DIMENSION]. Null when the file can't be decoded.
     */
    fun loadUpright(path: String): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_DIMENSION) sample *= 2
        val raw = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val degrees = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        val longest = maxOf(raw.width, raw.height)
        val scale = if (longest > MAX_DIMENSION) MAX_DIMENSION.toFloat() / longest else 1f
        if (degrees == 0f && scale == 1f) raw
        else Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, Matrix().apply { postScale(scale, scale); postRotate(degrees) }, true)
    }.getOrNull()

    /** Null when no complete leg (hip, knee and ankle) is found, for example on a knee close-up. */
    suspend fun estimate(photo: Bitmap, bend: KneeBend, requested: KneeLeg?): KneePoseEstimate? = withContext(Dispatchers.Default) {
        val options = AccuratePoseDetectorOptions.Builder()
            .setDetectorMode(AccuratePoseDetectorOptions.SINGLE_IMAGE_MODE)
            .build()
        val detector = PoseDetection.getClient(options)
        try {
            var best: KneeSkeleton? = null
            for (rotation in KneeGeometry.Rotation.entries) {
                val turned = if (rotation == KneeGeometry.Rotation.NONE) photo
                else Bitmap.createBitmap(photo, 0, 0, photo.width, photo.height, Matrix().apply { postRotate(rotation.degrees) }, true)
                val pose = runCatching { detector.process(InputImage.fromBitmap(turned, 0)).await() }.getOrNull()
                val found = pose?.let { skeleton(it, turned.width, turned.height) }
                val mapped = found?.let { unrotate(it, rotation) }
                if (mapped != null && mapped.bestConfidence > (best?.bestConfidence ?: 0.0)) best = mapped
                if (rotation == KneeGeometry.Rotation.NONE && (mapped?.bestConfidence ?: 0.0) >= GOOD_ENOUGH_CONFIDENCE) break
            }
            val skeleton = best ?: return@withContext null
            val leg = KneeGeometry.chooseLeg(skeleton, requested, bend, photo.width, photo.height) ?: return@withContext null
            val points = skeleton.leg(leg).keypoints ?: return@withContext null
            KneePoseEstimate(
                keypoints = KneeKeypoints(points.hip.clamped, points.knee.clamped, points.ankle.clamped),
                measuredLeg = leg,
                confidence = skeleton.leg(leg).confidence,
                sideFacingCamera = skeleton.sideFacingCamera,
            )
        } finally {
            detector.close()
        }
    }

    private fun skeleton(pose: Pose, width: Int, height: Int): KneeSkeleton? {
        if (pose.allPoseLandmarks.isEmpty()) return null
        fun landmark(type: Int): PoseLandmark? = pose.getPoseLandmark(type)?.takeIf { it.inFrameLikelihood >= MIN_LIKELIHOOD }
        fun point(type: Int): NPoint? = landmark(type)?.let { NPoint(it.position.x.toDouble() / width, it.position.y.toDouble() / height) }
        fun leg(hip: Int, knee: Int, ankle: Int): SkeletonLeg {
            val joints = listOf(hip, knee, ankle).map { landmark(it) }
            return SkeletonLeg(point(hip), point(knee), point(ankle),
                confidence = if (joints.any { it == null }) 0.0 else joints.minOf { it!!.inFrameLikelihood.toDouble() })
        }
        val left = leg(PoseLandmark.LEFT_HIP, PoseLandmark.LEFT_KNEE, PoseLandmark.LEFT_ANKLE)
        val right = leg(PoseLandmark.RIGHT_HIP, PoseLandmark.RIGHT_KNEE, PoseLandmark.RIGHT_ANKLE)

        /** Average pixel position of the given joints that were found, or null when none were. */
        fun pixels(vararg types: Int): Pair<Double, Double>? {
            val found = types.toList().mapNotNull { landmark(it) }
            if (found.isEmpty()) return null
            return found.map { it.position.x.toDouble() }.average() to found.map { it.position.y.toDouble() }.average()
        }
        val top = pixels(PoseLandmark.LEFT_SHOULDER, PoseLandmark.RIGHT_SHOULDER)
        val bottom = pixels(PoseLandmark.LEFT_HIP, PoseLandmark.RIGHT_HIP)
        val nose = pixels(PoseLandmark.NOSE)
        val ears = pixels(PoseLandmark.LEFT_EAR, PoseLandmark.RIGHT_EAR)
        var head: KneeLeg? = null
        var headInView = false
        if (top != null && bottom != null && nose != null && ears != null) {
            headInView = true
            head = KneeGeometry.sideFacingCamera(top.first - bottom.first, top.second - bottom.second,
                nose.first - ears.first, nose.second - ears.second)
        }
        // Shoulders wide apart: a front or back view, whatever the head and knees suggest.
        val ls = pixels(PoseLandmark.LEFT_SHOULDER)
        val rs = pixels(PoseLandmark.RIGHT_SHOULDER)
        if (top != null && bottom != null && ls != null && rs != null) {
            val torso = hypot(top.first - bottom.first, top.second - bottom.second)
            if (torso > 1 && hypot(ls.first - rs.first, ls.second - rs.second) / torso >= KneeGeometry.MAXIMUM_SHOULDER_SPREAD_FOR_SIDE_VIEW) {
                headInView = true
                head = null
            }
        }
        val facing = KneeGeometry.sideFacingCamera(head, headInView,
            listOf(left, right).map { l -> l.keypoints?.let { KneeGeometry.sideFacingCamera(it, width, height) } })
        return KneeSkeleton(left, right, facing)
    }

    private fun unrotate(s: KneeSkeleton, rotation: KneeGeometry.Rotation): KneeSkeleton {
        if (rotation == KneeGeometry.Rotation.NONE) return s
        fun leg(l: SkeletonLeg) = l.copy(
            hip = l.hip?.let { KneeGeometry.unrotate(it, rotation) },
            knee = l.knee?.let { KneeGeometry.unrotate(it, rotation) },
            ankle = l.ankle?.let { KneeGeometry.unrotate(it, rotation) },
        )
        // Turning the photo a quarter turn does not change which side of the body faces the camera.
        return KneeSkeleton(leg(s.left), leg(s.right), s.sideFacingCamera)
    }
}
