# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ACL Rehab Tracker - A multi-platform mobile app for tracking ACL rehabilitation progress using AI-powered knee angle measurement.

## Project Structure

- `ios/` - iOS app (Swift/SwiftUI)
- `android/` - Android app (Kotlin/Jetpack Compose)
- `functions/` - Firebase Cloud Functions (TypeScript)
- `web/` - Landing page / marketing site

## Backend

- Firebase project: `acl-rehab-d3e88`
- Auth: Anonymous Firebase Auth
- Database: Cloud Firestore
- Storage: Firebase Storage (photo uploads)
- AI: Gemini via Cloud Function (`analyzeKneeAngle`)

## Measuring methods (iOS)

The Measure tab has two methods, chosen in the "Method" row. The choice is stored on the device
(`UserDefaults` key `measureMode`); a missing value means Standard photo.

- **Standard photo** (default): the original flow. `GeminiPoseService` sends the photo to the
  `analyzeKneeAngle` Cloud Function and an AI model returns the angle. Works on knee close-ups.
- **Whole-body mode** (opt-in, shown with a "Beta" tag; called Accurate mode in code, `MeasureMode.accurate`,
  and in the docs below): `KneePoseEstimator` finds hip, knee and ankle on the phone with Apple
  Vision and `KneeAngleMath` computes the angle (straight leg = 0). The photo needs the whole body,
  side-on. (`KneeAnalyzer.photoCheckEnabled` is false in 1.2 because `checkKneePhoto` is not deployed:
  the app does not call it and the explainer does not mention it.) When enabled, in parallel `checkKneePhoto` (Gemini, `functions/src/kneeCheck.ts`) says whether the
  photo is usable; if it can't run, the on-device result is shown anyway. The result screen draws
  the three points on the photo and they can be dragged.

Accurate mode only (none of this shows in Standard photo):
- **Which leg**: the knee saved at onboarding is the one measured. The estimator also works out
  which side of the body faces the camera (`sideFacingCamera`: head direction, bent-knee direction,
  shoulder width for front views). If that is the other side, or can't be told, the result shows a
  note (`MeasureView.resultNote`) instead of guessing silently. Vision's own left/right labels are
  unreliable in profile, so when the two legs clearly differ the one doing the movement is measured.
- **Pose guide**: `PoseGuideSheet` (drawings for flexion and extension plus four rules). Opens once
  when Accurate mode is first chosen, and from "How to pose" on the camera preview.
- **Zoom**: on the result photo (`KneeKeypointEditor`) pinch zooms up to 5x, one finger pans, double tap
  zooms in or back out, and a "Reset zoom" pill appears while zoomed. Dots stay the same size and are
  stored as fractions of the image, so zoom never changes the angle. Standard photo results have no
  dots and no zoom.
- **Self-timer**: off / 5 s / 10 s pill on the camera preview. Counts on screen and with beeps
  (`CountdownBeeper`, plays even on silent); tapping the capture button again cancels.

Saved measurements are the same Firestore documents for both. Accurate mode adds two optional
fields, `method: "on_device"` and `adjusted`; documents without them are Standard photo ones.
Android (1.2, versionCode 7) has both methods too, with the same names, fields and preference key
(`measureMode` in the `acl_rehab_prefs` SharedPreferences). Its twins of the iOS pieces:
`data/model/MeasureMode.kt`, `data/pose/KneeGeometry.kt` (angle math, leg choice, result note),
`data/service/KneePoseEstimator.kt` (ML Kit accurate pose detection, on the device, model bundled) and
`ui/screens/measure/WholeBodyUi.kt` (chooser, pose guide, self-timer beeper, zoomable dot editor).
There is no photo check on Android. A device with no camera shows a message and still measures from
the photo library.

Android tests: `./gradlew :app:testDebugUnitTest` (geometry) and `WholeBodyModeTest` on an emulator.
The emulator tests need `seated.jpg` and `closeup.jpg` pushed to `/data/local/tmp/acl-test/` (see the
test's header; `accuracy/fixtures/rehab/flexion_85_gem-seated.jpg` and
`accuracy/fixtures/bad/flexion_x_closeup-bench.jpg` are the ones used). They clear the app's saved
preferences on that emulator, and an emulator holding a release-signed install can't run them.

`accuracy/` holds the harness that scores the estimator against labelled photos; see its README.
