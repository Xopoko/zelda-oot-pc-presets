# Dependencies and provenance

## Base installation and prompts

The installer downloads **Hookshot v2.1.0** through eight hash-pinned builder
parts from the maintainer's release and LLVM-MinGW. The packaged Python,
compiler, shader toolchain, .NET runtime and libraries stay inside the
installation's build directory. They are not installed globally or copied into
this source repository. Hookshot is GPL-3.0 licensed; the generated game and
extracted resources remain private to the user's machine.
[Release](https://github.com/NotRexed/Hookshot/releases/tag/v2.1.0) ·
[Hookshot license](https://github.com/NotRexed/Hookshot/blob/v2.1.0/LICENSE) ·
[Pinned manifest](../manifests/hookshot-2.1.0.json).

The bundled Python already supplies `zstandard`, `fontTools` and Pillow for
the prompt generator. ARM's **astcenc 5.7.1** SSE2 executable is fetched from
its Apache-2.0 release and checked by SHA-256. `tools/prompts/button_icons.py`
comes from `valentderah/totk-pc-recomp` commit
`ae30a61b7bee4a3db959a234e7459e95939ac596`; its MIT notice is preserved in
`tools/prompts/LICENSE.upstream`. The generator reads fonts and textures from
the user's own RomFS and writes a local mod. No font or texture is bundled.
[Prompt dependencies and controls](CONTROLS.md) ·
[ARM license](https://github.com/ARM-software/astc-encoder/blob/5.7.1/LICENSE.txt).

## Ultra rendering

Ultra adds the tested DLSS 5 Neural Rendering path to the same native-resolution Hookshot build used by Native. The bridge creates a private DLAA session using depth from ReShade and motion from NVIDIA Optical Flow. RenoDX runs Neural Rendering through NGX Feature 18, and the bridge sends the result back to Vulkan. FSR and frame generation stay disabled.

This combination ran on an RTX 4090 with NVIDIA driver 621.14 and Vulkan loader 1.4.357.0. The process-local implicit layer path requires Vulkan loader 1.3.295 or later. Launch from a standard user session because the Vulkan loader ignores layer path overrides for elevated applications. Other GPUs and driver versions need separate testing. [Vulkan loader documentation](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderApplicationInterface.md)

## Files supplied by the installer

| Component | Source and terms |
| --- | --- |
| ReShade 6.8.0, full add-on support | The installer extracts the x64 DLL and Vulkan layer manifest from the official setup archive. ReShade's source license is BSD-3-Clause. The setup archive is fetched directly from ReShade and never executed. [Release](https://reshade.me/releases/10326-6-8) · [License](https://github.com/crosire/reshade/blob/v6.8.0/LICENSE.md) |
| NIGos DLSS 5 Bridge v1.4.12 | The maintainer's tagged add-on release. The project uses the MIT license. [Release](https://github.com/NIGos/dlss5-bridge/releases/tag/v1.4.12) · [License](https://github.com/NIGos/dlss5-bridge/blob/v1.4.12/LICENSE) |
| RenoDX DLSS 5 add-on 2.5 | The exact add-on used in the gameplay test comes from the RankFTW community mirror. Its release carries no license or build attestation for that particular binary. The installer fetches the release archive and checks both the archive and extracted binary hashes. The main RenoDX source project has a separate MIT license. [Mirrored release](https://github.com/RankFTW/rhi-repo/releases/tag/renodx-dlss5-2.5) · [RenoDX source license](https://github.com/clshortfuse/renodx/blob/main/LICENSE) |
| NVIDIA DLSS Super Resolution 310.9.1 | The unmodified NVIDIA binary is downloaded from the pinned commit of NVIDIA's DLSS SDK and used for DLAA. The NVIDIA RTX SDKs License applies, including its restriction to compatible NVIDIA hardware. [SDK](https://github.com/NVIDIA/DLSS/tree/374959484e79a640feaba44c93ac8cfb0a03f5b5) · [License](https://github.com/NVIDIA/DLSS/blob/374959484e79a640feaba44c93ac8cfb0a03f5b5/LICENSE.txt) |

The pinned download URLs, sizes and SHA-256 values are in [the graphics manifest](../manifests/graphics.json). The file hashes in the installation receipt identify the resulting preset files.

## Neural Rendering runtime supplied by the user

Ultra requires a separate `nvngx_dlssnr.dll` in addition to the game NUP. NVIDIA confirmed on November 9, 2026 that public access to the DLSS 5 SDK and evaluation releases was unavailable. The installer takes a file you have the right to use through `-NrRuntime` and verifies the exact tested bytes. [NVIDIA Developer Forums](https://forums.developer.nvidia.com/t/official-dlss-5-neural-rendering-plugin-access-for-unreal-engine-5-8-2/382731)

| Field | Tested runtime |
| --- | --- |
| Version and target | 310.8.0.0, Ada compatibility build |
| Size | 165,840,496 bytes |
| SHA-256 | `ceb6432f6fbdf44d886014bcd47241932bf8b67439feef9bbdd0961436662650` |
| Authenticode | `HashMismatch`. The runtime was modified for Ada. The SHA-256 identifies the tested bytes and provides no publisher authentication. |

Other DLSS NR builds, including unmodified binaries with the same version number, have different hashes. Use Native if you have only the NUP, prefer a signed runtime, or have a GPU outside the tested Ultra configuration.

## Local configuration and diagnosis

The launcher sets `VK_IMPLICIT_LAYER_PATH` and `RESHADE_BASE_PATH_OVERRIDE` for the game process so it sees the preset's own `bin` directory. `ReShade64.json` resolves `ReShade64.dll` relative to itself. `ZeldaDepthTap.fx` exposes the depth buffer with color writes disabled. The bridge keeps the driver's NGX loader with `ngx_loader=1`.

At startup the bridge can create its first DLAA session before RenoDX has installed its D3D12 hooks. Recreating the swapchain after the first delivered frame lets RenoDX attach to the next session. The two key log lines are `D3D12 NGX hooks installed` in `bin/ReShade.log` and `Vulkan frame ... delivered` in `bin/dlss5-bridge.log`. An Ultra session that has engaged the tested effect shows `inline feature 18 evaluation succeeded` with the expected resolution in `bin/ReShade.log`.
