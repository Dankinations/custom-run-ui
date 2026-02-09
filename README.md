# custom-run-ui
Flow launcher UI written in GODOT (yes, godot)

### Requirements: 
- Python 3.14 (the one i wrote it on, could work on an earlier version)
- Chocolatey (you can install it quickly by doing winget install chocolatey!)

### CRU-specific commands:
- reload - reloads all the .lnk files from "Program Files/Start Menu/Programs" so it can display the shortcuts to apps (with icons!)
- refreshenv - reloads PATH environment (REQUIRES CHOCOLATEY)

### Important notes:
- CRU does not support ALL "shell:PATH" commands, but it does support:
  - shell:startup
  - shell:downloads
  - shell:programs
  - shell:desktop
- CRU is not heavily tested, so if any issues pop up, please report them!

### Ease of use:
If you wanna CRU easier, i recommend using [url=https://github.com/AutoHotkey/AutoHotkey/releases]AutoHotKey[/url].
