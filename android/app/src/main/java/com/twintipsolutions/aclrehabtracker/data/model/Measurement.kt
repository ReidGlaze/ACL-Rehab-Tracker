package com.twintipsolutions.aclrehabtracker.data.model

import com.google.firebase.Timestamp
import java.util.Date

enum class MeasurementType(val displayName: String, val goalAngle: Int) {
    EXTENSION("Extension", 0),
    FLEXION("Flexion", 135);

    companion object {
        fun fromString(value: String): MeasurementType {
            return when (value.lowercase()) {
                "extension" -> EXTENSION
                "flexion" -> FLEXION
                else -> EXTENSION
            }
        }
    }
}

data class Measurement(
    val id: String = "",
    val type: MeasurementType = MeasurementType.EXTENSION,
    val angle: Int = 0,
    val timestamp: Date = Date(),
    val weekPostOp: Int = 0,
    val photoUrl: String = ""
) {
    companion object {
        fun fromFirestore(id: String, data: Map<String, Any?>): Measurement {
            return Measurement(
                id = id,
                type = MeasurementType.fromString(data["type"] as? String ?: "extension"),
                angle = (data["angle"] as? Long)?.toInt() ?: 0,
                timestamp = (data["timestamp"] as? Timestamp)?.toDate() ?: Date(),
                weekPostOp = (data["weekPostOp"] as? Long)?.toInt() ?: 0,
                photoUrl = data["photoUrl"] as? String ?: ""
            )
        }
    }

    fun toFirestore(): Map<String, Any> {
        return mapOf(
            "type" to type.name.lowercase(),
            "angle" to angle,
            "timestamp" to Timestamp(timestamp),
            "weekPostOp" to weekPostOp,
            "photoUrl" to photoUrl
        )
    }
}
