#!/usr/bin/env python3
"""Write a deterministic 32x32 RGBA pixel-art PNG for the Files import check."""

from __future__ import annotations

import hashlib
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".scratch" / "Craftberry-Texture-Import-32x32.png"
WIDTH = 32
HEIGHT = 32

TRANSPARENT = (0, 0, 0, 0)
OUTLINE = (20, 24, 34, 255)
CYAN = (52, 188, 196, 255)
CYAN_LIGHT = (137, 247, 246, 255)
GOLD = (227, 176, 48, 255)
GOLD_LIGHT = (255, 229, 119, 255)
WOOD = (142, 87, 52, 255)
WOOD_LIGHT = (205, 143, 90, 255)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def make_pixels() -> bytes:
    pixels = [[TRANSPARENT for _ in range(WIDTH)] for _ in range(HEIGHT)]

    # A diagonal cyan blade with a dark outline and a bright edge.
    for y in range(2, 22):
        center_x = 26 - y
        for x in range(center_x - 2, center_x + 3):
            if 0 <= x < WIDTH:
                pixels[y][x] = OUTLINE
        for x in range(center_x - 1, center_x + 2):
            if 0 <= x < WIDTH:
                pixels[y][x] = CYAN
        if 0 <= center_x < WIDTH:
            pixels[y][center_x] = CYAN_LIGHT

    # The guard, grip and pommel make the fixture easy to recognize in-app.
    for x in range(2, 11):
        pixels[20][x] = OUTLINE
        pixels[21][x] = OUTLINE
    for x in range(3, 10):
        pixels[20][x] = GOLD
        pixels[21][x] = GOLD_LIGHT if x in (4, 8) else GOLD
    for y in range(22, 29):
        for x in range(3, 9):
            pixels[y][x] = OUTLINE if x in (3, 8) else WOOD
        pixels[y][5] = WOOD_LIGHT
    for x in range(3, 9):
        pixels[29][x] = OUTLINE
    for x in range(4, 8):
        pixels[28][x] = GOLD

    rows = bytearray()
    for row in pixels:
        rows.append(0)  # PNG filter: None.
        for red, green, blue, alpha in row:
            rows.extend((red, green, blue, alpha))
    return bytes(rows)


def main() -> None:
    raw = make_pixels()
    png = b"\x89PNG\r\n\x1a\n"
    png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0))
    png += png_chunk(b"IDAT", zlib.compress(raw, level=9))
    png += png_chunk(b"IEND", b"")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(png)
    print(f"Wrote {OUTPUT}")
    print(f"PNG: {WIDTH}x{HEIGHT}, RGBA, {len(png)} bytes")
    print(f"SHA-256: {hashlib.sha256(png).hexdigest()}")


if __name__ == "__main__":
    main()
