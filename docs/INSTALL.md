# Installation and saves

## Fresh installation

Run `Install.ps1` from this repository in Windows PowerShell 5.1 or PowerShell 7.
Point `-Nup` at a dump you are entitled to use. Brackets and spaces in the name
are supported. Choose an empty installation folder outside this checkout.

The script fetches the pinned Hookshot toolchain, validates the supported build,
extracts and compiles the NUP, creates selected presets, patches copied scene
data, regenerates prompts from the extracted resources, installs the optional
graphics chain and creates shortcuts. Game data never leaves your computer.

```powershell
.\Install.ps1 -Nup "D:\Dumps\game.nup" -Destination "D:\Games\ZeldaPresets" -Preset Both -NrRuntime "D:\Runtimes\nvngx_dlssnr.dll" -Resolution 5120x1440 -Language en-US
```

Use `-Preset Native` (default), `Ultra`, or `Both`. Ultra requires the exact
compatible user-supplied runtime described in [DEPENDENCIES.md](DEPENDENCIES.md).
Missing or unrecognized NR stops installation before the game build; it is not
silently replaced with a different rendering path.

Options:

| Option | Purpose |
| --- | --- |
| `-Resolution auto` | Read the primary display's physical pixels; default |
| `-Resolution 5120x1440` | Explicit output; use the fullscreen display's actual size |
| `-Language ru` | Game language; defaults to `en-US` |
| `-TextureBudgetMB 12288` | Optional texture-cache budget; default uses Hookshot's automatic budget |
| `-Jobs 12` | Limit concurrent compilation jobs; default uses builder auto selection |
| `-DownloadCache "D:\Cache\Zelda"` | Reuse SHA-verified downloads; no overwrite of mismatching files |
| `-ImportProfile "D:\OldZelda\user"` | Copy the existing profile's `save/` into this new installation |
| `-NoShortcuts` | Do not create desktop shortcuts |
| `-ShortcutDirectory "D:\My shortcuts"` | Create the chosen directory if needed and write shortcuts there |
| `-ExistingBuild "D:\ExistingHookshot"` | Advanced: reuse a hash-verified v2.1.0 build instead of recompiling |

Use the bundled interpreter through the provided scripts. You do not need a
separate Python, C++ compiler, Codex or desktop automation tool. Dependencies
are staged locally; there is no driver modification or global Vulkan-layer
registration. A blocked GitHub/release download fails visibly with the URL and
hash check; the installer does not substitute an unverified mirror.

## Launch

Use a desktop shortcut, or run from the installation folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Preset Native
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Preset Ultra
```

The launcher starts `bin/hookshot.exe` with the correct working directory,
shared ROMFS and save profile. The root Hookshot builder is not the game.
Close one session before switching presets.

The first launch and first visit to a scene can pause to compile shaders.
Let it finish. Shader caches are private to each preset; do not transfer
device-dependent caches between PCs. Ultra checks fresh logs for successful
Feature18 evaluations at the requested resolution. Its one-time startup resize
should settle back to fullscreen. An activation failure is reported and logged.

## Saves and upgrades

Both presets use `<installation>/profile/save/`. The installer never scans
other installations for saves. When `-ImportProfile` is specified, it copies
`save/` into the new profile and keeps a second copy under
`backups/imported-save/save/`. The source is untouched. Close the old game
before importing so that it cannot change the source during the copy.

The installer refuses a nonempty destination. For an upgrade:

1. Close the game and copy `profile/` to a safe backup location.
2. Install into a new folder, passing the old `profile/` to `-ImportProfile`.
3. Load the desired save in the new installation before retiring the old one.

An interrupted installation keeps its files and `installation-status.json` for
diagnosis. Use a new destination for the retry; `-DownloadCache` can reuse the
previous verified downloads. Never delete a folder that contains your only saves.

## Removal

Close the game. Back up `profile/`, then remove the installation folder and its
shortcuts yourself. No uninstall script touches saves or other games. The source
checkout can be removed separately. Downloads/build work may be kept as a cache.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| NUP rejected | Title/update/build must match; read the builder check log |
| Download hash mismatch | Keep the failed file for diagnosis; obtain the exact pinned file from its owner |
| Ultra asks for an NR DLL | The model is a separate prerequisite; see dependency documentation |
| Ultra looks native | Read the launch log and the preset's `bin/ReShade.log`; successful startup includes Feature18 count=60 |
| First scene stalls | Shader compilation is expected on a fresh cache; compare warmed gameplay |
| Repeated flicker or ghosting | Confirm `frame_generation=0` and `RX_VK_FRAMEGEN=0`; do not stack FSR/other injectors |
| Wrong resolution | Use the monitor's physical size, then check `HOS_OUTPUT_RES` and `HOS_ASPECT` in both presets |
| Prompts differ after remapping | Rebuild the prompt mod from the updated INI; it is not a live remapping overlay |

Logs and receipts stay in the installation. Review them for private paths
before attaching anything to a public issue. Never attach NUPs, saves, keys,
extracted assets, or proprietary DLLs.
