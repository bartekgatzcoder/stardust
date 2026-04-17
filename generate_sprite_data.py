#!/usr/bin/env python3
"""
Generate VBXE sprite data from C64 BLOB sprite PNGs.

Composites body sprites (192x168, 8x scale) with eye overlays
(24x21, 1:1 C64 resolution), crops to 16x16, and maps to a
5-color palette stored as 8bpp indexed data for VBXE overlay use.

Outputs:
  data/sprite_frames.bin  - 11 frames x 256 bytes (16x16, 1 byte/pixel)
  data/sprite_palette.bin - 5 colors x 3 bytes (R, G, B)
  data/gameplay_xdl.bin   - VBXE XDL for 160-wide 8bpp gameplay overlay
"""

import os
import math
from PIL import Image

SPRITE_DIR = "assets/sprites"
DATA_DIR = "data"

# Frame definitions: (base_name, body_png, eyes_png)
FRAME_DEFS = [
    ("front",        "blob_front.png",        "blob_front_eyes.png"),
    ("walk_right_1", "blob_walk_right_1.png", "blob_walk_right_1_eyes.png"),
    ("walk_right_2", "blob_walk_right_2.png", "blob_walk_right_2_eyes.png"),
    ("walk_right_3", "blob_walk_right_3.png", "blob_walk_right_3_eyes.png"),
    ("walk_right_4", "blob_walk_right_4.png", "blob_walk_right_4_eyes.png"),
    ("walk_right_5", "blob_walk_right_5.png", "blob_walk_right_5_eyes.png"),
    ("walk_left_1",  "blob_walk_left_1.png",  "blob_walk_left_1_eyes.png"),
    ("walk_left_2",  "blob_walk_left_2.png",  "blob_walk_left_2_eyes.png"),
    ("walk_left_3",  "blob_walk_left_3.png",  "blob_walk_left_3_eyes.png"),
    ("walk_left_4",  "blob_walk_left_4.png",  "blob_walk_left_4_eyes.png"),
    ("walk_left_5",  "blob_walk_left_5.png",  "blob_walk_left_5_eyes.png"),
]

# 5-color palette (index 0 = transparent, handled automatically).
# Indices 1-5 are the non-transparent colors.
PALETTE = [
    (165, 115,  47),   # 1: brown / face
    (201, 212, 135),   # 2: yellow-green / ears
    (255, 255, 255),   # 3: white / eyes
    (139,  84,  41),   # 4: orange / body
    (251, 231,  94),   # 5: yellow / body highlight
]

SCALE = 8          # body sprites are 8x upscaled
CROP_W = 16
CROP_H = 16
FRAME_BYTES = CROP_W * CROP_H  # 256


def color_distance(a, b):
    """Euclidean RGB distance squared (no sqrt needed for comparisons)."""
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def map_pixel(r, g, b, a):
    """Map an RGBA pixel to a palette index (0 = transparent)."""
    if a < 128:
        return 0
    best_idx = 1
    best_dist = color_distance((r, g, b), PALETTE[0])
    for i, pal in enumerate(PALETTE[1:], start=2):
        d = color_distance((r, g, b), pal)
        if d < best_dist:
            best_dist = d
            best_idx = i
    return best_idx


def downsample_body(img):
    """Downsample a 192x168 body sprite to 24x21 by center-sampling."""
    img = img.convert("RGBA")
    out_w = img.width // SCALE   # 24
    out_h = img.height // SCALE  # 21
    pixels = []
    for y in range(out_h):
        row = []
        for x in range(out_w):
            sx = x * SCALE + SCALE // 2   # center sample at +4
            sy = y * SCALE + SCALE // 2
            row.append(img.getpixel((sx, sy)))
        pixels.append(row)
    return pixels


def load_eyes(img):
    """Load a 24x21 eye overlay as a 2D RGBA pixel array."""
    img = img.convert("RGBA")
    pixels = []
    for y in range(img.height):
        row = []
        for x in range(img.width):
            row.append(img.getpixel((x, y)))
        pixels.append(row)
    return pixels


def composite_frame(body_pixels, eye_pixels):
    """Composite eyes on top of body, crop to 16x16, return palette indices."""
    # Start with body, overlay eyes where non-transparent.
    h = min(len(body_pixels), len(eye_pixels))
    w = min(len(body_pixels[0]), len(eye_pixels[0]))

    indices = []
    for y in range(CROP_H):
        row = []
        for x in range(CROP_W):
            if y < h and x < w:
                br, bg, bb, ba = body_pixels[y][x]
                er, eg, eb, ea = eye_pixels[y][x]
                # Eyes override body where non-transparent.
                if ea >= 128:
                    r, g, b, a = er, eg, eb, ea
                else:
                    r, g, b, a = br, bg, bb, ba
            else:
                r, g, b, a = 0, 0, 0, 0
            row.append(map_pixel(r, g, b, a))
        indices.append(row)
    return indices


def print_frame_ascii(name, indices):
    """Print an ASCII art preview of a composited frame."""
    CHARS = ".BYWOX"  # 0=transparent, 1=brown, 2=yellow-green,
                       # 3=white, 4=orange, 5=yellow
    print(f"  {name}:")
    for row in indices:
        line = "    "
        for idx in row:
            line += CHARS[idx] if idx < len(CHARS) else "?"
        print(line)
    print()


def build_gameplay_xdl():
    """Build a VBXE XDL for gameplay: 160-wide LR 8bpp overlay at $20000.

    Structure mirrors the title XDL (data/xdl.bin) with two entries:

    Entry 1: 24 blank scanlines (no overlay, just repeat).
      XDLC byte 0: bit 2 (unused/reserved carry-over) + bit 5 (RPTL)
      XDLC byte 1: 0x00
      RPTL data: 23 (24 total scanlines)

    Entry 2: 192 active scanlines with graphics overlay.
      XDLC byte 0: bit 1 (GMON) + bit 5 (RPTL) + bit 6 (OVADR) = 0x62
      XDLC byte 1: bit 3 (OVATT) + bit 5 (LR) + bit 7 (END) = 0xA8
      RPTL data: 191 (192 total scanlines)
      OVADR data: addr $20000 (3 bytes LE) + step 160 (2 bytes LE)
      OVATT data: 0x11 (normal width + palette 1), 0xFF (max priority)
    """
    xdl = bytearray()

    # Entry 1: blank top (24 scanlines, no overlay).
    xdl += bytes([0x24, 0x00, 0x17])

    # Entry 2: active gameplay overlay.
    xdl += bytes([
        0x62, 0xA8,             # XDLC: GMON + RPTL + OVADR | OVATT + LR + END
        191,                    # RPTL: 191 extra = 192 total scanlines
        0x00, 0x00, 0x02,       # OVADR address: $020000 (low, mid, high)
        0xA0, 0x00,             # OVADR step: 160 (low, high)
        0x11,                   # OVATT: normal width (01) + palette 1 (bit 4)
        0xFF,                   # OVATT: priority 255 (overlay over all)
    ])
    return bytes(xdl)


def main():
    os.makedirs(DATA_DIR, exist_ok=True)

    all_frame_data = bytearray()
    all_indices = []
    palette_used = set()

    print("=== Sprite Data Generation ===\n")
    print(f"Frames: {len(FRAME_DEFS)}")
    print(f"Frame size: {CROP_W}x{CROP_H} = {FRAME_BYTES} bytes (8bpp)")
    print(f"Palette colors: {len(PALETTE)} (indices 1-{len(PALETTE)})")
    print()

    for name, body_file, eyes_file in FRAME_DEFS:
        body_img = Image.open(os.path.join(SPRITE_DIR, body_file))
        eyes_img = Image.open(os.path.join(SPRITE_DIR, eyes_file))

        body_pixels = downsample_body(body_img)
        eye_pixels = load_eyes(eyes_img)
        indices = composite_frame(body_pixels, eye_pixels)
        all_indices.append((name, indices))

        # Flatten to bytes (row-major, 1 byte per pixel).
        for row in indices:
            for idx in row:
                all_frame_data.append(idx)
                if idx > 0:
                    palette_used.add(idx)

    # Print ASCII previews.
    print("--- ASCII Previews ---\n")
    for name, indices in all_indices:
        print_frame_ascii(name, indices)

    # Save sprite frames.
    frames_path = os.path.join(DATA_DIR, "sprite_frames.bin")
    with open(frames_path, "wb") as f:
        f.write(all_frame_data)

    # Save palette (colors 1-5, 3 bytes each = 15 bytes).
    pal_path = os.path.join(DATA_DIR, "sprite_palette.bin")
    pal_data = bytearray()
    for r, g, b in PALETTE:
        pal_data += bytes([r, g, b])
    with open(pal_path, "wb") as f:
        f.write(pal_data)

    # Save gameplay XDL.
    xdl_data = build_gameplay_xdl()
    xdl_path = os.path.join(DATA_DIR, "gameplay_xdl.bin")
    with open(xdl_path, "wb") as f:
        f.write(xdl_data)

    # Statistics.
    print("--- Statistics ---\n")
    print(f"  Frames:           {len(FRAME_DEFS)}")
    print(f"  Frame size:       {CROP_W}x{CROP_H} = {FRAME_BYTES} bytes")
    print(f"  Total frame data: {len(all_frame_data)} bytes")
    print(f"  Palette entries:  {len(PALETTE)} (indices 1-{len(PALETTE)})")
    print(f"  Palette used:     {sorted(palette_used)}")
    print(f"  Palette data:     {len(pal_data)} bytes")
    print(f"  Gameplay XDL:     {len(xdl_data)} bytes")
    print(f"  Total output:     {len(all_frame_data) + len(pal_data) + len(xdl_data)} bytes")
    print()
    print(f"  {frames_path}: {len(all_frame_data)} bytes")
    print(f"  {pal_path}: {len(pal_data)} bytes")
    print(f"  {xdl_path}: {len(xdl_data)} bytes")

    # Compare title XDL vs gameplay XDL.
    title_xdl = open(os.path.join(DATA_DIR, "xdl.bin"), "rb").read()
    print(f"\n--- XDL Comparison ---\n")
    print(f"  Title XDL:    {title_xdl.hex(' ')}")
    print(f"  Gameplay XDL: {xdl_data.hex(' ')}")


if __name__ == "__main__":
    main()
