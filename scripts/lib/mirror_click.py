#!/usr/bin/env python3
"""Quartz-based single click at absolute screen coordinates, with a brief
down/up hold, as an alternative to AppleScript's `System Events click at`.
Usage: mirror_click.py x y [hold_seconds]
"""
import sys
import time
import Quartz

def post(event):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

def main():
    x, y = float(sys.argv[1]), float(sys.argv[2])
    hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.08

    move = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), Quartz.kCGMouseButtonLeft)
    post(move)
    time.sleep(0.05)

    down = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, (x, y), Quartz.kCGMouseButtonLeft)
    post(down)
    time.sleep(0.03)

    # A stationary down+up can be ignored by canvas-rendered UI (e.g.
    # Minecraft's Coherent Gameface/Ore UI) that expects at least one
    # pointer-move between down and up to treat it as a real touch rather
    # than a ghost event. A few px of jitter is harmless on real buttons.
    for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1), (0, 0)):
        drag = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDragged, (x + dx, y + dy), Quartz.kCGMouseButtonLeft)
        post(drag)
        time.sleep(0.02)

    time.sleep(hold)

    up = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, (x, y), Quartz.kCGMouseButtonLeft)
    post(up)

if __name__ == "__main__":
    main()
