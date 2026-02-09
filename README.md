# custom-run-ui
Flow launcher UI written in GODOT (yes, godot)

### Requirements: 
- Python 3.14 (this is the one i wrote a useful .py on, could work on an earlier version)
- Chocolatey (you can install it quickly by doing winget install chocolatey!)

### Important notes:
- Do NOT erase ANY of the files in the CRU folder, i recommend making a separate one for it
- On the first launch, CRU will freeze a little, thats it reading ur shortcuts so it can add them to the list dont worry.
- CRU does not support ALL "shell:PATH" commands, but it does support:
  - shell:startup
  - shell:downloads
  - shell:programs
  - shell:desktop
- CRU is not heavily tested, so if any issues pop up, please report them!

### CRU-specific commands:
- reload - reloads all the .lnk files from "Program Files/Start Menu/Programs" so it can display the shortcuts to apps (with icons!)
- refreshenv - reloads PATH environment (REQUIRES CHOCOLATEY)

### Ease of use:
If you wanna CRU easier, i recommend using [AutoHotKey](https://github.com/AutoHotkey/AutoHotkey/releases)

here's a script that should work
#r::Run "PATH/TO/CRU" 
