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
- **Accurate mode** (opt-in): `KneePoseEstimator` finds hip, knee and ankle on the phone with Apple
  Vision and `KneeAngleMath` computes the angle (straight leg = 0). The photo needs the whole body,
  side-on. In parallel `checkKneePhoto` (Gemini, `functions/src/kneeCheck.ts`) says whether the
  photo is usable; if it can't run, the on-device result is shown anyway. The result screen draws
  the three points on the photo and they can be dragged.

Saved measurements are the same Firestore documents for both. Accurate mode adds two optional
fields, `method: "on_device"` and `adjusted`; documents without them are Standard photo ones.
Android has Standard photo only for now.

`accuracy/` holds the harness that scores the estimator against labelled photos; see its README.
