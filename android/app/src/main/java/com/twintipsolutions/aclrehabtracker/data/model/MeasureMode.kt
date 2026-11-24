package com.twintipsolutions.aclrehabtracker.data.model

import android.content.Context

/**
 * How the Measure tab turns a photo into an angle. Stored on the device only. The default is the
 * original method, so nothing changes for anyone who never opens the chooser.
 *
 * Users see ACCURATE as "Whole-body mode" with a Beta tag. The internal name and the stored key
 * match iOS (`MeasureMode.accurate`, preference "measureMode").
 */
enum class MeasureMode(val key: String, val title: String, val summary: String) {
    STANDARD(
        "standard", "Standard photo",
        "Take a photo of your knee from the side. AI estimates the angle. About 15 seconds.",
    ),
    ACCURATE(
        "accurate", "Whole-body mode",
        "Get your whole body in the photo. Your phone finds your hip, knee and ankle and measures between them.",
    );

    val isBeta: Boolean get() = this == ACCURATE

    /** The name as a screen reader should say it. */
    val spokenTitle: String get() = if (isBeta) "$title, beta" else title

    fun instruction(type: MeasurementType): String = when (this) {
        STANDARD -> if (type == MeasurementType.EXTENSION)
            "Straighten your leg as much as possible and capture from the side"
        else "Bend your knee as much as possible and capture from the side"
        ACCURATE -> if (type == MeasurementType.EXTENSION)
            "Step back until your whole body is in the photo, side-on. Then straighten your leg as much as possible"
        else "Step back until your whole body is in the photo, side-on. Then bend your knee as much as possible"
    }

    companion object {
        const val PREFS = "acl_rehab_prefs"
        const val KEY = "measureMode"
        const val KEY_POSE_GUIDE_SEEN = "accuratePoseGuideSeen"
        const val KEY_SELF_TIMER = "accurateSelfTimerSeconds"

        /** A missing or unknown value means Standard photo. */
        fun fromKey(key: String?): MeasureMode = entries.firstOrNull { it.key == key } ?: STANDARD

        fun load(context: Context): MeasureMode =
            fromKey(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))

        fun save(context: Context, mode: MeasureMode) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, mode.key).apply()
        }
    }
}
