package com.twintipsolutions.aclrehabtracker.data.service

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import com.google.firebase.functions.FirebaseFunctions
import com.twintipsolutions.aclrehabtracker.data.model.Keypoint
import com.twintipsolutions.aclrehabtracker.data.model.PoseResult
import kotlinx.coroutines.tasks.await
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

object GeminiPoseService {
    private val functions = FirebaseFunctions.getInstance("us-central1")

    suspend fun detectKneeAngle(
        imagePath: String,
        injuredKnee: String? = null,
        injuryType: String? = null
    ): PoseResult {
        val bitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw Exception("Could not load image from path")
        return detectKneeAngle(bitmap, injuredKnee, injuryType)
    }

    suspend fun detectKneeAngle(
        bitmap: Bitmap,
        injuredKnee: String? = null,
        injuryType: String? = null
    ): PoseResult {
        val resized = resizeImage(bitmap, 1024)
        val base64 = bitmapToBase64(resized)

        val data = hashMapOf<String, Any>(
            "imageBase64" to base64
        )
        injuredKnee?.let { data["injuredKnee"] = it }
        injuryType?.let { data["injuryType"] = it }

        val result = functions
            .getHttpsCallable("analyzeKneeAngle")
            .call(data)
            .await()

        @Suppress("UNCHECKED_CAST")
        val responseData = result.getData() as Map<String, Any>

        val angle = (responseData["angle"] as? Number)?.toInt()
            ?: throw Exception("No angle in response")
        val confidence = (responseData["confidence"] as? Number)?.toDouble() ?: 0.0

        @Suppress("UNCHECKED_CAST")
        val hipData = responseData["hip"] as? Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val kneeData = responseData["knee"] as? Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val ankleData = responseData["ankle"] as? Map<String, Any>

        return PoseResult(
            hip = parseKeypoint(hipData),
            knee = parseKeypoint(kneeData),
            ankle = parseKeypoint(ankleData),
            angle = angle,
            confidence = confidence
        )
    }

    private fun parseKeypoint(data: Map<String, Any>?): Keypoint {
        if (data == null) return Keypoint(0f, 0f)
        return Keypoint(
            x = (data["x"] as? Number)?.toFloat() ?: 0f,
            y = (data["y"] as? Number)?.toFloat() ?: 0f
        )
    }

    private fun resizeImage(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val maxDim = max(width, height)
        if (maxDim <= maxDimension) return bitmap

        val scale = maxDimension.toFloat() / maxDim
        val newWidth = (width * scale).roundToInt()
        val newHeight = (height * scale).roundToInt()
        return Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    }

    private fun bitmapToBase64(bitmap: Bitmap): String {
        val baos = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
        return Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
    }
}
