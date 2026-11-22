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

## Other tools

- `accuracy/render_chooser.sh <outDir>` renders the method chooser and the Measure-tab method row
  to PNG from the app's own SwiftUI views, on the Mac. Useful when no simulator is available.
- `ios/ACLRehabTrackerUITests/AccurateModeUITests.swift` drives the chooser, an on-device
  measurement, the close-up retake screen and a failed photo check in the simulator. It needs
  `TEST_RUNNER_PHOTO_DIR` with `seated.jpg` and `closeup.jpg`. Debug builds also accept
  `-startTab Measure`, `-measureMode accurate`, `-showMeasureModeSheet YES`, `-testPhoto <path>`
  and `-forceCheckMessage <text>` as launch arguments.

## What is not measured here

- The app flow in a simulator or on a phone. On 2026-11-22 the app and the UI tests compiled, but
  the simulator on the development Mac could not install or launch apps (the machine was out of
  memory and swap), so `AccurateModeUITests` has not been run yet.

- Real patients with a goniometer reading. The numbers above compare against hand-labelled joints
  and estimates by eye, not a clinical measurement.
- The `checkKneePhoto` prompt against real photos. It is unit tested but has not been run on Vertex.
