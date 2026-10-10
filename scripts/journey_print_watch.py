#!/usr/bin/env python3
"""Taps through Android's system print sheet (Save as PDF -> save) while journeys run.

The journey harness cannot drive another app's activity (flows.dart S0.5b). This watcher polls
the UI hierarchy over adb and, when the print spooler or the document saver is in front, taps
its primary button. It never touches the app under test.
"""
import os, re, subprocess, sys, time

DEV = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
DEADLINE = time.time() + float(sys.argv[2] if len(sys.argv) > 2 else 3600)
# scripts/run_journeys.sh passes the adb it resolved (the SDK's, when adb is not on PATH).
ADB = os.environ.get("ADB") or "adb"


def adb(*a):
    return subprocess.run([ADB, "-s", DEV, *a], capture_output=True, text=True).stdout


def dump():
    return subprocess.run([ADB, "-s", DEV, "exec-out", "uiautomator", "dump", "/dev/tty"],
                          capture_output=True, text=True).stdout


def centre(node):
    m = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def find(xml, pred):
    for node in re.findall(r"<node [^>]*>", xml):
        if pred(node):
            return node
    return None


def focus():
    out = adb("shell", "dumpsys", "window")
    m = re.search(r"mCurrentFocus=.*", out)
    return m.group(0) if m else ""


while time.time() < DEADLINE:
    # Only dump (which turns accessibility on, and with it Flutter semantics) when another app's
    # print or save activity is in front - never over the app under test.
    f = focus()
    if "printspooler" not in f and "documentsui" not in f:
        time.sleep(1)
        continue
    xml = dump()
    hit = None
    if "com.android.printspooler" in xml:
        # 1. the destination list is open: pick Save as PDF;
        # 2. Save as PDF chosen: the floating "download PDF" button;
        # 3. no destination yet ("Select a printer"): open the destination list.
        hit = find(xml, lambda n: 'resource-id="com.android.printspooler:id/print_button"' in n) \
            or find(xml, lambda n: 'text="Save as PDF"' in n
                    and 'resource-id="com.android.printspooler:id/title"' not in n)
        if not hit and 'text="Select a printer"' in xml:
            hit = find(xml, lambda n: 'resource-id="com.android.printspooler:id/destination_spinner"' in n)
    elif "com.android.documentsui" in xml or "com.google.android.documentsui" in xml:
        hit = find(xml, lambda n: re.search(r'text="(SAVE|Save)"', n) and 'clickable="true"' in n) \
            or find(xml, lambda n: 'resource-id="android:id/button1"' in n)
    if hit:
        x, y = centre(hit)
        rid = re.search(r'resource-id="([^"]*)"', hit)
        txt = re.search(r'text="([^"]*)"', hit)
        label = (rid.group(1) if rid else "") or (txt.group(1) if txt else "")
        print(time.strftime("%H:%M:%S"), "tap", x, y, label, flush=True)
        adb("shell", "input", "tap", str(x), str(y))
        time.sleep(3)
    else:
        time.sleep(2)
