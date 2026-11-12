# Dependencies

Everything below is downloaded by the installer, checked against the SHA-256
(and usually size) in [`manifests/`](../manifests), and kept inside the
installation folder. Nothing is installed globally.

## Base build and prompts

| Component | Source and license |
| --- | --- |
| Hookshot v2.1.0 builder (seven parts) and LLVM-MinGW 20261104 | [Hookshot release](https://github.com/NotRexed/Hookshot/releases/tag/v2.1.0), GPL-3.0 ([license](https://github.com/NotRexed/Hookshot/blob/v2.1.0/LICENSE)). Includes Python, compilers, the shader toolchain and .NET. Pins: [`hookshot-2.1.0.json`](../manifests/hookshot-2.1.0.json) |
| ARM astcenc 5.7.1 | [Release](https://github.com/ARM-software/astc-encoder/releases/tag/5.7.1), Apache-2.0. Used to redraw the ocarina note icons. Pin: [`prompts.json`](../manifests/prompts.json) |
| `tools/prompts/button_icons.py` | Copied from [`valentderah/totk-pc-recomp`](https://github.com/valentderah/totk-pc-recomp/blob/ae30a61b7bee4a3db959a234e7459e95939ac596/tools/button_icons.py), which adapted it from [MacNativeGames](https://github.com/ly05010419/MacNativeGames/blob/933b6a0d1438de160208a0a13eb5e8d7a2cb8094/games/totk/scripts/make_button_icons.py). MIT, notices in [`LICENSE.upstream`](../tools/prompts/LICENSE.upstream) |

The prompt generator runs on the builder's bundled Python, which already has
zstandard, fontTools and Pillow. It reads fonts and textures from your own
RomFS; none are bundled.

Desktop shortcuts point to `ZeldaLauncher.exe`, a small GUI wrapper compiled
during install from [`LauncherBootstrap.cs`](../scripts/LauncherBootstrap.cs)
with the .NET Framework compiler that ships with Windows. It starts
`Launch.ps1` without a console window.

## Ultra

Pins: [`graphics.json`](../manifests/graphics.json).

| Component | Source and license |
| --- | --- |
| ReShade 6.8.0 with add-on support | `ReShade64.dll` and `ReShade64.json` are extracted from the [official setup](https://reshade.me/releases/10326-6-8) without running it. BSD-3-Clause ([license](https://github.com/crosire/reshade/blob/v6.8.0/LICENSE.md)) |
| NIGos DLSS 5 Bridge v1.4.12 | [Release](https://github.com/NIGos/dlss5-bridge/releases/tag/v1.4.12), MIT |
| RenoDX DLSS 5 add-on 2.5 | From the [RankFTW community mirror](https://github.com/RankFTW/rhi-repo/releases/tag/renodx-dlss5-2.5); this build has no license or provenance of its own. RenoDX itself is [MIT](https://github.com/clshortfuse/renodx/blob/main/LICENSE) |
| NVIDIA DLSS Super Resolution 310.9.1 | Unmodified, from a pinned commit of the [DLSS SDK](https://github.com/NVIDIA/DLSS/tree/374959484e79a640feaba44c93ac8cfb0a03f5b5). [NVIDIA RTX SDKs License](https://github.com/NVIDIA/DLSS/blob/374959484e79a640feaba44c93ac8cfb0a03f5b5/LICENSE.txt), NVIDIA hardware only |
| Neural Rendering runtime 310.8.0 | See below |

## Neural Rendering runtime

`nvngx_dlssnr.dll` comes from `streamline.zip` in yumlevi's
[renodx-dlss-installer release](https://github.com/yumlevi/renodx-dlss-installer/releases/tag/latest).
It is a community-modified build for Ada GPUs. The repository has no license,
and because the DLL was modified its Authenticode signature reports
`HashMismatch`. The SHA-256 pin is what ties it to the copy that was tested.

| | Archive | DLL |
| --- | --- | --- |
| File | `streamline.zip` (asset `534399347`) | `streamline/nvngx_dlssnr.dll` |
| Size | 144,023,101 bytes | 165,840,496 bytes |
| SHA-256 | `5389d164ef99a0e4aba5128da2e87d26de5833aeaf89bfeb0232cfdc8f7229a2` | `ceb6432f6fbdf44d886014bcd47241932bf8b67439feef9bbdd0961436662650` |

The release is tagged `latest`, so it can change; a changed archive fails the
check before the game build starts. If you already have the exact DLL, pass it
with `-NrRuntime` to skip the download. `-Preset Native` skips it entirely.
