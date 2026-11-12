# Validation record

This package is pinned to Hookshot 2.1.0 and game build `e0f3ccfa`. Tests use
Windows x64, Core i9-14900K, RTX 4090, NVIDIA driver 621.14 and a 5120×1440
display. Other machines, input dumps and later game areas require independent
validation. Source packages contain no test saves or proprietary outputs.

## Reproducibility

- Pinned builder parts downloaded from the release owner and verified by size
  and SHA-256; fresh extraction and the supported NUP probe passed.
- Module and wrapper syntax checked under Windows PowerShell 5.1.
- The prompt generator ran with an empty download cache. Its 35 glyphs and
  10 texture masks produced the same two files as the accepted local prompt mod.
  The ZR label is F and ZL is the right mouse button.
- Ultra dependencies installed into an isolated bin directory from an empty
  cache under Windows PowerShell 5.1. Six binary/manifest files matched the
  previously tested Ultra; text settings matched after line-ending normalization.
- Installer refusal checks protect a nonempty destination, reject missing or
  wrong NR runtimes before creating an installation, and prevent installing
  runtime data into the source checkout. Invalid scene images remain unchanged.
- Launcher tests with a disposable process checked quoted paths, child-only
  environment, stale log isolation, exact-PID resize/restore, activation matching
  and preserving unrelated existing shortcuts. These checks do not prove the
  real game starts correctly.

The integrated fresh NUP build and real-game launch are being checked before
the first public release. This paragraph will be replaced by the observed
result; it is not a completed validation claim.

## Prior in-game evidence for the presets

The earlier working installation loaded Castle Town, rendered scene and depth
at 5120×1440, and confirmed successful NR Feature18 evaluations and Vulkan
frame delivery. A normal shortcut relaunch measured 41.3–41.7 FPS in the
selected Castle Town view. Other warmed 30-second trials measured about
40–42 real frames per second. No generated frames were counted as game FPS.

The README screenshots come from that installation. They show the same camera
position, with different moving NPC/particle states. Native is the same full-size
rendering without the neural bridge. Ultra's screenshots demonstrate its visual
effect, not general accuracy, motion stability in every scene, or 60 FPS.

The user confirmed a clean moving image after FSR and frame generation were
disabled. Full-game completion, every keyboard prompt, other GPUs/drivers and
the damaged late-game texture remain unverified. Read [TECHNICAL.md](TECHNICAL.md)
before treating a successful early scene as a complete playthrough result.
