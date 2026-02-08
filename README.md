# ACL Rehab Tracker

A mobile app that helps ACL surgery patients track their rehabilitation progress using AI-powered knee angle measurement.

Available on the [App Store](https://apps.apple.com/app/acl-rehab-tracker/id6745041257) and [Google Play](https://play.google.com/store/apps/details?id=com.twintipsolutions.aclrehabtracker).

## What It Does

- Take a photo of your knee (or pick one from your library)
- AI analyzes the image and measures your knee flexion/extension angle
- Track measurements over time with charts and history
- See your progress through recovery milestones

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS | Swift, SwiftUI |
| Android | Kotlin, Jetpack Compose |
| Backend | Firebase (Auth, Firestore, Storage, Cloud Functions) |
| AI | Google Gemini via Firebase Cloud Function |
| Landing Page | Static HTML/CSS on Vercel |

## Project Structure

```
.
├── ios/              # iOS app (SwiftUI)
├── android/          # Android app (Jetpack Compose)
├── functions/        # Firebase Cloud Functions (TypeScript)
└── web/              # Landing page
```

## Architecture

- **Anonymous auth** — no login required, users start tracking immediately
- **Serverless AI** — photos are sent to a Cloud Function that calls Gemini for knee angle analysis
- **Shared Firebase backend** — both platforms read/write to the same Firestore database
- **Native UI** — each platform uses its native UI framework (SwiftUI / Compose), no cross-platform abstraction

## Building

### iOS

Requires Xcode 15+ and CocoaPods.

```bash
cd ios
pod install
open ACLRehabTracker.xcworkspace
```

### Android

Requires Android Studio and JDK 17.

```bash
cd android
./gradlew assembleDebug
```

### Cloud Functions

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

## License

All rights reserved.
