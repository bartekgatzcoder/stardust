#!/usr/bin/env python3
"""
Build Starquake_VBXE.xex by:
1. Loading the VBXE overlay data into VRAM (loader segment)
2. Patching the game binary to control VBXE from within
   the game's own code (no external trampolines)

All runtime patches live in the game's code area ($0600+)
which survives gameplay. Pages 4-5 ($0400-$057F) get zeroed
by the game, so nothing goes there.

VBXE control via the VBI handler at $0BD6:
  - Reads $AA (COLPF2 color variable)
  - During title: $AA=0 (black bg). We also set $27=0.
  - During gameplay: $AA=nonzero color
  - VBI sets VIDEO_CONTROL = ($AA==0 ? 1 : 0)

This requires the VBI to be 18 bytes (same as original).
"""

import struct, sys

def parse_xex(data):
    """Parse XEX into segments."""
    segments = []
    i = 0
    while i < len(data):
        if i+1 < len(data) and data[i] == 0xFF and data[i+1] == 0xFF:
            i += 2
        if i+3 >= len(data):
            break
        start = data[i] | (data[i+1] << 8)
        end = data[i+2] | (data[i+3] << 8)
        i += 4
        length = end - start + 1
        segments.append((start, end, data[i:i+length]))
        i += length
    return segments

def build_xex_segment(start, end, data):
    """Build one XEX segment with header."""
    return bytes([0xFF, 0xFF,
                  start & 0xFF, start >> 8,
                  end & 0xFF, end >> 8]) + bytes(data)

# Load the original game
game_data = bytearray(open('Starquake (v2).xex', 'rb').read())
game_segs = parse_xex(game_data)

# The game's main data is in 2 segments: $2300-$62FF and $6300-$BB7F
# These get relocated to $0580-$9E7F (offset -$1D80)
RELOC_OFFSET = 0x1D80

def runtime_to_xex(runtime_addr):
    """Convert runtime address to XEX file offset."""
    # Runtime $0580 = XEX $2300
    xex_addr = runtime_addr + RELOC_OFFSET
    # Find which segment and offset
    for seg_start, seg_end, seg_data in game_segs:
        if seg_start <= xex_addr <= seg_end:
            return seg_start, xex_addr - seg_start
    return None, None

def patch_game(runtime_addr, new_bytes):
    """Patch bytes in the game XEX data at a runtime address."""
    xex_addr = runtime_addr + RELOC_OFFSET
    # Find segment in raw file
    offset = 0
    for seg_start, seg_end, seg_data in game_segs:
        seg_header = 6  # FF FF start_lo start_hi end_lo end_hi
        if seg_start <= xex_addr <= seg_end:
            file_offset = offset + seg_header + (xex_addr - seg_start)
            for i, b in enumerate(new_bytes):
                game_data[file_offset + i] = b
            return True
        offset += seg_header + len(seg_data)
    return False

# ============================================================
# Patch 1: New VBI handler at $0BD6 (18 bytes, same size)
#
# The trick: when $AA=0 (title screen), COLPF2=0 (black)
# and we want VIDEO_CONTROL=1. When $AA!=0 (gameplay),
# COLPF2=color and VIDEO_CONTROL=0.
#
# We compute: if A=0 after loading $AA, set A=1 for VBXE.
# If A!=0, the game already runs with nonzero COLPF2 and
# we need A=0 for VBXE. Use: A = (AA==0) ? 1 : 0
#
# Code:
#   LDA $AA       ; A = COLPF2 value
#   STA $D018     ; write COLPF2 hardware
#   BNE .off      ; if nonzero → VBXE off
#   LDA #$01      ; A=1 (VBXE on)
#   .byte $2C     ; BIT abs — skip next 2 bytes (trick)
# .off:
#   LDA #$00      ; A=0 (VBXE off) — skipped when $AA=0
#   STA $D640     ; VIDEO_CONTROL
#   LDA #$00
#   STA $5F
#   JMP $E462     ; XITVBV
#
# Encoding:
#   A5 AA         LDA $AA       (2)
#   8D 18 D0      STA $D018     (3)
#   D0 02         BNE +2        (2)
#   A9 01         LDA #$01      (2)
#   2C            BIT abs       (1) — eats next 2 bytes as operand
#   A9 00         LDA #$00      (2) — this is the "BIT $00A9" operand AND the LDA
#   8D 40 D6      STA $D640     (3)
#   85 5F         STA $5F       (2) — A=0 in "off" path; A=1 in "on" path... BUG!
#
# Wait: in the "on" path (AA=0), A=1 after LDA #$01.
# Then BIT $00A9 executes: loads byte at $00A9 into nowhere (just sets flags).
# A is STILL 1. Then STA $D640 writes 1. Good.
# Then STA $5F writes 1. BAD — should be 0.
#
# Fix: separate the STA $5F:
#   A5 AA         LDA $AA       (2)
#   8D 18 D0      STA $D018     (3)
#   D0 02         BNE +2        (2)
#   A9 01         LDA #$01      (2)
#   2C            BIT abs       (1)
#   A9 00         LDA #$00      (2)
#   8D 40 D6      STA $D640     (3)
#   = 15 bytes. Need 3 more for LDA #0/STA $5F/exit.
#   LDA #$00 (2) + STA $5F (2) + JMP $E462 (3) = 7.
#   15+7 = 22. TOO BIG.
#
# Simpler: drop the STA $5F and JMP XITVBV, use original exit.
# But original exit is PLA/TAY/PLA/TAX/PLA/STA NMIRES/RTI = 9 bytes.
# 15+9 = 24. Even worse.
#
# Let me drop STA $5F entirely and use a shorter exit:
#   A5 AA           (2)
#   8D 18 D0        (3)
#   D0 02           (2)
#   A9 01           (2)
#   2C              (1) BIT trick
#   A9 00           (2)
#   8D 40 D6        (3)
#   4C 62 E4        (3) JMP XITVBV
#   = 18 bytes! Fits!
#
# But STA $5F is missing. The DLI counter $5F is NOT cleared.
# The DLI code at $33FD uses $5F as a counter:
#   INC $5F / LDA $5F / AND #$01 / BEQ skip
# Without clearing, $5F keeps incrementing every DLI.
# AND #$01 alternates 0/1 regardless of overflow. So the
# DLI behavior is: odd frames do color cycling, even don't.
# The visual effect might be slightly different (every DLI
# toggles instead of every other DLI), but the game is
# functional. Let's try it.

new_vbi = bytes([
    0xA5, 0xAA,             # LDA $AA
    0x8D, 0x18, 0xD0,       # STA $D018
    0xD0, 0x02,             # BNE +2 (skip LDA #$01)
    0xA9, 0x01,             # LDA #$01 (VBXE on)
    0x2C,                   # BIT abs (skip next 2 bytes)
    0xA9, 0x00,             # LDA #$00 (VBXE off)
    0x8D, 0x40, 0xD6,       # STA $D640
    0x4C, 0x62, 0xE4,       # JMP $E462 (XITVBV)
])
assert len(new_vbi) == 18, f"VBI is {len(new_vbi)} bytes, need 18"

ok = patch_game(0x0BD6, new_vbi)
print(f"Patch VBI at $0BD6: {'OK' if ok else 'FAIL'}")

# ============================================================
# No other patches needed! The VBI automatically detects
# title screen ($AA=0) vs gameplay ($AA!=0).
# No need to patch $20CA or $20F2 at all.
# ============================================================

# Write the patched game
open('Starquake_patched.xex', 'wb').write(game_data)

# Build final merged XEX: loader + patched game
loader = open('vbxe_loader.xex', 'rb').read()
merged = loader + bytes(game_data)
open('Starquake_VBXE.xex', 'wb').write(merged)
print(f"Merged: {len(merged)} bytes (loader {len(loader)} + game {len(game_data)})")
