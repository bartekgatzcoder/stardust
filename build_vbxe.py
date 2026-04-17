#!/usr/bin/env python3
"""
Build Starquake_VBXE.xex — VBXE title overlay + gameplay sprites.

Layout: the copy-down segment ($BC00-$BFFF max, under C000 ROM):
  $BC00-$BC1D: original copy-down (patched JMP → $BC1E)
  $BC1E-$BC4F: handler-install code
  $BC50-$BDEB: handler binary (396 bytes) → copied to $9E00
  $BDEC-$BFFF: padding
"""
import struct, sys

def parse_xex(data):
    segments = []
    i = 0
    while i < len(data):
        if i+1 < len(data) and data[i] == 0xFF and data[i+1] == 0xFF: i += 2
        if i+3 >= len(data): break
        start = data[i]|(data[i+1]<<8); end = data[i+2]|(data[i+3]<<8); i += 4
        length = end - start + 1
        segments.append((start, end, data[i:i+length])); i += length
    return segments

game_data = bytearray(open('Starquake (v2).xex', 'rb').read())
game_segs = parse_xex(game_data)
RELOC = 0x1D80

def patch_game(runtime_addr, new_bytes):
    xex_addr = runtime_addr + RELOC
    offset = 0
    for s, e, d in game_segs:
        if s <= xex_addr <= e:
            foff = offset + 6 + (xex_addr - s)
            for i, b in enumerate(new_bytes):
                game_data[foff + i] = b
            return True
        offset += 6 + len(d)
    return False

# === Patch VBI at $0BD6 (18 bytes) ===
new_vbi = bytes([
    0xA5, 0xAA, 0x8D, 0x18, 0xD0,  # LDA $AA / STA $D018
    0xA9, 0x00, 0x85, 0x5F,         # LDA #0 / STA $5F
    0x4C, 0x00, 0x9E,               # JMP $9E00
    0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA
])
assert len(new_vbi) == 18
ok = patch_game(0x0BD6, new_vbi)
print(f"Patch VBI: {'OK' if ok else 'FAIL'}")

# === Find and patch the copy-down segment ===
cd_data_offset = None
i = 0
while i < len(game_data):
    if game_data[i]==0xFF and game_data[i+1]==0xFF: i += 2
    if i+3 >= len(game_data): break
    s = game_data[i]|(game_data[i+1]<<8); e = game_data[i+2]|(game_data[i+3]<<8)
    i += 4; l = e - s + 1
    if s == 0xBC00:
        cd_data_offset = i; break
    i += l

jmp_off = cd_data_offset + 26
assert game_data[jmp_off:jmp_off+3] == bytes([0x4C, 0xB9, 0x05])
game_data[jmp_off+1] = 0x1E; game_data[jmp_off+2] = 0xBC
print("Patch copy-down JMP: OK")

# === Build the extended copy-down segment ===
handler_bin = open('data/handler.bin', 'rb').read()
HANDLER_LEN = len(handler_bin)
HANDLER_SRC = 0xBC50   # In the segment
HANDLER_DEST = 0x9E00   # Runtime destination
GAME_START = 0x05B9

# Install code at $BC1E: copy handler from $BC50 to $9E00
ic = bytearray()
def e(b): ic.extend(b if isinstance(b,(bytes,bytearray)) else bytes(b))

# Source = $BC50, Dest = $9E00
e([0xA9, HANDLER_SRC & 0xFF]);  e([0x85, 0xFB])     # LDA #lo / STA $FB
e([0xA9, HANDLER_SRC >> 8]);    e([0x85, 0xFC])     # LDA #hi / STA $FC
e([0xA9, HANDLER_DEST & 0xFF]); e([0x85, 0xFD])     # LDA #lo / STA $FD
e([0xA9, HANDLER_DEST >> 8]);   e([0x85, 0xFE])     # LDA #hi / STA $FE

pages = HANDLER_LEN // 256
rem = HANDLER_LEN % 256

if pages > 0:
    e([0xA2, pages])        # LDX #pages
    e([0xA0, 0x00])         # LDY #0
    e([0xB1, 0xFB])         # LDA ($FB),Y
    e([0x91, 0xFD])         # STA ($FD),Y
    e([0xC8])               # INY
    e([0xD0, 0xF9])         # BNE -7 (byte_loop)
    e([0xE6, 0xFC])         # INC $FC
    e([0xE6, 0xFE])         # INC $FE
    e([0xCA])               # DEX
    e([0xD0, 0xF0])         # BNE -16 (page_loop)

if rem > 0:
    e([0xA0, 0x00])         # LDY #0
    e([0xB1, 0xFB])         # LDA ($FB),Y
    e([0x91, 0xFD])         # STA ($FD),Y
    e([0xC8])               # INY
    e([0xC0, rem])          # CPY #remainder
    e([0xD0, 0xF7])         # BNE -9 (rem_loop)

e([0x4C, GAME_START & 0xFF, GAME_START >> 8])  # JMP $05B9

print(f"Install code: {len(ic)} bytes at $BC1E-${0xBC1E+len(ic)-1:04X}")
assert 0xBC1E + len(ic) <= HANDLER_SRC, f"Install overflows into handler!"

# Build segment data
orig_cd = None
for s, e_addr, d in game_segs:
    if s == 0xBC00: orig_cd = bytearray(d); break

seg = bytearray(0x400)  # $BC00-$BFFF = 1024 bytes
seg[:30] = orig_cd[:30]
seg[26+1] = 0x1E; seg[26+2] = 0xBC       # Patched JMP
seg[0x1E:0x1E+len(ic)] = ic               # Install code
seg[0x50:0x50+HANDLER_LEN] = handler_bin  # Handler binary

seg_end = 0xBFFF
print(f"Segment: $BC00-${seg_end:04X} ({len(seg)} bytes)")

# === Rebuild game XEX ===
# Re-parse game_data to pick up VBI patch applied via patch_game()
game_segs = parse_xex(game_data)

output = bytearray()
for s, e_orig, d in game_segs:
    if s == 0xBC00:
        output += bytes([0xFF,0xFF, 0x00,0xBC, seg_end&0xFF,seg_end>>8])
        output += bytes(seg)
    elif s == 0x02E0:
        output += bytes([0xFF,0xFF, 0xE0,0x02, 0xE1,0x02]) + d
    else:
        output += bytes([0xFF,0xFF, s&0xFF,s>>8, e_orig&0xFF,e_orig>>8]) + d

open('Starquake_patched.xex', 'wb').write(output)

# Merge with VBXE loader
loader = open('vbxe_loader.xex', 'rb').read()
merged = loader + bytes(output)
open('Starquake_VBXE.xex', 'wb').write(merged)
print(f"Merged: {len(merged)} bytes")

# Verify
segs = parse_xex(merged)
for s, e, d in segs:
    lbl = ""
    if s == 0x02E2: lbl = f" (INITAD→${d[0]|d[1]<<8:04X})"
    if s == 0x02E0: lbl = f" (RUNAD→${d[0]|d[1]<<8:04X})"
    if s == 0xBC00: lbl = " (copy-down+handler)"
    print(f"  ${s:04X}-${e:04X} ({len(d)}){lbl}")
