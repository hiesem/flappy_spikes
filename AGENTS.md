# flappy_spikes (Flutter + Flame rebuild)

Read `../AGENTS.md` (workspace root) FIRST — it has the full project context,
decisions, machine environment (Flutter/JDK/Android SDK paths), and pending tasks.

Quick facts for this directory:
- Gameplay contract: `SPEC.md` — follow it exactly for any behavior change.
- Gate: `flutter analyze` clean + `flutter test` all green (55 tests).
- Store guide: `SUBMISSION.md`. Task log: `TODO.md`.
- Never commit `android/upload-keystore.jks` or `android/app/key.properties`.
