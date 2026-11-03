package com.twintipsolutions.aclrehabtracker.data.service

import android.os.Bundle
import com.google.firebase.Firebase
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.analytics.analytics
import com.twintipsolutions.aclrehabtracker.data.model.MeasurementType

/**
 * Funnel events for understanding where users drop off.
 *
 * Privacy: never log angles, names, injury details, surgery dates, or error text here.
 * Only counts and outcomes, so the Play Data safety form stays "app activity" only.
 * Event and parameter names must match the iOS `AnalyticsService` so both platforms
 * report into the same GA4 reports.
 */
object AnalyticsService {
    enum class Source(val value: String) { CAMERA("camera"), LIBRARY("library") }

    enum class FailureStage(val value: String) { CAPTURE("capture"), ANALYSIS("analysis"), SAVE("save") }

    private val analytics: FirebaseAnalytics by lazy { Firebase.analytics }

    private val MeasurementType.value: String get() = name.lowercase()

    private fun log(event: String, build: Bundle.() -> Unit = {}) {
        analytics.logEvent(event, Bundle().apply(build))
    }

    fun onboardingCompleted() = log("onboarding_complete")

    fun measurementStarted(type: MeasurementType, source: Source) = log("measurement_started") {
        putString("measurement_type", type.value)
        putString("source", source.value)
    }

    fun measurementAnalyzed(type: MeasurementType, source: Source) = log("measurement_analyzed") {
        putString("measurement_type", type.value)
        putString("source", source.value)
    }

    fun measurementFailed(type: MeasurementType, source: Source?, stage: FailureStage) =
        log("measurement_failed") {
            putString("measurement_type", type.value)
            putString("stage", stage.value)
            source?.let { putString("source", it.value) }
        }

    fun measurementRetaken(type: MeasurementType) = log("measurement_retake") {
        putString("measurement_type", type.value)
    }

    /** [saveCount] is the user's lifetime saved-measurement count. */
    fun measurementSaved(type: MeasurementType, saveCount: Int) = log("measurement_saved") {
        putString("measurement_type", type.value)
        putLong("save_count", saveCount.toLong())
    }

    /** Compose navigation doesn't trigger automatic screen tracking, so log tabs explicitly. */
    fun screenViewed(name: String) = log(FirebaseAnalytics.Event.SCREEN_VIEW) {
        putString(FirebaseAnalytics.Param.SCREEN_NAME, name)
        putString(FirebaseAnalytics.Param.SCREEN_CLASS, name)
    }
}
