# Keyboard and mouse

Both presets start with the same bindings. The installer generates the on-screen keyboard labels from the local game resources and the preset's Hookshot options.

| Nintendo control | Keyboard or mouse |
| --- | --- |
| A, confirm or interact | **E** or Enter |
| B, back | **Shift** |
| X | **Space** |
| Y, attack | **Left mouse button** |
| L / R | **Q** / **R** |
| ZL, target | **Right mouse button** or Z |
| ZR | **F** or X |
| Plus / Minus | **Tab** / **M** |
| Left / right stick click | **Ctrl** / **C** |
| D-pad left / up / right / down | **1** / **2** / **3** / **4** |
| Move | **WASD** |
| Camera | **Mouse**, arrow keys or IJKL |

The mod changes 35 prompt glyphs, four HUD button masks and six ocarina note icons. Several baked-in controller diagrams and tutorials still display Nintendo buttons. The table also applies in those screens.

## Regenerate after changing bindings

Quit the game and use the options INI for the preset you changed. This command takes the Python executable from HookshotBuilder v2.1.0 and the extracted RomFS from your build. Use new paths for the mod folder and its JSON receipt.

Supported labels include A–Z, 0–9, five mouse buttons, Shift/Ctrl/Alt,
Space/Enter/Tab/Backspace, arrows, Escape, F1–F24 and navigation keys
(Home, End, Page Up/Down, Insert, Delete). Other virtual-key codes are rejected
with a named error rather than producing a misleading symbol. Font legibility
and in-game behavior of custom bindings need your own check.

~~~powershell
.\scripts\Build-Prompts.ps1 `
  -Python 'C:\Path\To\HookshotBuilder\tools\python\python.exe' `
  -Romfs 'C:\Path\To\Game\romfs' `
  -Options 'C:\Path\To\Preset\hookshot_options.ini' `
  -Output 'C:\Path\To\Staging\Keyboard prompts' `
  -Cache 'C:\Path\To\DownloadCache' `
  -ReceiptPath 'C:\Path\To\Staging\keyboard-prompts.json'
~~~

The generated folder contains a `romfs` subfolder. Move the previous `Keyboard prompts` folder out of the preset's `mods` directory, then move the new folder into `mods`. To restore the Nintendo symbols for gamepad play, move `Keyboard prompts` out of `mods`.

The generator checks the source resource hashes for game version 1.1.1. HookshotBuilder supplies Python, zstandard, FontTools and Pillow. The script downloads ARM astcenc 5.7.1 from its release and checks the archive SHA-256. Keep generated game resources in the local installation. [ARM astcenc release](https://github.com/ARM-software/astc-encoder/releases/tag/5.7.1)

The glyph drawing code comes from the MIT-licensed `totk-pc-recomp` tool and its MacNativeGames predecessor. [totk-pc-recomp source](https://github.com/valentderah/totk-pc-recomp/blob/ae30a61b7bee4a3db959a234e7459e95939ac596/tools/button_icons.py) · [MacNativeGames source](https://github.com/ly05010419/MacNativeGames/blob/933b6a0d1438de160208a0a13eb5e8d7a2cb8094/games/totk/scripts/make_button_icons.py) · [MIT notices](../tools/prompts/LICENSE.upstream)
