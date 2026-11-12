# Technical notes and limits

## Full-resolution scene

Hookshot 2.1.0's guest image for build `e0f3ccfa` caps the scene at
3840×2160. At 5120×1440 output that leaves the scene and depth buffer smaller
than the swapchain, and the DLSS bridge can't use the depth.

`tools/patch_scene.py` changes the width at file offset `0x03f78570` from 3840
to 5120 and keeps the 2160 height cap. It runs on the installation's copy of
`image.bin`, accepts only the known original or already-patched image, and
checks the result hash:

| Image | SHA-256 |
| --- | --- |
| Original | `f77dd8d6448b4204ae2be6c91872f6a3ca4ae64fc6566e7b3ed0c3b908d98ee2` |
| Patched | `8aff5492abc56fd237f09d7526d4c346e9a80911f41ba510b600ace08c6c5872` |

`HOS_SCENE_NATIVE=1`, `HOS_DYNRES=0` and `HOS_OUTPUT_RES` then render the
scene at the full output size. Widescreen support itself comes from Hookshot.

## Quality settings

Both presets ([`quality.ini`](../presets/quality.ini),
[`quality-env.txt`](../presets/quality-env.txt)) use:

- a custom quality preset (`quality_preset=0`), because Hookshot's named Ultra
  preset can turn on frame generation;
- 16× anisotropic filtering, textures up to 16384 px, RGBA8 ASTC decoding
  instead of re-compressing to BC3;
- Lanczos upscaling with 20% sharpening;
- `HOOKSHOT_OCCLUSION_OFF=1`, a workaround for the renderer's approximate
  visibility queries;
- `RX_VK_PRECOMPILE=0` and `RX_VK_NO_WARM=1`, which skip the long shader
  warm-up. Shaders compile on first use instead, so new scenes can hitch once.

`-TextureBudgetMB` sets `RX_VK_VRAM_MB`; by default Hookshot picks the budget.

## Ultra startup

The [DLSS 5 bridge](https://github.com/NIGos/dlss5-bridge) runs a synthetic
DLAA session using depth from ReShade and motion from NVIDIA Optical Flow,
passing frames through D3D11/D3D12 and back to Vulkan. RenoDX evaluates NGX
Feature 18 (neural rendering) on that session. This is a community
integration, not the game's own DLSS path, so Hookshot's `dlss=0` stays off.

The bridge can create its first DLAA session before RenoDX has hooked D3D12.
To fix that, `Launch.ps1`:

1. waits for `D3D12 NGX hooks installed` in `bin/ReShade.log` and a delivered
   frame in `bin/dlss5-bridge.log`;
2. if no Feature 18 evaluation has happened yet, shrinks the game window by
   20 px and restores it, which recreates the swapchain and the bridge
   session, this time hooked;
3. waits for at least 60 successful Feature 18 evaluations at the selected
   resolution, and reports an error if they don't appear within 8 minutes.

The previous run's logs are kept as `*.previous` so old success lines can't be
mistaken for the current run.

Other details:

- `vk_sync=2` in `dlss5-bridge.cfg` pipelines one frame, adding a frame of latency.
- `ngx_loader=1` keeps the driver's own NGX loader.
- The ReShade Vulkan layer is enabled only for the game process, via
  `VK_IMPLICIT_LAYER_PATH` and `RESHADE_BASE_PATH_OVERRIDE`. No registry or
  system-wide layer is installed. This needs Vulkan loader 1.3.295 or later,
  and the loader ignores these variables for elevated processes.
- `ZeldaDepthTap.fx` only exposes the depth buffer to ReShade; it writes no color.

Optical flow is less precise than the game's own motion vectors, so Ultra can
soften small text or smear dense foliage, and neural rendering can change fine
details. Native is there if that bothers you.

## Why frame generation is off

FSR 3.1 frame generation combined with the DLSS chain caused visible flashing.
Without the bridge, FSR frame generation still produced doubled HUD and
character images. With frame generation off, motion was clean. Neither preset
enables it.

## Damaged NUP resources

The NUP used during development has three damaged compressed textures.
Hookshot replaces them with neighboring textures from the same game files.
Two (Fairy Fountain and Water Temple normal maps) fit their size limits. The
third, `RBake_Scene_GanonStage_G_2_1_d0_t0.bntx.zs`, gets a replacement of
9,101,416 bytes against a size-table limit of 6,934,920. That late-game area
has not been tested. A clean dump should not have this problem.

## Tested setup

- Windows x64, Core i9-14900K, RTX 4090, NVIDIA driver 621.14, 5120×1440 display.
- A fresh install from the NUP took about 26 minutes (627 s of compilation).
- Both shortcuts started the game at 5120×1440 and loaded a save in Kakariko
  Village. Ultra confirmed Feature 18 at 5120×1440.
- Ultra ran at about 40–42 FPS in Castle Town; the on-screen counter showed
  about 60 FPS for Native and 46 FPS for Ultra in Kakariko.

Not tested: other GPUs or drivers, finishing the game, every keyboard prompt.

Locally built executables can differ in hash from build to build; the inputs
are pinned, not the outputs.
