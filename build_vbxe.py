#!/usr/bin/env python3
"""
Build Starquake_VBXE.xex with:
1. VBXE title screen overlay (existing)
2. VBXE gameplay sprite overlay (new)
   - 16x16 color sprites replace 8x16 P/M sprites
   - Sprite handler at $9E00, frame data at $A000

Build: mads vbxe_loader.asm → vbxe_loader.xex
       python3 build_vbxe.py → Starquake_VBXE.xex
"""

import struct, sys

def parse_xex(data):
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
    return bytes([0xFF, 0xFF,
                  start & 0xFF, start >> 8,
                  end & 0xFF, end >> 8]) + bytes(data)

# Load the original game
game_data = bytearray(open('Starquake (v2).xex', 'rb').read())
game_segs = parse_xex(game_data)

RELOC_OFFSET = 0x1D80

def patch_game(runtime_addr, new_bytes):
    xex_addr = runtime_addr + RELOC_OFFSET
    offset = 0
    for seg_start, seg_end, seg_data in game_segs:
        seg_header = 6
        if seg_start <= xex_addr <= seg_end:
            file_offset = offset + seg_header + (xex_addr - seg_start)
            for i, b in enumerate(new_bytes):
                game_data[file_offset + i] = b
            return True
        offset += seg_header + len(seg_data)
    return False

# ============================================================
# Patch: New VBI handler at $0BD6 (18 bytes)
#
# The new VBI just jumps to our sprite handler at $9E00.
# The handler takes care of both title/gameplay modes and
# exits via JMP XITVBV.
#
# Original VBI was:
#   LDA $AA / STA $D018 / LDA #$00 / STA $5F /
#   PLA / TAY / PLA / TAX / PLA / STA $D40F / RTI
#
# New VBI (18 bytes):
#   LDA $AA         ; 2 bytes - original COLPF2 handling
#   STA $D018       ; 3 bytes - write COLPF2 hardware register
#   LDA #$00        ; 2 bytes - clear DLI counter
#   STA $5F         ; 2 bytes - (preserves original behavior)
#   JMP $9E00       ; 3 bytes - jump to VBXE sprite handler
#   NOP * 4         ; 4 bytes - padding (unreachable)
# Total: 2+3+2+2+3+4 = 16. Need 2 more.
#
# Actually, the handler does its own register save/restore
# and calls XITVBV, so we need to NOT do PLA/TAY etc here.
# But the original VBI saves/restores regs with PLA/TAX/etc.
# The OS VBI framework pushes A/X/Y before calling the
# deferred VBI vector. XITVBV pops them and does RTI.
#
# Wait: looking at the original VBI ending:
#   PLA / TAY / PLA / TAX / PLA / STA $D40F / RTI
# This is the standard XITVBV equivalent inline.
# Our handler calls JMP XITVBV which does the same thing.
# But the handler also pushes A/X/Y at entry!
# That means the stack will have DOUBLE-pushed registers.
#
# Fix: Don't push/pop in the handler. The OS already did it
# before calling the deferred VBI. Just do the work and JMP XITVBV.
#
# But the handler modifies A/X/Y. If we JMP XITVBV, it will
# pop the OS-saved values. So the handler can freely use regs.
# We DON'T need PHA/TXA etc in the handler.
#
# Updated handler: remove the push/pop, just do work + JMP XITVBV.
#
# VBI patch: handle COLPF2 first (preserves original behavior),
# then jump to handler.

new_vbi = bytes([
    0xA5, 0xAA,             # LDA $AA      (COLPF2 shadow)
    0x8D, 0x18, 0xD0,       # STA $D018    (write COLPF2 hardware)
    0xA9, 0x00,             # LDA #$00
    0x85, 0x5F,             # STA $5F      (clear DLI counter)
    0x4C, 0x00, 0x9E,       # JMP $9E00    (sprite handler)
    0xEA, 0xEA, 0xEA,       # NOP padding (unreachable)
    0xEA, 0xEA, 0xEA,       # NOP padding
])
assert len(new_vbi) == 18, f"VBI is {len(new_vbi)} bytes, need 18"

ok = patch_game(0x0BD6, new_vbi)
print(f"Patch VBI at $0BD6: {'OK' if ok else 'FAIL'}")

# Write the patched game
open('Starquake_patched.xex', 'wb').write(game_data)

# Build final merged XEX: loader + patched game
loader = open('vbxe_loader.xex', 'rb').read()
merged = loader + bytes(game_data)
open('Starquake_VBXE.xex', 'wb').write(merged)
print(f"Merged: {len(merged)} bytes (loader {len(loader)} + game {len(game_data)})")
