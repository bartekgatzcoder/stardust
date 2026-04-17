#!/usr/bin/env python3
"""
Build Starquake_VBXE.xex with VBXE title overlay + gameplay sprites.

Key insight: the game loads at $2300-$BB7F, then a copy-down routine
at $BC00 moves it to $0580-$9DFF (offset -$1D80). After copy-down,
$9E00+ is free. We patch the copy-down's final JMP $05B9 to first
go through our handler-install routine, which copies the sprite
handler + data to $9E00+, then starts the game.

Build chain:
  1. mads vbxe_sprite_handler.asm → data/handler.bin  (handler code)
  2. mads vbxe_loader.asm → vbxe_loader.xex  (VBXE init + data)
  3. python3 build_vbxe.py → Starquake_VBXE.xex  (merged + patched)
"""

import struct, sys, os

def parse_xex(data):
    segments = []
    i = 0
    while i < len(data):
        if i+1 < len(data) and data[i] == 0xFF and data[i+1] == 0xFF:
            i += 2
        if i+3 >= len(data): break
        start = data[i] | (data[i+1] << 8)
        end = data[i+2] | (data[i+3] << 8)
        i += 4
        length = end - start + 1
        segments.append((start, end, data[i:i+length]))
        i += length
    return segments

# Load the original game
game_data = bytearray(open('Starquake (v2).xex', 'rb').read())
game_segs = parse_xex(game_data)

RELOC_OFFSET = 0x1D80

def patch_game(runtime_addr, new_bytes):
    """Patch bytes in the game XEX data at a runtime address."""
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

def patch_raw(file_offset, new_bytes):
    """Patch bytes at a raw file offset."""
    for i, b in enumerate(new_bytes):
        game_data[file_offset + i] = b

# ============================================================
# Patch 1: VBI handler at $0BD6 (18 bytes)
# Original: LDA $AA / STA $D018 / LDA #0 / STA $5F / PLA/TAY/PLA/TAX/PLA/STA $D40F/RTI
# New: preserve original COLPF2 + DLI handling, then JMP to sprite handler
new_vbi = bytes([
    0xA5, 0xAA,             # LDA $AA      (COLPF2 shadow)
    0x8D, 0x18, 0xD0,       # STA $D018    (write COLPF2 hardware)
    0xA9, 0x00,             # LDA #$00
    0x85, 0x5F,             # STA $5F      (clear DLI counter)
    0x4C, 0x00, 0x9E,       # JMP $9E00    (sprite handler)
    0xEA, 0xEA, 0xEA,       # NOP padding
    0xEA, 0xEA, 0xEA,
])
assert len(new_vbi) == 18
ok = patch_game(0x0BD6, new_vbi)
print(f"Patch VBI at $0BD6: {'OK' if ok else 'FAIL'}")

# ============================================================
# Patch 2: Copy-down routine - change JMP $05B9 to JMP $BC20
#
# The copy-down is at $BC00-$BC1D. It ends with JMP $05B9.
# We change it to JMP $BC20 (our handler-install code).
# The handler-install code is appended at $BC1E.
#
# Original at $BC1A: 4C B9 05  (JMP $05B9)
# New:               4C 1E BC  (JMP $BC1E)

# Find the copy-down segment in the raw file
# Must account for FF FF headers
copydown_file_offset = None
i = 0
while i < len(game_data):
    if i+1 < len(game_data) and game_data[i] == 0xFF and game_data[i+1] == 0xFF:
        i += 2
    if i+3 >= len(game_data): break
    s = game_data[i] | (game_data[i+1] << 8)
    e = game_data[i+2] | (game_data[i+3] << 8)
    i += 4
    l = e - s + 1
    if s == 0xBC00:
        copydown_file_offset = i  # Points to start of segment DATA
        break
    i += l

if copydown_file_offset is None:
    print("ERROR: Could not find copy-down segment!")
    sys.exit(1)

# Patch JMP $05B9 → JMP $BC1E
# JMP is at $BC1A = 26 bytes into segment data
jmp_offset = copydown_file_offset + 26
assert game_data[jmp_offset] == 0x4C, f"Expected JMP at offset {jmp_offset}, got ${game_data[jmp_offset]:02X}"
assert game_data[jmp_offset+1] == 0xB9 and game_data[jmp_offset+2] == 0x05
game_data[jmp_offset+1] = 0x1E  # $BC1E
game_data[jmp_offset+2] = 0xBC
print("Patch copy-down JMP: OK")

# ============================================================
# Extend the copy-down segment to include handler-install code
#
# At $BC1E, we add code that:
# 1. Copies handler code from $BC80 to $9E00 (handler_len bytes)
# 2. Copies sprite frame data from $BC80+handler_len to $A000 (2816 bytes)
# 3. JMP $05B9 (original game start)
#
# The handler + sprite data will be appended to this segment.

handler_bin = open('data/handler.bin', 'rb').read()
sprite_bin = open('data/sprite_frames.bin', 'rb').read()
handler_len = len(handler_bin)
sprite_len = len(sprite_bin)
total_payload = handler_len + sprite_len  # 430 + 2816 = 3246

print(f"Handler: {handler_len} bytes, Sprites: {sprite_len} bytes")

# The install code copies from $BC80 to $9E00 (handler), then
# from $BC80+handler_len to $A000 (sprite data).
# Use a general-purpose page-copy loop.

# Layout in the segment:
# $BC00-$BC19: original copy-down (patched JMP)
# $BC1A-$BC1C: patched JMP $BC1E
# $BC1D: original $00 (unused)
# $BC1E-$BC7F: install code (~90 bytes)
# $BC80+: handler binary + sprite frame data

SRC_BASE = 0xBC80  # Where payload starts in segment
HANDLER_DEST = 0x9E00
SPRITE_DEST = 0xA000
GAME_START = 0x05B9

# Build the install code at $BC1E
install_code = bytearray()

def emit(b):
    install_code.extend(b if isinstance(b, (bytes, bytearray)) else bytes(b))

# Copy handler: SRC_BASE → $9E00, handler_len bytes
# Self-modifying copy loop (page-based)
handler_pages = handler_len // 256
handler_rem = handler_len % 256

# Set up source pointer at ZP $FB/$FC
emit([0xA9, SRC_BASE & 0xFF])         # LDA #<SRC_BASE
emit([0x85, 0xFB])                     # STA $FB
emit([0xA9, SRC_BASE >> 8])            # LDA #>SRC_BASE
emit([0x85, 0xFC])                     # STA $FC
# Set up dest pointer at ZP $FD/$FE
emit([0xA9, HANDLER_DEST & 0xFF])      # LDA #<HANDLER_DEST
emit([0x85, 0xFD])                     # STA $FD
emit([0xA9, HANDLER_DEST >> 8])        # LDA #>HANDLER_DEST
emit([0x85, 0xFE])                     # STA $FE

# Copy full pages
if handler_pages > 0:
    emit([0xA2, handler_pages])        # LDX #pages
    # @page_loop:
    emit([0xA0, 0x00])                 # LDY #0
    # @byte_loop:
    emit([0xB1, 0xFB])                 # LDA ($FB),Y
    emit([0x91, 0xFD])                 # STA ($FD),Y
    emit([0xC8])                       # INY
    emit([0xD0, 0xF9])                 # BNE @byte_loop (-7)
    emit([0xE6, 0xFC])                 # INC $FC (source page)
    emit([0xE6, 0xFE])                 # INC $FE (dest page)
    emit([0xCA])                       # DEX
    emit([0xD0, 0xF0])                 # BNE @page_loop (-16)

# Copy remaining bytes
if handler_rem > 0:
    emit([0xA0, 0x00])                 # LDY #0
    # @rem_loop:
    emit([0xB1, 0xFB])                 # LDA ($FB),Y
    emit([0x91, 0xFD])                 # STA ($FD),Y
    emit([0xC8])                       # INY
    emit([0xC0, handler_rem])          # CPY #remainder
    emit([0xD0, 0xF7])                 # BNE @rem_loop (-9)

# Now copy sprite data: continues from where handler ended
# Source continues at $FB/$FC (already advanced past handler pages)
# But need to advance past remainder too
# Simpler: just set up new pointers
sprite_src = SRC_BASE + handler_len
emit([0xA9, sprite_src & 0xFF])        # LDA #<sprite_src
emit([0x85, 0xFB])                     # STA $FB
emit([0xA9, sprite_src >> 8])          # LDA #>sprite_src
emit([0x85, 0xFC])                     # STA $FC
emit([0xA9, SPRITE_DEST & 0xFF])       # LDA #<SPRITE_DEST
emit([0x85, 0xFD])                     # STA $FD
emit([0xA9, SPRITE_DEST >> 8])         # LDA #>SPRITE_DEST
emit([0x85, 0xFE])                     # STA $FE

# Copy 11 pages (2816 bytes = 11 × 256)
emit([0xA2, 11])                       # LDX #11
# @spage_loop:
emit([0xA0, 0x00])                     # LDY #0
# @sbyte_loop:
emit([0xB1, 0xFB])                     # LDA ($FB),Y
emit([0x91, 0xFD])                     # STA ($FD),Y
emit([0xC8])                           # INY
emit([0xD0, 0xF9])                     # BNE @sbyte_loop
emit([0xE6, 0xFC])                     # INC $FC
emit([0xE6, 0xFE])                     # INC $FE
emit([0xCA])                           # DEX
emit([0xD0, 0xF0])                     # BNE @spage_loop

# Start the game
emit([0x4C, GAME_START & 0xFF, GAME_START >> 8])  # JMP $05B9

print(f"Install code: {len(install_code)} bytes (at $BC1E-${0xBC1E+len(install_code)-1:04X})")

# Verify it fits before payload area
assert 0xBC1E + len(install_code) <= SRC_BASE, \
    f"Install code overflows into payload area! {0xBC1E+len(install_code):04X} > {SRC_BASE:04X}"

# ============================================================
# Build the extended copy-down segment
# Original: $BC00-$BC1D (30 bytes)
# Extended: $BC00-$BC7F (install code) + $BC80+ (payload)

# Get original copy-down data
orig_copydown = None
for seg_start, seg_end, seg_data in game_segs:
    if seg_start == 0xBC00:
        orig_copydown = bytearray(seg_data)
        break

# Build new segment: original 30 bytes + install code + padding + payload
new_seg = bytearray(0x80)  # $BC00-$BC7F (128 bytes for code area)

# Copy original 30 bytes
new_seg[:30] = orig_copydown[:30]

# Patch JMP at offset 26
new_seg[26+1] = 0x1E  # JMP $BC1E
new_seg[26+2] = 0xBC

# Place install code at offset $1E
new_seg[0x1E:0x1E+len(install_code)] = install_code

# Append payload
new_seg += handler_bin
new_seg += sprite_bin

seg_end = 0xBC00 + len(new_seg) - 1
print(f"Extended segment: $BC00-${seg_end:04X} ({len(new_seg)} bytes)")

# ============================================================
# Rebuild the game XEX
# Replace the copy-down segment and RUNAD with extended version

output = bytearray()
for seg_start, seg_end_orig, seg_data in game_segs:
    if seg_start == 0xBC00:
        # Replace with extended segment
        output += bytes([0xFF, 0xFF,
                        0x00, 0xBC,
                        seg_end & 0xFF, seg_end >> 8])
        output += bytes(new_seg)
    elif seg_start == 0x02E0:
        # RUNAD - keep pointing to $BC00
        output += bytes([0xFF, 0xFF, 0xE0, 0x02, 0xE1, 0x02])
        output += seg_data
    else:
        # Normal segment
        output += bytes([0xFF, 0xFF,
                        seg_start & 0xFF, seg_start >> 8,
                        seg_end_orig & 0xFF, seg_end_orig >> 8])
        output += seg_data

# Save patched game
open('Starquake_patched.xex', 'wb').write(output)

# Merge: loader + patched game
loader = open('vbxe_loader.xex', 'rb').read()
merged = loader + bytes(output)
open('Starquake_VBXE.xex', 'wb').write(merged)
print(f"Merged: {len(merged)} bytes (loader {len(loader)} + game {len(output)})")

# Verify
print("\nVerification:")
segs = parse_xex(merged)
for s, e, d in segs:
    label = ""
    if s == 0x02E2: label = f" (INITAD → ${d[0]|d[1]<<8:04X})"
    if s == 0x02E0: label = f" (RUNAD → ${d[0]|d[1]<<8:04X})"
    if s == 0xBC00: label = f" (copy-down + handler install)"
    print(f"  ${s:04X}-${e:04X} ({len(d)} bytes){label}")
