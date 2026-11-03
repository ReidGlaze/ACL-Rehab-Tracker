import Foundation
import FirebaseAnalytics

/// Funnel events for understanding where users drop off.
///
/// Privacy: never log angles, names, injury details, surgery dates, or error text here.
/// Only counts and outcomes, so the App Store privacy label stays "usage data" only.
/// Event and parameter names must match the Android `AnalyticsService` so both platforms
/// report into the same GA4 reports.
enum AnalyticsService {
    enum Source: String {
        case camera
        case library
    }

    enum FailureStage: String {
        case capture
        case analysis
        case save
    }

    static func onboardingCompleted() {
        Analytics.logEvent("onboarding_complete", parameters: nil)
    }

    static func aiConsent(accepted: Bool) {
        Analytics.logEvent("ai_consent", parameters: ["accepted": accepted ? "true" : "false"])
    }

    static func measurementStarted(type: MeasurementType, source: Source) {
        Analytics.logEvent("measurement_started", parameters: [
            "measurement_type": type.rawValue,
            "source": source.rawValue,
        ])
    }

    static func measurementAnalyzed(type: MeasurementType, source: Source) {
        Analytics.logEvent("measurement_analyzed", parameters: [
            "measurement_type": type.rawValue,
            "source": source.rawValue,
        ])
    }

    static func measurementFailed(type: MeasurementType, source: Source?, stage: FailureStage) {
        var params: [String: Any] = [
            "measurement_type": type.rawValue,
            "stage": stage.rawValue,
        ]
        if let source { params["source"] = source.rawValue }
        Analytics.logEvent("measurement_failed", parameters: params)
    }

    static func measurementRetaken(type: MeasurementType) {
        Analytics.logEvent("measurement_retake", parameters: ["measurement_type": type.rawValue])
    }

    /// `saveCount` is the user's lifetime saved-measurement count, so GA can show
    /// how many users get to their 2nd, 5th, 10th measurement.
    static func measurementSaved(type: MeasurementType, saveCount: Int) {
        Analytics.logEvent("measurement_saved", parameters: [
            "measurement_type": type.rawValue,
            "save_count": saveCount,
        ])
    }

    /// SwiftUI tabs don't trigger automatic screen tracking, so log them explicitly.
    static func screenViewed(_ name: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name,
        ])
    }
}
