# Changelog

## Unreleased

- Remove `-ExistingBuild`. It only accepted one specific local build, so every
  install now compiles from the NUP.
- Shorter documentation; `docs/VALIDATION.md` is folded into `docs/TECHNICAL.md`.
- One shared, hash-checked download helper for all installer scripts.

## 1.1.0

- Install Native Quality and Ultra DLSS 5 by default from the supplied NUP.
- Fetch the tested Neural Rendering DLL from a pinned community archive and
  verify both hashes before building the game.
- Keep `-Preset Native` for Native Quality alone and `-NrRuntime` for an
  explicit local copy of the same DLL.

## 1.0.0

- Pinned Hookshot 2.1.0 installation from a user-provided supported NUP.
- Native Quality and optional Ultra DLSS 5 presets with no frame generation.
- Guarded 5120-pixel scene-width fix and regenerated keyboard/mouse prompts.
- Standalone launcher, per-process graphics layer and shared save folder.
- Dependency hashes, source notices, comparison captures and documented limits.
