# Private knee-angle model comparison

The Debug build installs as **ACL Rehab Test** (`com.twintipsolutions.ACLRehabTracker.test`).
Release retains the production bundle identifier and normal application screens.
The `ACL_MODEL_TEST` compilation condition gates the comparison UI.

## Git checkpoint

Branch: `codex/gemini-accuracy-test`.
Commit `6ee5c4f` preserves the pre-existing local backend, consent, and privacy changes.
Do not merge or deploy the production function as part of model testing.

## Local setup

The separate Firebase iOS app is `1:942682033745:ios:adb71fdc302678c5fc7270` in project `acl-rehab-d3e88`.
Download its local configuration (ignored by Git):

```sh
firebase apps:sdkconfig IOS 1:942682033745:ios:adb71fdc302678c5fc7270 \
  --project acl-rehab-d3e88 --out ios/ACLRehabTracker/GoogleService-Test.plist
```

Open `ios/ACLRehabTracker.xcworkspace`, select the `ACLRehabTracker` scheme,
select your iPhone, and Run using Debug. The resulting app is separate from the App Store app.
Debug requires the test configuration; Release uses the original `GoogleService-Info.plist`.

The comparison app signs in anonymously with its own bundle-specific keychain storage.
Copy the Tester UID shown at the bottom of the test screen. Put it in the untracked
`functions/.env.acl-rehab-d3e88` file:

```dotenv
GEMINI_TESTER_UIDS=your-test-app-uid
```

Multiple test UIDs can be comma-separated. An empty allowlist denies everyone.
Reinstalling the app may require updating the allowlist if its anonymous account changes.

## Backend verification and deployment

```sh
npm --prefix functions run build
node --test functions/test/*.test.cjs
firebase deploy --only functions:analyzeKneeAngleGeminiTest --project acl-rehab-d3e88
```

Deploy **only** the named test function. The production `analyzeKneeAngle` export
and its model/prompt are unchanged. Never run the broad deploy command for this test.
The Gemini endpoint checks Firebase authentication and a tester UID allowlist before
making any AI request. It has a one-instance cap, concurrency two, and a 120-second timeout.
It calls the pinned `gemini-3.8-flash` model through Vertex AI's global endpoint with high thinking.
It does not write photos, measurements, or profiles to Firestore or Storage.
Its logs contain timing/status only. The existing Opus production function retains its own logging behavior.

## Test workflow

1. Open **ACL Rehab Test** and pick a photo or take one.
2. Choose injury side/type, matching the same context for both models.
3. Optionally enter an independently verified reference angle (0–180 degrees).
4. Review and enable the photo-analysis consent toggle.
5. Tap **Compare both models**, or run either model separately.
6. Repeat on the same image to inspect consistency. Export session results before closing the app.

Both requests use the same image preprocessing: JPEG at 80% quality, maximum dimension 1024.
Opus is called through the existing production function; Gemini uses the private test function.
The test photo goes to both model providers when comparing both.
Errors remain visible independently, with no silent fallback from one model to the other.
Compare errors against verified reference angles, not merely agreement between models.
The Gemini `confidence` field is zero for interface compatibility, not a calibrated accuracy score.
Neither model currently returns measured joint coordinates from these cloud endpoints.

Results exist only in memory; **Share session results** exports text in CSV format without the photos.
Record several independently verified images across relevant angles and capture conditions before
making a production model decision. No claim of improved accuracy has been established.

## Stop testing

Remove the tester UID from the allowlist and redeploy only the test function to disable access.
The App Store app and its production function require no rollback because testing does not modify them.

## Verified setup status

- TypeScript build and all seven request/response/access tests passed.
- The Debug iOS app compiled successfully for a physical-device architecture without signing.
- Release build settings retain `com.twintipsolutions.ACLRehabTracker` and exclude `GoogleService-Test.plist`.
- The new test function is deployed. Live calls returned `UNAUTHENTICATED` (401) without a token
  and `PERMISSION_DENIED` (403) for a fresh non-allowlisted anonymous account, which was then deleted.
- A minimal non-photo Vertex AI request confirmed project access to Gemini 3.8 Flash.
- The tester allowlist is disabled pending installation and collection of the phone app's UID.
- Signing/installing on the paired iPhone requires refreshing the Apple Developer login in Xcode.
- End-to-end photo comparison on the phone and measurement accuracy remain unverified.
