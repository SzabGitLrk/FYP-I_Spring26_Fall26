# Unreleased (17 Nov 2026): logo, one voice for camera and navigation

- **Logo and icon.** The EYRIS logo is on the login screen, and the emblem (no lettering) is on the home screen
  and is the launcher icon. The app is named "EYRIS" on the phone.
- **Battery screen removed**, with its tab, quick tile, voice command and the `battery_plus` dependency.
- **Camera and navigation speak through one shared voice** (`lib/services/speech_hub.dart`). Before, route
  directions ("turn left") stopped whenever the camera was open: the two screens each had their own text-to-speech,
  and the engine drops a sentence that is said while it is busy. Now a close obstacle interrupts a direction (which
  is repeated afterwards), a direction cuts routine camera chatter off, and "Path clear" is skipped while anything
  is being spoken. Navigation and the camera are separate tabs that both stay alive, so directions keep playing
  with the camera tab open. Do not enable `awaitSpeakCompletion` on that engine: it makes the plugin discard speech.
- 10 new tests in `test/speech_hub_test.dart` (51 in total).

# EYRIS 1.0.6: open drains, dark frames (15 Oct 2026)

The client sent videos of open gutters and broken drain slabs where the app said "Path is clear", and an ESP32
screen recording (249.mp4) with mistakes indoors. None of the models knew open drains. The hazard model
(`eyris_hazard.tflite`) now has a fourth class, **Open drain**: open manholes, missing or broken drain slabs,
open drain channels.

## Result

Test photos the model never saw during training, run through the app's own pipeline:

| | Phone camera: right of reported | ESP32 frames: right of reported | Found (phone / ESP32) | 1.0.5 |
|---|---|---|---|---|
| Open drain | 70 of 75 (93%) | 61 of 65 (94%) | 70 / 61 of 111 (63% / 55%) | not detected |
| Speed breaker | 371 of 386 (96%) | 365 of 386 (95%) | 371 / 365 of 428 (87% / 85%) | 95% / 92% right, 85% / 83% found |
| Pothole (road photos) | 211 of 231 (91%) | 186 of 202 (92%) | 211 / 186 of 513 (41% / 36%) | 91% / 94% right, 41% / 35% found |
| Standing AC | 4 of 4 | 4 of 4 | 4 of 11 | 5 of 5 right, 5 of 11 found |

- **"Path clear" is held back near a drain.** A weaker open-drain box (confidence 0.35 to 0.73) is not named, because
  it would break the 9-in-10 rule, but while it shows up the app says "Path unclear, move slowly" instead of
  "Path clear". With this, 76% of drains (phone) and 74% (ESP32) hold back "Path clear". On test photos without
  a drain, this happens on 0.8% / 0.7% of photos.
- When an open drain is named, the app beeps once and says "Caution. Open drain ..." at any distance. It does
  not say "Path clear" for 4 seconds after.
- **Dark frames:** in black ESP32 frames the models made up a person and a wall. A frame that is too dark (average
  brightness under 50 of 255 and almost nothing bright in it) is no longer analysed. The app says "Too dark to
  see, move slowly".

Weak points:

- **New drains:** about 6 in 10 drains are named and 3 in 4 hold back "Path clear" (public test photos; 15 of 20
  broken-slab drains from Bangladesh, which look like the client's). A model trained without one of the client's
  videos found nothing in that video, so a drain that looks unlike everything in training can still be missed.
- **The client's videos:** the drains in the 6.33 PM videos are now found in the frames where they are in view,
  but those videos were used for training. The first video (5.51.55 PM) was kept out. The sun on the filmed phone
  screen hides the drain in most frames. No frame reaches the reporting confidence, and 10% hold back "Path
  clear". The real test is the app pointed at a drain, without a screen in between.
- **Pothole:** closed manhole covers are sometimes taken for potholes: 19 of 221 cover photos. The 1.0.5 model did
  this on 39 of them; it was not measured then. Counting those photos, "right of reported" for pothole is 84%.
- **Standing AC:** still needs the 60 to 100 client photos asked for in 1.0.5. 4 of 11 versus 5 of 11 is one photo.
- **ESP32 without the sensor:** a plainer view is needed before the app says "Wall" (variance under 300 instead of
  500), because the camera gives flatter frames. A heap of clothes was called a wall. This change was not
  measured.
- Not yet tried on a phone or on the ESP32 board.

## What changed

- `assets/models/eyris_hazard.tflite` + `labels_hazard.txt`: 4 classes. `hazardModel` in
  `lib/services/detection_models.dart`: pothole 0.60 (was 0.55; same behaviour on road photos), speed breaker 0.35,
  AC 0.60, open drain 0.73. `cautionThresholds`: open drain 0.35.
- `DetectorSpec.cautionThresholds`, `YoloDetection.hint`, `combineDetections` and
  `YoloDetectionService.weakSightings` (`lib/services/yolo_detection_service.dart`): weak sightings are kept apart
  from what is reported.
- `lib/screens/camera_screen.dart`: drain beep and memory, weak sightings, dark-frame check, ESP32 frames are
  offered to detection every frame (detection itself is still at most twice a second), ESP32 wall limit.
- `scene_describer.dart`: "Open drain" is a ground hazard, always spoken with "Caution."
- `distance_estimator.dart`: open drain is ranged from where it meets the ground. The ultrasonic sensor no longer
  replaces the distance of a pothole, speed breaker or open drain, because its beam passes over them.
- Version 1.0.6+12. `flutter test`: 41 tests pass (5 new). `flutter analyze lib test`: only the old style note.

## Training data (open drain)

| | Distinct photos (train) | Test photos | Source |
|---|---|---|---|
| Open manholes | 128 + 74 + 171 + 13 | 35 + 17 + 33 + 5 | Kaggle: sabidrahman/pothole-cracks-and-openmanhole, amandapriyashantha/manhole-detection-dataset (CC BY 4.0), cubeai/manhole-for-yolov8, deeppratap/manhole-detection (CC BY 4.0) |
| Broken slabs, open chambers | 82 | 20 | Mendeley Data 10.17632/7zzcmv2wz7 (Bangladesh, CC BY 4.0); boxes drawn by eye |
| Client videos | 20 frames | (5.51.55 PM kept out) | WhatsApp videos of 15 Oct |
| No drain | 1,068 closed covers, 130 ESP32 room frames | 221, 33 | the sets above, 249.mp4 |

Each drain photo is used 3 times in training. Scripts in `training/`: `remote_zip.py` (single files from a remote
zip), `mendeley_manholes.py`, `hazard_autobox.py drain`, `box_sheets.py`, `drain_boxes.py`, `client_drafts.py`,
`screen_frames.py`, `video_frames.py`, `contact_sheet.py`, `build_hazard_dataset.py`, `train_hazard.py`,
`export_scene.py --name hazard --size 416`, `hazard_eval.py`, `hazard_table.py`, `hazard_compare.py`,
`hazard_errors_by_source.py`, `drain_caution.py`. Figures: `training/hazard_report.json`.

---

# EYRIS 1.0.5: potholes, speed breakers and standing ACs (15 Oct 2026)

The client reported that standing ACs, speed breakers and potholes were not detected. A fourth model,
`eyris_hazard.tflite`, was trained for these three objects only. It runs on every second frame, alongside
the road model.

## Result

Test photos the model never saw during training, run through the app's own pipeline:

| | Phone camera: right of reported | ESP32 frames: right of reported | Found (phone / ESP32) | Before |
|---|---|---|---|---|
| Speed breaker | 363 of 382 (95%) | 355 of 384 (92%) | 363 / 355 of 428 (85% / 83%) | 1 of 128 found |
| Pothole | 212 of 233 (91%) | 177 of 189 (94%) | 212 / 177 of 513 (41% / 35%) | 13 of 244 found (5%) |
| Standing AC | 5 of 5 | 5 of 5 | 5 of 11 | 3 of 141 found |

On the 1,297 test photos that hold none of the three (rooms, streets, everyday objects) the model raised 2
false alarms through the phone camera.

Weak points:

- **Standing AC:** only 62 usable photos of standing ACs exist for training, and 11 for testing. "5 of 5
  right" is too small a sample to prove 90%. A tall dustbin standing on its own looked like an AC before
  the last round of training; it is now below the threshold. **Ask the client for 60 to 100 phone photos of
  standing ACs** (different homes, shops and showrooms, 1 to 4 metres away). With those the AC can be
  retrained and measured properly.
- **Pothole:** 4 of 10 potholes are found, against 1 of 20 before. Most "wrong" potholes are other road
  damage, such as cracks and patches, which is still a hazard.
- **Speed breaker:** trained on Indian streets (SBP-YOLO data), close to Pakistani roads. Unmarked,
  unpainted speed breakers are the least covered case.
- Not yet tried on a phone or on the ESP32 board. The phone now runs four models, and their speed has not
  been timed.

## What changed

- New: `assets/models/eyris_hazard.tflite` + `labels_hazard.txt` (YOLOv8s, 416 px input). `hazardModel` in
  `lib/services/detection_models.dart` gives pothole 0.55, speed breaker 0.35, AC 0.75.
- `applySceneRules`: boxes from the hazard model are checked by shape only (a speed breaker is wider than
  tall, a standing AC taller than wide). The old position rules threw away close-up potholes and speed
  breakers higher up in the view. They still apply to the other models.
- Version 1.0.5+11. `flutter test`: 36 tests pass (2 new: hazard-model rules, hazard-model output decoded
  like the Python reference).

## Training data

| Object | Photos (train / test) | Source |
|---|---|---|
| Pothole | 1,647 / 276 | RDD2022 (already used by the road model), Roboflow potholes set (CC BY 4.0) |
| Speed breaker | 2,305 / 389 | SBP-YOLO speed bump set (github.com/chuanqi1997/SBP-YOLO) |
| Standing AC | 51 / 11 | Objects365 and Wikimedia Commons; each box checked by eye |
| None of the three | 5,088 / 1,297 | ADE20K rooms and streets, Open Images, Objects365 photos with wall ACs |

Scripts in `training/`: `objects365_ac.py` (fetches the AC photos), `build_hazard_dataset.py`,
`train_hazard.py`, `export_scene.py --name hazard --size 416`, `hazard_eval.py collect / pick / report`,
`hazard_table.py`, `hazard_errors.py`. Figures: `training/hazard_report.json`.

---

# EYRIS: 9 of 10 reported objects are right (14 Oct 2026)

The request: when the app says it sees something, it must be right at least 90% of the time, with the
phone camera and with the ESP32 hardware.

## Result

Share of reported objects that are right, on labelled test photos the models were not trained on:

| | Before | Now | Now, thresholds picked on half of the photos and judged on the other half |
|---|---|---|---|
| Phone camera | 84% (1,336 of 1,582) | 94.9% (1,642 of 1,731) | 92.2% |
| ESP32 camera (imitated frames) | not measured | 94.6% (1,028 of 1,087) | 91.4% |

The last column is the fairer figure, because it never judges a threshold on the photos it was picked from.

The price is that the app now stays silent when it is not sure. It finds fewer objects per frame than before,
most of all potholes, trees, dustbins, trucks and chairs (last column of the table below). People, stairs,
beds, laptops and backpacks are found as often as before.

**Not yet tested on a phone or on the ESP32 board.** The ESP32 figures come from test photos reduced to what
the firmware sends (640 x 480 JPEG, softer, noisier, less contrast). No APK was built: this PC has no JDK or
Android SDK.

## What changed

1. **The scene model was trained to the end.** It had been stopped after 6 of 16 passes. Finished, it is
   better on the held-out photos (average precision 0.34 to 0.39). New `assets/models/eyris_scene.tflite`.
2. **Two confidences per label instead of one.** A model reports an object alone only when it is very sure.
   When it is less sure, the object counts only if a second model sees the same thing in the same place. Two
   models agreeing are right more often than one model alone, so this keeps mistakes down without losing as
   many objects (`confirmAcrossModels` in `lib/services/yolo_detection_service.dart`).
3. **Every confidence is measured.** `training/tune_precision.py` picks, per label and model, the lowest
   confidence at which at least 9 of 10 detections are right through both cameras, with a margin for labels
   that have few test photos. The values are in `lib/services/detection_models.dart`.
4. **Speed breaker was a road detector.** It put a box over the whole road and called it a speed breaker on 95
   of 176 ordinary road photos. Only a small strip across the road counts now. After that it finds 1 of 128
   real speed breakers, so this label is effectively off until a model is trained on labelled photos.
5. **Hardware mode: "Obstacle", not "Wall".** When the ultrasonic sensor sees something closer than 0.8 m
   and the camera recognises nothing, the app used to say "Wall". The sensor cannot know that, so it now says
   "Obstacle" with the sensor distance.

## Accuracy per label

Rooms and streets are ADE20K photos in which every object is labelled; general photos are Open Images and
road photos. A detection is right when its box covers a labelled object of that name.

| Label | Phone camera: right of reported | ESP32 frames: right of reported | Phone: objects found (rooms and streets, general photos) |
|---|---|---|---|
| Person | 292 of 319 (92%) | 287 of 310 (93%) | 119 of 575, 173 of 357 |
| Car | 322 of 329 (98%) | 72 of 75 (96%) | 265 of 1495, 57 of 185 |
| Bike | 91 of 96 (95%) | 81 of 87 (93%) | 12 of 129, 79 of 158 |
| Truck | 21 of 21 (100%) | 19 of 19 (100%) | 1 of 53, 20 of 55 |
| Bus | 36 of 37 (97%) | 36 of 37 (97%) | 1 of 7, 35 of 65 |
| Pothole | 13 of 13 (100%) | 14 of 14 (100%) | 13 of 244 |
| Tree | 110 of 118 (93%) | 11 of 11 (100%) | 108 of 2144, 2 of 80 |
| Pole * | 7 of 7 (100%) | 6 of 6 (100%) | 2 of 90, 5 of 82 |
| Traffic sign | 18 of 18 (100%) | 18 of 18 (100%) | 0 of 147, 18 of 59 |
| Chair | 309 of 328 (94%) | 70 of 74 (95%) | 282 of 1626, 27 of 143 |
| Table | 70 of 72 (97%) | 65 of 67 (97%) | 45 of 149, 25 of 98 |
| Door * | 17 of 22 (77%) | 14 of 18 (78%) | 10 of 73, 7 of 82 |
| Stairs * | 13 of 13 (100%) | 12 of 12 (100%) | 2 of 17, 11 of 41 |
| Wall | 42 of 44 (95%) | 47 of 49 (96%) | 42 of 463 (only walls across the view are reported) |
| Bed | 64 of 70 (91%) | 61 of 66 (92%) | 22 of 26, 42 of 61 |
| Sofa | 49 of 51 (96%) | 49 of 51 (96%) | 13 of 24, 36 of 117 |
| Bottle | 37 of 38 (97%) | 38 of 39 (97%) | 0 of 177, 37 of 68 |
| Dustbin | 12 of 12 (100%) | 12 of 12 (100%) | 0 of 120, 12 of 29 |
| Backpack | 47 of 48 (98%) | 47 of 49 (96%) | 3 of 29, 44 of 65 |
| Laptop | 53 of 55 (96%) | 49 of 51 (96%) | 4 of 20, 49 of 65 |
| Footpath * | 17 of 18 (94%) | 18 of 20 (90%) | 17 of 52 |
| Fan | 2 of 2 | 2 of 2 | 2 of 4 |
| AC | none reported | none reported | 0 of 12 |
| Speed breaker | none reported | none reported | no labelled photos |

\* Few detections in the test photos, so the percentage is uncertain.

Weak points, stated plainly:

- **Door** is the one label below 90% by box matching (77% and 78%). Every detection counted as wrong was
  looked at: on the phone set 4 of 5 show a real door that the photo's labels miss or box differently (a door
  at the frame edge, an open door seen edge-on, a doorway) and 1 is a window wall; on the ESP32 set all 4 are
  doors or doorways. By eye that is 21 of 22 and 18 of 18. Doors are found in about one frame in nine.
- **Potholes** are announced far less often than before: 13 of 244 found, was 54. A missed pothole is a
  danger for a blind user, so this is the cost of the 90% rule that deserves a decision. Lowering `Pothole`
  in `detection_models.dart` from 0.77 to 0.45 brings back the earlier behaviour: about 54 of 244 found,
  79% right.
- **AC and speed breaker** do not work. Both need 200 to 300 labelled photos from the client to train on.
- **Pole, stairs, footpath, fan**: too few test photos to be sure of the percentage.
- In the cross-check several labels came out a little below 90% (tree, sofa, bottle and traffic sign at 87 to
  89%; chair at 87% on ESP32 frames), and pole and stairs well below it (71% and 79%) on a dozen detections
  each.
- The blank-surface check that says "Wall" when the phone camera sees a plain surface with nothing recognised
  is not covered by these measurements.

On crops from the client's videos (a phone filmed by another phone, so only a rough check) the app no longer
says "Table" for the ceiling, the wall, the stairs or the door. It names nothing in them: the plain wall
scored just below the new threshold (0.66 against 0.72) and only one of the models recognised the door.

## To do on the build PC

```
flutter pub get
flutter test
flutter build apk --release
```

Then walk the same route as in the videos with the phone camera and with the ESP32, and note what is said.

## Tests

`flutter test`: 34 tests pass (2 new: belief in one model alone, agreement between models).
`dart analyze lib test`: one old style note, no errors.

## Files

Changed: `lib/services/detection_models.dart`, `lib/services/yolo_detection_service.dart`,
`lib/screens/camera_screen.dart`, `assets/models/eyris_scene.tflite`, `assets/models/labels_scene.txt`,
`test/detection_test.dart`, `test/fixtures/`, `training/app_sim.py`, `training/check_config.py`,
`training/make_config.py`.
New: `training/tune_precision.py`, `training/manual_thresholds.json`, `training/resume_scene.py`.
Removed: `training/final_config.py` (it wrote the old thresholds back).
The previous scene model is kept in `D:\dev\eyris_work\runs\scene_c_backup_ep6`.

## Rebuilding the models and thresholds

Scripts are in `training/` (they expect the data folders used on the development PC; paths are at the top
of each file): `ade_extract.py`, `build_scene_dataset.py`, `train_scene.py` (or `resume_scene.py`),
`export_scene.py`, `export_world.py`. Then, once per camera (`SIM_CAMERA=phone`, then `SIM_CAMERA=esp32`),
`app_sim.py collect`; then `tune_precision.py --crosscheck`, `tune_precision.py --write`,
`check_config.py --dart` to print the values for `detection_models.dart`, and
`check_config.py lib/services/detection_models.dart` to confirm the app uses them.

---

# EYRIS 1.0.4: detection fixes and new classes (12 Oct 2026)

## What was wrong

On labelled test photos the old set-up behaved like this:

| Old part | Finding |
|---|---|
| Main model (`eyris_20_classes_float32.tflite`, YOLO-World at 320 px) | Thresholds were set almost to zero (table 0.07, chair 0.08), so weak guesses were shown as objects. On fully labelled room photos its average precision was 15% for doors and 6% for stairs. |
| `door.tflite` | Never fired: best score on door photos was 0.15, the app needed 0.40. |
| `stairs.tflite` | Its output was read in the wrong format, so every confident detection was thrown away. Read correctly, it fires on doors, floors and sofas as well. |
| `pothole.tflite` | Found 4% of potholes on road photos and raised a false pothole on 2 of every 100 indoor and street photos. |
| Frame preparation | The tall phone frame was stretched into a square before detection. |
| "Path is clear" | Spoken whenever nothing was recognised, including in front of a wall or a closed door. |

The phone in the client's videos runs a build whose camera screen (direction list, "Table closest") is not
in this source folder, so the exact cause of "Table" on every surface in that build could not be traced.
The app now refuses to load a model whose class count does not match its labels file, which is the usual
cause of every object getting the wrong name.

## What changed

Three models (which labels each one reports has since changed, see above):

| Model | Runs |
|---|---|
| `eyris_scene.tflite` (YOLOv8s trained on 14,504 fully labelled room and street photos) | every frame |
| `eyris_world.tflite` (YOLO-World, rebuilt with better prompts) | every second frame |
| `eyris_road.tflite` (YOLOv8s trained on road photos) | every second frame |

New classes: **Speed breaker**, **Footpath**, **AC** (standing and wall units; "Fan" is also added).

Other changes:

- Frames keep their proportions (letterbox) instead of being stretched.
- Every object is listed with side and distance: "Door straight ahead · about 2 meters". The voice says the
  nearest objects, for example "Door straight ahead, about 2 meters. Chair far left, about 3 meters."
- "Path clear" is no longer said in front of a plain surface; the app says "Wall" or "Path unclear, move
  slowly".
- `door.tflite`, `stairs.tflite`, `pothole.tflite` and `eyris_20_classes_float32.tflite` are no longer
  bundled. They can be deleted from `assets/models`.
- Speed of the three models on the phone has not been timed.
