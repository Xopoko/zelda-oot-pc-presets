# Zelda OOT · PC graphics presets

Two reproducible Windows presets for **The Legend of Zelda: Ocarina of Time
(Switch 2)** through [Hookshot](https://github.com/NotRexed/Hookshot), built
locally from your own supported `.nup`.

**Native Quality** preserves the game's rendering at full display resolution.
**Ultra DLSS 5** adds the tested neural-rendering bridge. Both include
ultrawide support, 16× anisotropic filtering, keyboard/mouse prompts and a
desktop shortcut. FSR and frame generation are disabled in both presets.

> Installation from your NUP downloads the dependencies for both presets.
> Ultra uses a SHA-256 pinned, community-patched `nvngx_dlssnr.dll` with
> Authenticode status `HashMismatch`. [Runtime source and verification](docs/DEPENDENCIES.md#neural-rendering-runtime).

| Native Quality | Ultra DLSS 5 |
| --- | --- |
| [![Native Quality](docs/images/native-preview.png)](docs/images/native-5120.png) | [![Ultra DLSS 5](docs/images/ultra-preview.png)](docs/images/ultra-5120.png) |
| Full-resolution scene, 16× filtering, Lanczos and 20% sharpening | Same base rendering plus neural reconstruction and relighting |

Click either screenshot for the full **5120×1440** capture. Same camera position
at the Castle Town gate; moving characters and particles differ between captures.
The FPS counter in a screenshot is an instant reading, not a benchmark.

## Install

1. Download the repository with **Code → Download ZIP** and extract it, or clone it.
2. Open PowerShell in the extracted repository folder.
3. Run this command to build the game locally and install **both presets**.
   The installer downloads and verifies the pinned dependencies automatically
   from a standard Windows user session.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Nup "D:\Dumps\game.nup" -Destination "D:\Games\ZeldaPresets"
```

Add `-Preset Native` to install Native Quality alone and skip the Neural Rendering
download. If you already have the exact compatible DLL, `-NrRuntime` accepts
its local path. [Install options](docs/INSTALL.md).

The first build can take **30 minutes or longer**. The installer selects the
primary display's physical resolution. For the demonstrated setup, append
`-Resolution 5120x1440 -TextureBudgetMB 12288`. Use that resolution only on the
matching display. The automatic texture-cache budget is more portable; the
12 GiB override was tested on a 24 GiB RTX 4090.

Launch **Zelda Ocarina of Time - Native Quality** or **Zelda Ocarina of Time - Ultra DLSS 5** from the
desktop after installation. Both use the same saves. A brief display resize
during Ultra startup initializes the neural-rendering path automatically.

[Detailed installation, saves and removal](docs/INSTALL.md) ·
[Keyboard and mouse](docs/CONTROLS.md) ·
[Dependencies and licenses](docs/DEPENDENCIES.md) ·
[Fixes and known limitations](docs/TECHNICAL.md) ·
[Validation](docs/VALIDATION.md) ·
[Инструкция на русском](docs/README.ru.md)

## Requirements and scope

- Windows x64, a current Vulkan-capable GPU driver, an SSD and substantial free
  space. Reserve **60 GiB** for the build and two presets; runtime shader caches
  can grow further. 32 GiB RAM or more is recommended for building.
- Your own supported NUP: title `0400486024DEC000`, update `v131072`, game
  `1.1.1`, guest build `e0f3ccfa`. Other versions are rejected before compilation.
- Ultra was tested on **RTX 4090 / driver 621.14** with the exact runtime hashes
  documented in the dependency manifest. Other GPUs and drivers are unverified.
- Fullscreen output up to 5120 pixels wide and 2160 pixels high. The demonstrated
  output is 5120×1440. Cutscenes and HUD keep their intended central proportions.

There is no 60 FPS guarantee. On an i9-14900K / RTX 4090, the earlier working
Ultra setup measured around **40–42 real FPS** at 5120×1440 in the documented
Castle Town view, without generated frames. The public package validation and
its exact scope are recorded in [VALIDATION.md](docs/VALIDATION.md).

Keyboard prompts cover many buttons, including HUD actions and ocarina notes;
some pre-rendered controller diagrams still use Nintendo labels. Full-game
completion and every prompt have not been verified. A damaged resource in the
tested NUP affects an unverified late-game area; see [known limitations](docs/TECHNICAL.md).

## Credits

Built on the work of [NotRexed/Hookshot](https://github.com/NotRexed/Hookshot),
[NIGos/dlss5-bridge](https://github.com/NIGos/dlss5-bridge),
[ReShade](https://reshade.me/), RenoDX, NVIDIA DLSS,
[ARM astc-encoder](https://github.com/ARM-software/astc-encoder) and
[valentderah/totk-pc-recomp](https://github.com/valentderah/totk-pc-recomp).
The prompt generator retains its upstream MIT notices and MacNativeGames credit.
Exact provenance and third-party terms are in the dependency documentation.

The original installer, configuration and patch recipes are MIT licensed.
They were developed with **OpenAI Codex** assistance and checked against the
local game. Screenshots are real game captures; no AI-generated artwork is used.
Nintendo and NVIDIA are not affiliated with this repository. No game, model,
save, key, or precompiled game executable is distributed here.
