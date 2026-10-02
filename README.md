# SignBridge AI v0.6

Arabic-first Android MVP for Palestinian Sign Language (PSL).

## Added in v0.6
- Palestine Sign Pack metadata and verification policy.
- Per-unit provenance / verification status.
- Android text sharing: Share → SignBridge opens the translation screen with the shared text.
- Explicit separation between software demo motions and verified PSL.

> No demo motion is claimed to be a verified Palestinian sign. Production sign motions require licensed source data and Deaf/community review.

# SignBridge AI — MVP v0.3

Arabic-first Flutter prototype for a privacy-conscious sign-language translation assistant.

## v0.3
- Arabic RTL UI.
- Text normalization and a constrained translation prototype.
- Sign units: verified/demo motion, fingerspelling fallback, unavailable.
- Avatar Player prototype with play/pause/replay/speed/fullscreen and timeline.
- Explicit safety labeling: demo motion IDs are software-test data, not verified Palestinian Sign Language.
- Extensible Sign Pack architecture direction.

## Critical linguistic rule
The application must never fabricate a sign. Production Sign Packs require community/linguist validation and provenance before a motion can be marked verified.

## Next milestone
Replace prototype visual motion cards with a rigged 3D avatar renderer and verified motion clips, then add Arabic streaming speech-to-text.


## v0.4
- Added Arabic live-speech screen using `speech_to_text`.
- Partial speech results feed the same guarded translation engine and avatar timeline.
- Added privacy disclosure in the microphone UI.
- Added Android/iOS permission snippets under `platform_setup/`.
- IMPORTANT: this archive is still source-only; native Android/iOS scaffolding must be generated with Flutter before producing AAB/IPA.
- Demo motion labels remain SOFTWARE TEST DATA, not validated Palestinian Sign Language.

## v0.7 additions
- Image translation screen: camera or gallery selection.
- On-device OCR attempt with explicit Arabic accuracy warning.
- Mandatory review/edit step before translation to PSL pipeline.
- Images are not uploaded by SignBridge in this MVP path.
- Version 0.7.0+7.

## v0.8 — Avatar Motion Engine
- Added a channel-based motion model for right/left hand, fingers, head/body and facial-expression channels.
- Added interpolation between motion frames and speed-aware playback.
- Added a prototype avatar body renderer to prove the motion pipeline inside Flutter.
- Demo clips are explicitly marked `MOTION DEMO • NOT PSL`; they are not Palestinian Sign Language claims.
- Architecture keeps verified PSL motion assets separate from avatar appearance, so a future realistic 3D avatar can consume the same verified motion clips.
