# Zelda OOT PC Presets

This public repository contains source-only installation recipes for a user's
own NUP. It must never contain game images, extracted game assets, saves,
keys, proprietary DLLs, downloaded archives, or local runtime logs.

- Read [README.md](README.md) and the relevant document in `docs/`.
- Preserve the pinned dependency hashes and guest-build guards. An upstream
  update requires a separate build and in-game validation before changing pins.
- Keep Native free of DLSS/FSR/frame generation. Ultra uses the documented NR
  path with frame generation disabled. Do not silently fall back on activation failure.
- Install in a new directory. Never overwrite a user's save profile or alter
  an unrelated installation, system Vulkan layer registration or GPU driver.
- Keep tooling compatible with Windows PowerShell 5.1; no administrator,
  Codex, agent-desktop or globally installed Python is required for users.
- Run `tests/Test-Package.ps1` and verify the changed runtime behavior as needed.
  A build or Feature18 count alone does not prove sustained gameplay or 60 FPS.
- Never turn private paths, diagnostic logs or screenshots of the desktop into
  public documentation. Review the exact staged files before publishing.
