# Installation and saves

## Install

Run `Install.ps1` in Windows PowerShell 5.1 or PowerShell 7 from a normal
(non-administrator) session. The destination must be a new or empty folder
outside this repository.

```powershell
.\Install.ps1 -Nup "D:\Dumps\game.nup" -Destination "D:\Games\ZeldaPresets"
```

The installer checks the NUP version, downloads the pinned toolchain, builds
the game, creates the presets, patches the scene-width cap
([details](TECHNICAL.md#full-resolution-scene)), generates keyboard prompts
from your game files and creates desktop shortcuts. Everything stays inside
the destination folder; nothing is installed system-wide.

For Ultra, the Neural Rendering runtime is downloaded and verified before the
long build starts, so a bad download fails early.

| Option | Purpose |
| --- | --- |
| `-Preset Both\|Native\|Ultra` | Presets to install; default `Both` |
| `-Resolution 5120x1440` | Output size; default `auto` reads the primary display |
| `-Language ru` | Game language; default `en-US` |
| `-TextureBudgetMB 12288` | Texture-cache budget; default lets Hookshot decide |
| `-Jobs 12` | Limit parallel compile jobs |
| `-DownloadCache "D:\Cache\Zelda"` | Reuse verified downloads between installs |
| `-NrRuntime "D:\nvngx_dlssnr.dll"` | Use a local copy of the pinned NR DLL instead of downloading it |
| `-ImportProfile "D:\OldZelda\user"` | Copy `save/` from an existing profile folder |
| `-NoShortcuts` | Skip desktop shortcuts |
| `-ShortcutDirectory "D:\Shortcuts"` | Put shortcuts somewhere other than the desktop |

A failed hash check stops the install; there is no fallback mirror.

## Launch

Use a desktop shortcut, or from the installation folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Preset Native
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Preset Ultra
```

Run one preset at a time. The first visit to a scene compiles shaders and can
stutter or briefly show missing materials.

Ultra resizes the game window once at startup and restores it; this is how
the launcher gets neural rendering to attach
([why](TECHNICAL.md#ultra-startup)). If activation is not confirmed, the
launcher shows an error and writes `logs/launch-ultra.log`.

## Saves and upgrades

Both presets use `<installation>/profile/save/`. `-ImportProfile` copies
`save/` from the given folder into the new profile and keeps a second copy in
`backups/imported-save/`. The source is not modified. Close the game first.

The installer never writes into a non-empty folder. To upgrade, install into a
new folder with `-ImportProfile` pointing at the old `profile/`, check your
save there, then remove the old installation.

A failed install leaves its files and `installation-status.json` in place.
Retry into a new folder; pass `-DownloadCache` to reuse finished downloads.

## Removal

Close the game, back up `profile/`, then delete the installation folder and
its shortcuts. There is no uninstaller.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| NUP rejected | Title, update and build must match; see `build/nup-check.log` |
| Download hash mismatch | Move the bad file out of the download cache and retry |
| Ultra looks like Native | `bin/ReShade.log` should contain `inline feature 18 evaluation succeeded` |
| Flicker or ghosting | Check `frame_generation=0` and `RX_VK_FRAMEGEN=0`; don't add FSR or other injectors |
| Wrong resolution | Check `HOS_OUTPUT_RES` and `HOS_ASPECT` in each preset's `hookshot_env.txt` |
| Prompts wrong after rebinding | [Regenerate the prompt mod](CONTROLS.md#rebinding) |

Logs can contain local paths. Don't attach NUPs, saves, keys, extracted game
files or DLLs to public issues.
