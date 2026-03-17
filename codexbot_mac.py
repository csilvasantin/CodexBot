#!/usr/bin/env python3
"""
CodexBot v2.0 (macOS) — Auto-approve Codex permission prompts

Detects the green "En espera de aprobacion" badge in the Codex
sidebar and sends "2" to auto-approve.

Usage:
    python3 codexbot_mac.py                # defaults (30m, 6s)
    python3 codexbot_mac.py -d 60          # run 60 minutes
    python3 codexbot_mac.py -i 4           # check every 4s

Requires: pip3 install Pillow pyautogui
Stop: Ctrl+C
"""

import subprocess
import time
import sys
import os
import argparse
from datetime import datetime, timedelta

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip3 install Pillow")
    sys.exit(1)

try:
    import pyautogui
    pyautogui.FAILSAFE = True
except ImportError:
    print("Install pyautogui: pip3 install pyautogui")
    sys.exit(1)


def find_codex_window():
    """Find Codex window using AppleScript."""
    script = '''
    tell application "System Events"
        set codexProcs to every process whose name contains "Codex"
        if (count of codexProcs) > 0 then
            set p to item 1 of codexProcs
            set winList to every window of p
            if (count of winList) > 0 then
                set w to item 1 of winList
                set pos to position of w
                set sz to size of w
                return (item 1 of pos as text) & "," & (item 2 of pos as text) & "," & (item 1 of sz as text) & "," & (item 2 of sz as text) & "," & (name of p)
            end if
        end if
    end tell
    return "NOTFOUND"
    '''
    try:
        result = subprocess.run(["osascript", "-e", script],
                                capture_output=True, text=True, timeout=5)
        out = result.stdout.strip()
        if out and out != "NOTFOUND":
            parts = out.split(",")
            if len(parts) >= 4:
                return {
                    "x": int(parts[0]), "y": int(parts[1]),
                    "w": int(parts[2]), "h": int(parts[3]),
                    "name": parts[4] if len(parts) > 4 else "Codex"
                }
    except Exception:
        pass
    return None


def capture_window(win_info, save_path):
    """Capture a screenshot of the Codex window region."""
    x, y, w, h = win_info["x"], win_info["y"], win_info["w"], win_info["h"]
    tmp = "/tmp/codexbot_capture.png"
    subprocess.run(["screencapture", "-x", "-R",
                     f"{x},{y},{w},{h}", tmp],
                    capture_output=True, timeout=5)
    if os.path.exists(tmp):
        img = Image.open(tmp)
        if save_path:
            img.save(save_path)
        return img
    return None


def has_approval_badge(img):
    """Check for green 'En espera de aprobacion' badge in sidebar."""
    w, h = img.size
    if w < 200 or h < 200:
        return 0

    pixels = img.load()
    sidebar_w = min(400, int(w * 0.35))
    scan_y_start = 150
    scan_y_end = min(500, int(h * 0.4))

    # Handle Retina displays (image may be 2x the window size)
    if w > 2000:
        sidebar_w = min(800, int(w * 0.35))
        scan_y_start = 300
        scan_y_end = min(1000, int(h * 0.4))

    green_count = 0
    step = 2 if w < 2000 else 4  # bigger step for retina

    for y in range(scan_y_start, scan_y_end):
        for x in range(0, sidebar_w, step):
            r, g, b = pixels[x, y][:3]
            if g > 140 and r < 200 and b < 120 and (g - r) > 20:
                green_count += 1

    return green_count


def send_approval():
    """Bring Codex to front and send '2'."""
    # Activate Codex window
    script = '''
    tell application "System Events"
        set codexProcs to every process whose name contains "Codex"
        if (count of codexProcs) > 0 then
            set frontmost of item 1 of codexProcs to true
        end if
    end tell
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True, timeout=5)
    time.sleep(0.3)

    # Send "2"
    pyautogui.press("2")
    time.sleep(0.2)


def main():
    parser = argparse.ArgumentParser(description="CodexBot macOS — auto-approve Codex prompts")
    parser.add_argument("-d", "--duration", type=int, default=30, help="Minutes to run (default: 30)")
    parser.add_argument("-i", "--interval", type=int, default=6, help="Seconds between checks (default: 6)")
    parser.add_argument("--no-save", action="store_true", help="Don't save screenshots")
    args = parser.parse_args()

    screenshot_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "screenshots")
    os.makedirs(screenshot_dir, exist_ok=True)

    banner = """
   ____          _           ____        _
  / ___|___   __| | _____  _| __ )  ___ | |_
 | |   / _ \\ / _` |/ _ \\ \\/ /  _ \\ / _ \\| __|
 | |__| (_) | (_| |  __/>  <| |_) | (_) | |_
  \\____\\___/ \\__,_|\\___/_/\\_\\____/ \\___/ \\__|  v2.0 macOS
"""
    print(f"\033[96m{banner}\033[0m")
    print(f"  Duration: {args.duration}m  |  Interval: {args.interval}s  |  Ctrl+C to stop")
    print(f"  \033[90m{'─' * 42}\033[0m\n")

    deadline = datetime.now() + timedelta(minutes=args.duration)
    total_checks = 0
    total_approved = 0
    start_time = datetime.now()

    try:
        while datetime.now() < deadline:
            total_checks += 1
            remaining = round((deadline - datetime.now()).total_seconds() / 60, 1)
            ts = datetime.now().strftime("%H:%M:%S")

            win = find_codex_window()
            if not win:
                print(f"\033[90m[{ts}]\033[0m \033[33mCodex not found...\033[0m ({remaining}m | x{total_approved})")
                time.sleep(args.interval)
                continue

            save_path = None if args.no_save else os.path.join(screenshot_dir, "codex_last.png")
            img = capture_window(win, save_path)

            if not img:
                print(f"\033[90m[{ts}]\033[0m \033[31mCapture failed\033[0m ({remaining}m | x{total_approved})")
                time.sleep(args.interval)
                continue

            green = has_approval_badge(img)
            img.close()

            if green > 100:
                send_approval()
                total_approved += 1
                print(f"\033[90m[{ts}]\033[0m \033[92mAPPROVED!\033[0m \033[90m[green:{green}px]\033[0m ({remaining}m | x{total_approved})")
                time.sleep(3)  # wait for Codex to process
            else:
                print(f"\033[90m[{ts}]\033[0m \033[36mNo prompt\033[0m \033[90m[green:{green}px]\033[0m ({remaining}m | x{total_approved})")

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print(f"\n\033[93m  Stopped by user.\033[0m")

    elapsed = round((datetime.now() - start_time).total_seconds() / 60, 1)
    color = "\033[92m" if total_approved > 0 else "\033[90m"
    print(f"\n  \033[90m{'─' * 42}\033[0m")
    print(f"  {color}Runtime: {elapsed}m | Checks: {total_checks} | Approved: {total_approved}\033[0m")
    print(f"\033[96m  CodexBot finished.\033[0m\n")


if __name__ == "__main__":
    main()
