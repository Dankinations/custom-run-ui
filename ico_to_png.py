import sys
import os
import win32com.client
import win32gui
import win32ui
import win32con
import win32api
from PIL import Image


def resolve_lnk_full(lnk_path):
    shell = win32com.client.Dispatch("WScript.Shell")
    shortcut = shell.CreateShortcut(lnk_path)
    return shortcut.Targetpath, shortcut.IconLocation


def resolve_real_exe_if_update(target):
    """
    If shortcut points to Update.exe (Discord/Slack/etc),
    try to find real exe in app-* folders.
    """
    if not target:
        return target

    if target.lower().endswith("update.exe"):
        base = os.path.dirname(target)

        try:
            for name in os.listdir(base):
                if name.lower().startswith("app-"):
                    candidate = os.path.join(base, name, "Discord.exe")
                    if os.path.exists(candidate):
                        return candidate
        except Exception:
            pass

    return target


def extract_largest_icon_to_png(file_path, output_png):
    if os.path.exists(output_png):
        print(f"PNG already exists: {output_png}, skipping.")
        return False

    largest_hicon = None
    largest_size = 0

    for index in range(0, 10):
        try:
            large, small = win32gui.ExtractIconEx(file_path, index)
        except Exception:
            continue

        if large:
            hicon = large[0]

            # We assume larger index often = larger icon
            size_guess = 256 - index * 16
            if size_guess > largest_size:
                largest_size = size_guess
                largest_hicon = hicon
            else:
                win32gui.DestroyIcon(hicon)

            for ico in small:
                win32gui.DestroyIcon(ico)

    if not largest_hicon:
        return False

    hicon = largest_hicon

    try:
        hdc = win32ui.CreateDCFromHandle(win32gui.GetDC(0))
        hbmp = win32ui.CreateBitmap()

        size = 256
        hbmp.CreateCompatibleBitmap(hdc, size, size)

        hdc_mem = hdc.CreateCompatibleDC()
        hdc_mem.SelectObject(hbmp)

        brush = win32ui.CreateBrush()
        brush.CreateSolidBrush(win32api.RGB(0, 0, 0))
        hdc_mem.FillRect((0, 0, size, size), brush)

        win32gui.DrawIconEx(
            hdc_mem.GetHandleOutput(),
            0,
            0,
            hicon,
            size,
            size,
            0,
            None,
            win32con.DI_NORMAL
        )

        bmpinfo = hbmp.GetInfo()
        bmpstr = hbmp.GetBitmapBits(True)

        img = Image.frombuffer(
            "RGBA",
            (bmpinfo["bmWidth"], bmpinfo["bmHeight"]),
            bmpstr,
            "raw",
            "BGRA",
            0,
            1
        )

        img.save(output_png, "PNG")

    finally:
        win32gui.DestroyIcon(hicon)

    return True


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python lnk_icon_to_png.py shortcut.lnk output.png")
        print("  python lnk_icon_to_png.py --leads-to-exe shortcut.lnk")
        return

    # --- Special flag ---
    if sys.argv[1] == "--leads-to-exe":
        if len(sys.argv) < 3:
            print("false")
            return

        lnk = sys.argv[2]

        if not os.path.exists(lnk):
            print("false")
            return

        target, icon_loc = resolve_lnk_full(lnk)
        target = resolve_real_exe_if_update(target)

        if os.path.exists(target) and target.lower().endswith(".exe"):
            print("true")
        else:
            print("false")
        return

    # --- Normal behavior ---
    if len(sys.argv) < 3:
        print("Error: shortcut and output PNG required.")
        return

    lnk = sys.argv[1]
    out = sys.argv[2]

    if not os.path.exists(lnk):
        print(f"Shortcut not found: {lnk}")
        return

    target, icon_loc = resolve_lnk_full(lnk)

    # Try resolving real exe (Discord etc)
    target = resolve_real_exe_if_update(target)

    icon_path = None

    # 1️⃣ Try icon location from shortcut
    if icon_loc:
        icon_path = icon_loc.split(",")[0]
        if not os.path.exists(icon_path):
            icon_path = None

    # 2️⃣ Fallback to target exe
    if not icon_path and os.path.exists(target):
        icon_path = target

    if not icon_path:
        print("No valid icon source found.")
        return

    success = extract_largest_icon_to_png(icon_path, out)

    if success:
        print("Done:", out)
    else:
        print("Skipped (no icon or PNG already exists).")


if __name__ == "__main__":
    main()
