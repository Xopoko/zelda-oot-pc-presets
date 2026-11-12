# Keyboard and mouse

Both presets use the same bindings. The installer redraws the on-screen button
prompts as keyboard/mouse labels using fonts and textures from your game files.

| Switch control | Keyboard or mouse |
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

The prompt mod changes 35 font glyphs, four HUD button images and six ocarina
note icons. Some pre-rendered controller diagrams in tutorials still show
Switch buttons; use the table above for those.

## Rebinding

Prompts are generated once, not updated live. After changing bindings in a
preset's `hookshot_options.ini`, quit the game and regenerate them:

```powershell
.\scripts\Build-Prompts.ps1 `
  -Python 'D:\Games\ZeldaPresets\build\builder-v2.1.0\HookshotBuilder\tools\python\python.exe' `
  -Romfs 'D:\Games\ZeldaPresets\base\romfs' `
  -Options 'D:\Games\ZeldaPresets\native\hookshot_options.ini' `
  -Output 'C:\Temp\Keyboard prompts' `
  -Cache 'D:\Games\ZeldaPresets\downloads' `
  -ReceiptPath 'C:\Temp\keyboard-prompts.json'
```

Then replace `mods\Keyboard prompts` in the preset folder with the new folder.
To get the Switch button icons back for gamepad play, remove
`mods\Keyboard prompts`.

Supported keys: A–Z, 0–9, five mouse buttons, Shift, Ctrl, Alt, Space, Enter,
Tab, Backspace, Escape, arrows, F1–F24, Home, End, Page Up/Down, Insert and
Delete. Other keys are rejected with an error.
