# Fixes and limits

## Full-resolution scene and depth

The verified Hookshot 2.1.0 guest image for `e0f3ccfa` contains a scene cap of
3840×2160. At a 5120×1440 display output this can leave the scene/depth smaller
than the swapchain, preventing the tested bridge from using matching depth.

`tools/patch_scene.py` changes the width at file offset `0x03f78570` from 3840
to 5120, keeping the 2160 height cap. It accepts only the exact source digest
and verifies the complete resulting digest. It runs on a new installation's
copy. The source NUP and base build are never modified. Reapplying to the
recognized patched image is harmless; all other images are rejected.

| Image | SHA-256 |
| --- | --- |
| Original | `f77dd8d6448b4204ae2be6c91872f6a3ca4ae64fc6566e7b3ed0c3b908d98ee2` |
| Patched | `8aff5492abc56fd237f09d7526d4c346e9a80911f41ba510b600ace08c6c5872` |

`HOS_SCENE_NATIVE=1`, `HOS_DYNRES=0` and `HOS_OUTPUT_RES` select the full-size
scene. Widescreen game patches come from Hookshot. We do not ship a game image
or generated game code. The observed 5120×1440 scene crop and main D32 depth
buffer support the resolution claim; display dimensions alone would not.

## Common quality settings

The shipped presets use custom docked settings, 16× texture filtering,
full-size textures (16384 maximum dimension), RGBA8 decoding instead of further
lossy ASTC-to-BC3 conversion, Lanczos filtering and 20% sharpening. The quality
preset is custom (`quality_preset=0`), since Hookshot's named Ultra preset can
also enable unwanted frame generation.

The public settings omit the development PC's hardcoded CPU affinity masks.
`TextureBudgetMB=0` leaves the cache budget to Hookshot; `12288` matches the
tested 24 GiB GPU's override. These differences affect scheduling and memory
pressure, not the requested image quality. They are not claimed FPS improvements.

`HOOKSHOT_OCCLUSION_OFF=1` retains the tested workaround for the renderer's
approximated visibility-query behavior. `RX_VK_PRECOMPILE=0` and
`RX_VK_NO_WARM=1` avoid the exhaustive precompile/warmup pass used by the
builder; scene shaders still compile on demand. This shortens initial waiting
but can introduce first-visit hitches. Do not measure those as warmed performance.

## Ultra activation and frame pacing

Bridge uses synthetic DLAA, depth and NVIDIA optical flow, passing frames
through private D3D11/D3D12 resources and back to Vulkan. This is a community
integration, not the game's native DLSS renderer. Hookshot's own `dlss=0`
therefore remains correct. RenoDX creates and evaluates NR Feature18.

With the tested versions, the first synthetic DLAA creation can precede the
RenoDX hook. The launcher waits for the hooks and a delivered frame, resizes
the launched game's own window once, then restores it. This recreates the
Vulkan runtime and synthetic session. It checks at least 60 successful
Feature18 evaluations at the selected dimensions; it does not equate loading
a DLL with working neural rendering.

Bridge `vk_sync=2` pipelines the previously processed frame, adding a frame
of latency. `ngx_loader=1` leaves the NVIDIA driver loader unchanged. The
Vulkan layer and ReShade search path are applied only to the game process.
No registry installation or system-wide injector is used.

## Why frame generation is off

Combining the tested DLSS chain with FSR 3.1 frame generation caused visible
flashing. Removing the neural bridge stopped that flashing, but FSR still
produced multiple HUD/character images. The user confirmed a clean moving
image with DLSS active and FSR/frame generation disabled. Those rejected
settings are not part of either preset.

Other local experiments (parallel bridge scheduling, removing a copy, renderer
patch candidates and alternative CPU settings) did not establish a useful
matched-scene FPS improvement. They are not silently applied in this package.

## Damaged NUP resources

The NUP used during development has three damaged compressed textures.
Hookshot 2.1.0 detects these and supplies stand-ins from that user's own game
resources. The two normal-map stand-ins (Fairy Fountain and Water Temple)
passed a static size check. The Ganon stand-in remains problematic:

`RBake_Scene_GanonStage_G_2_1_d0_t0.bntx.zs` receives a neighboring texture
whose decoded size is 9,101,416 bytes against a RESTBL limit of 6,934,920.
Its late-game load and appearance have not been validated. A successful
Castle Town test does not prove that this damaged dump can finish the game.

No damaged texture or substitute is bundled here. The installer uses the
upstream extraction behavior and documents this unresolved limit. A clean
supported dump is preferable. We have not tested a second copy of the NUP.
