# Accurate mode accuracy harness

Runs the iOS app's own `KneePoseEstimator` (Apple Vision, on this Mac) over photos with a known
knee angle and reports the error. Nothing here calls a server.

```sh
accuracy/knee_math_test.sh                                  # unit checks for the angle math and leg choice
accuracy/knee_pose_run.sh accuracy/fixtures/coco accuracy/results/coco.json
python3 accuracy/score_coco.py accuracy/results/coco.json
```

Fixtures and results are git-ignored because they are photos of people.

## Fixtures

- `fixtures/coco/` and `fixtures/coco_truth.json`: 68 single-person photos from COCO val2017 with
  hand-labelled hip, knee and ankle, up to 12 per 25-degree band of knee flexion. Rebuild with
  `python3 accuracy/select_coco.py /path/to/person_keypoints_val2017.json`. These are everyday and
  sports photos from every camera angle, so they are harder than a posed side-on rehab photo.
  The "truth" is the 2D angle of the hand labels, which are themselves a few degrees noisy.
- `fixtures/rehab/`: rehab-style photos named `<flexion|extension>_<angle|x>_<note>.jpg`. The ones
  used so far are AI-generated (Gemini) and the angle in the name is an estimate by eye.
- `fixtures/bad/`: photos Accurate mode should refuse or warn about (knee close-ups, front view).

## Results, 2026-11-22 (Xcode 26.2 Vision, 2D body pose)

COCO, 68 photos: a complete leg was found in 64.

| Set | Photos | Median error | Within 5° | Within 10° | Worst |
|---|---|---|---|---|---|
| All found | 64 | 4.7° | 52% | 77% | 68° |
| Confidence 0.3 or higher | 48 | 3.9° | 60% | 85% | 29° |
| Confidence 0.5 or higher | 33 | 3.6° | 61% | 82% | 29° |

- Mean signed error is -1.4°, so there is no real bias toward more or less bend.
- The large misses are almost all low-confidence results, which is why the app shows a "check the
  dots" note below 0.3 and lets the user drag any point.
- Vision's 3D body request was much worse for the knee (median 17.5°) and is not used.
- Trying the photo turned a quarter turn each way helps people who are lying down. Doing it for
  every photo, even confident ones, scored slightly worse (median 5.2°), so it only happens when
  the upright result is below 0.5.

Rehab-style photos (7): standing 3°, lying straight 3°, seated at a right angle 84°, heel slide 119°,
bent knee lying down 101°, sitting on the floor 128°: the dots sit on the hip, knee and ankle in
each. Lying face down read 135° with the hip dot too high (on the waistband); the true angle is
nearer 100°. That photo's confidence was 0.23, so the app flags it.

Bad framing (3): both knee close-ups return "no complete leg", which the app turns into the retake
screen. A front view is measured (it reads 2° for a knee lifted to about 90°), which is wrong:
only the AI photo check can catch that case.

## Which side faces the camera, 2026-11-22

The 7 rehab-style photos plus the front view, each also mirrored (16 photos). Checked by eye:

- 6 clear side views and their 6 mirror images: all 12 correct, and every mirror image flipped.
- Lying flat with both legs straight: "can't tell" both ways (no bent knee, face pointing up).
  The app then shows the softer "couldn't tell which side" note.
- Front view and its mirror: "can't tell", as it should be. Before the shoulder-width rule the
  mirrored one was read as a side view.

This is a small, AI-generated set. It has not been run on real patients or on selfie-camera photos;
a mirrored photo would report the opposite side.

One leg-choice miss showed up here that is not new: in the mirrored heel-slide photo the straight
leg was measured (11 instead of about 119), most likely because the bent leg's ankle was not found.

## Other tools

- `accuracy/render_chooser.sh <outDir>` renders the method chooser and the Measure-tab method row
  to PNG from the app's own SwiftUI views, on the Mac. Useful when no simulator is available.
- `ios/ACLRehabTrackerUITests/AccurateModeUITests.swift` drives the app in the simulator: the
  chooser, an Accurate result with a dragged dot, the close-up retake screen, a failed photo check,
  the Standard photo flow from a fresh install, and saving both kinds and seeing them in History.
  It needs `TEST_RUNNER_PHOTO_DIR` with `seated.jpg` and `closeup.jpg`; the last two tests call the
  test Firebase project and only run with `TEST_RUNNER_ACL_NETWORK=1`. Grant the camera first or its
  alert covers the screen: `xcrun simctl privacy booted grant camera com.twintipsolutions.ACLRehabTracker.test`.
  Also covered: the pose guide, the self-timer count and cancel, and the wrong-side and
  unknown-side notes. All ten passed on 2026-11-22 (iPhone 17 simulator, iOS 26.2).
- Debug launch arguments: `-startTab Measure`, `-measureMode accurate` (pins the mode for that run),
  `-resetMeasureMode YES`, `-showMeasureModeSheet YES`, `-testPhoto <path>`,
  `-forceCheckMessage <text>` and, simulator only, `-testKeypoints hx,hy,kx,ky,ax,ay` with `-testFacing left|right|unknown`. Also
  `-testInjuredKnee left|right` (stands in for the saved profile) and `-resetSelfTimer YES`.

## Vision does not run in the simulator

`VNDetectHumanBodyPoseRequest` fails in the iOS 26.2 simulator with Vision error 9 ("Unable to setup
request"), so every photo there ends on the "Couldn't measure this photo" screen. The UI tests
therefore hand the app the points this harness finds for `seated.jpg` on the Mac (`-testKeypoints`).
The simulator tests prove the screens, the angle maths, dragging and saving; the detection itself is
only tested here on the Mac, and on a real phone not at all yet.

## What is not measured here

- Detection on a real iPhone. Simulator tests use points found on the Mac (see above).
- The self-timer on a real phone: that the beeps are loud enough across a room, that they play
  with the ring switch on silent, and that the photo fires at zero. The simulator has no camera, so
  the tests only check the count and cancelling.
- Real patients with a goniometer reading. The numbers above compare against hand-labelled joints
  and estimates by eye, not a clinical measurement.
- The `checkKneePhoto` prompt against real photos. It is unit tested but has not been run on Vertex.
