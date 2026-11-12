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
  and preserving unrelated existing shortcuts. The GUI bootstrap's PowerShell
  child returned a null console handle. A separate PowerShell 5.1 regression
  checks launching without an explicit installation path from a different
  working directory.

## Integrated installation and game test — 12 November 2026

The installer completed a **fresh build from the NUP** in an independent
directory, using the pinned downloaded toolchain and a separately supplied NR
runtime. Total elapsed installation time was approximately **26 minutes**;
compilation took **627 seconds with zero failed files**. Both scene-cap patches,
the regenerated prompt mod, the Ultra dependencies and the shared profile were
created by the public scripts. No precompiled game or shader cache was copied
from the older working installation.

Both generated GUI shortcuts started the real game at **5120×1440**. The test
loaded a copied save in **Kakariko Village** in both presets and inspected the
rendered scene, character and R/F keyboard labels. Native's first scene initially
showed incomplete shaders, then settled into a complete image. The scene's
settled native log reported zero queued shader jobs and zero skipped draws.

Ultra's launcher observed the hooks, resized the exact game window once,
observed Vulkan runtime teardown and restored fullscreen. It confirmed
**Feature18 count=60 at 5120×1440**; Bridge then logged more than 600 delivered
Vulkan frames. The copied scene displayed correctly after activation. This run
also exercised cleanup of an inherited ReShade-disable setting. FSR and frame
generation remained off. Both sessions exited gracefully.

The on-screen counter showed about 60 FPS in this native view and about 46 FPS
in Ultra. These are scene-specific observations, **not a new matched-duration
benchmark or a sustained 60 FPS claim**. Comprehensive keyboard navigation and
motion artifact testing were not repeated for this package.

The original user's **14 save files remained byte-identical** to the pre-test
hash snapshot. Test play used only the installation's copied profile. Source-only
publication checks found no game files, keys, credentials or private paths.

Fresh executables can have different hashes because they are built locally.
Acceptance here combines pinned inputs, the exact guest-image patch guard and
real-game behavior; it is not a claim of bit-for-bit reproducible PE binaries.

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
