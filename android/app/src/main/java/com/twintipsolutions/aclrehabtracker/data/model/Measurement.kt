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
    val photoUrl: String = "",
    /**
     * How the angle was produced. Null on every measurement saved before Whole-body mode existed
     * and on Standard photo ones; only Whole-body mode writes it ("on_device", the same value iOS
     * writes), so older app versions and saved data are unaffected.
     */
    val method: String? = null,
    /** True when the user dragged a dot before saving. Whole-body mode only. */
    val adjusted: Boolean? = null
) {
    val isWholeBody: Boolean get() = method == METHOD_ON_DEVICE

    companion object {
        const val METHOD_ON_DEVICE = "on_device"

        fun fromFirestore(id: String, data: Map<String, Any?>): Measurement {
            return Measurement(
                id = id,
                type = MeasurementType.fromString(data["type"] as? String ?: "extension"),
                angle = (data["angle"] as? Long)?.toInt() ?: 0,
                timestamp = (data["timestamp"] as? Timestamp)?.toDate() ?: Date(),
                weekPostOp = (data["weekPostOp"] as? Long)?.toInt() ?: 0,
                photoUrl = data["photoUrl"] as? String ?: "",
                // Optional and lenient: a missing or unexpected value must never hide a measurement.
                method = data["method"] as? String,
                adjusted = data["adjusted"] as? Boolean
            )
        }
    }

    fun toFirestore(): Map<String, Any> {
        val map = mutableMapOf<String, Any>(
            "type" to type.name.lowercase(),
            "angle" to angle,
            "timestamp" to Timestamp(timestamp),
            "weekPostOp" to weekPostOp,
            "photoUrl" to photoUrl
        )
        // Standard photo saves stay exactly the document they always were.
        method?.let { map["method"] = it }
        adjusted?.let { map["adjusted"] = it }
        return map
    }
}
