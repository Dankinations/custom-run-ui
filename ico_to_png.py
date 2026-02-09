import sys
import os
import win32com.client
import win32gui
import win32ui
import win32con
import win32api
from PIL import Image


def resolve_lnk(lnk_path):
    """Return the target path of a .lnk shortcut."""
    shell = win32com.client.Dispatch("WScript.Shell")
    shortcut = shell.CreateShortcut(lnk_path)
    return shortcut.Targetpath


def extract_largest_icon_to_png(file_path, output_png):
    """
    Extract the largest available icon from file_path to output_png.
    Skip if no icon or PNG already exists.
    """
    if os.path.exists(output_png):
        print(f"PNG already exists: {output_png}, skipping.")
        return False

    largest_hicon = None
    largest_size = 0

    # Try indices 0-9
    for index in range(0, 10):
        try:
            large, small = win32gui.ExtractIconEx(file_path, index)
        except Exception:
            continue

        if large:
            hicon = large[0]
            # Get icon size
            icon_info = win32gui.GetIconInfo(hicon)
            width = icon_info[1][2] if icon_info else 0
            height = icon_info[1][3] if icon_info else 0
            area = width * height
            if area > largest_size:
                largest_size = area
                largest_hicon = hicon
            else:
                win32gui.DestroyIcon(hicon)
            # Destroy other icons
            for ico in small:
                win32gui.DestroyIcon(ico)

    if not largest_hicon:
        return False  # no icon found

    hicon = largest_hicon

    try:
        # Create device contexts
        hdc = win32ui.CreateDCFromHandle(win32gui.GetDC(0))
        hbmp = win32ui.CreateBitmap()

        size = 256  # max size for PNG
        hbmp.CreateCompatibleBitmap(hdc, size, size)

        hdc_mem = hdc.CreateCompatibleDC()
        hdc_mem.SelectObject(hbmp)

        # Fill background black
        brush = win32ui.CreateBrush()
        brush.CreateSolidBrush(win32api.RGB(0, 0, 0))
        hdc_mem.FillRect((0, 0, size, size), brush)

        # Draw icon
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

        # Convert to PNG
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

    # Special flag: check if leads to EXE
    if sys.argv[1] == "--leads-to-exe":
        if len(sys.argv) < 3:
            print("false")
            return
        lnk = sys.argv[2]

        if not os.path.exists(lnk):
            print("false")
            return

        target = resolve_lnk(lnk)

        if os.path.exists(target) and target.lower().endswith(".exe"):
            print("true")
        else:
            print("false")
        return

    # Default behavior: lnk + output.png
    if len(sys.argv) < 3:
        print("Error: shortcut and output PNG required.")
        return

    lnk = sys.argv[1]
    out = sys.argv[2]

    if not os.path.exists(lnk):
        print(f"Shortcut not found: {lnk}")
        return

    target = resolve_lnk(lnk)

    if not os.path.exists(target):
        print(f"Target not found: {target}")
        return

    success = extract_largest_icon_to_png(target, out)

    if success:
        print("Done:", out)
    else:
        print("Skipped (no icon or PNG already exists).")


if __name__ == "__main__":
    main()
