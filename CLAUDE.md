# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ACL Rehab Tracker - A multi-platform mobile app for tracking ACL rehabilitation progress using AI-powered knee angle measurement.

## Project Structure

- `ios/ios_new/` - iOS app (Swift/SwiftUI)
- `android/` - Android app (Kotlin/Jetpack Compose)
- `functions/` - Firebase Cloud Functions (TypeScript)
- `web/` - Landing page / marketing site

## Backend

- Firebase project: `acl-rehab-d3e88`
- Auth: Anonymous Firebase Auth
- Database: Cloud Firestore
- Storage: Firebase Storage (photo uploads)
- AI: Gemini via Cloud Function (`analyzeKneeAngle`)
