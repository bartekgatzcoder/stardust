#!/usr/bin/env python3
"""
Build Starquake_VBXE.xex — VBXE title overlay + gameplay VBXE sprite.

Segment $BC00-$BFFF layout:
  $BC00-$BC1D  original copy-down code (30 bytes, patched JMP → $BC1E)
  $BC1E-$BC7A  install code (~93 bytes)
                 1. copy handler  $BC80 → $9E00   (291 bytes)
                 2. copy sprite   $BDB0 → VRAM $30000 via MEMAC_A=$8C
                 3. zero ZP $FB-$FE
                 4. JMP $05B9
  $BC80-$BDA2  handler binary (291 bytes)
  $BDB0-$BEAF  sprite frame 0 raw (256 bytes, 16×16 8bpp)
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
# Replace inline toggle with JMP $9E00, padded with NOPs.
# The handler at $9E00 handles both title and gameplay paths.
new_vbi = bytes([0x4C, 0x00, 0x9E] + [0xEA] * 15)
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

# === Layout constants ===
handler_bin  = open('data/handler.bin', 'rb').read()
sprite_bin   = open('data/sprite_frames.bin', 'rb').read()[0:256]   # frame 0
HANDLER_LEN  = len(handler_bin)   # 291 bytes
HANDLER_SRC  = 0xBC80             # XEX segment address of handler binary
HANDLER_DEST = 0x9E00             # Runtime destination (copied by install code)
SPRITE_SRC   = 0xBDB0             # XEX segment address of sprite frame data
VRAM_SPRITE  = 0x4000             # MEMAC window addr for VRAM $30000 (bank 12)
MEMAC_SPRITE = 0x8C               # MEMAC_A bank 12 ($80 | 12)
MEMAC_REG    = 0xD65D
GAME_START   = 0x05B9

# Handler is now the Phase-1 minimal VBI (XDL-address-only). Size may
# grow in later phases when sprite-draw routines are added alongside it.
assert HANDLER_LEN < 256, f"Handler too large: {HANDLER_LEN} bytes"

# === Build install code at $BC1E ===
ic = bytearray()
def e(b): ic.extend(b if isinstance(b, (bytes, bytearray)) else bytes(b))

# --- Part 1: copy handler from HANDLER_SRC to HANDLER_DEST ---
pages = HANDLER_LEN // 256   # 1
rem   = HANDLER_LEN  % 256   # 35

e([0xA9, HANDLER_SRC & 0xFF]);  e([0x85, 0xFB])     # LDA #lo / STA $FB
e([0xA9, HANDLER_SRC >> 8]);    e([0x85, 0xFC])     # LDA #hi / STA $FC
e([0xA9, HANDLER_DEST & 0xFF]); e([0x85, 0xFD])     # LDA #lo / STA $FD
e([0xA9, HANDLER_DEST >> 8]);   e([0x85, 0xFE])     # LDA #hi / STA $FE

if pages > 0:
    e([0xA2, pages])       # LDX #pages
    e([0xA0, 0x00])        # LDY #0           ← page_loop
    e([0xB1, 0xFB])        # LDA ($FB),Y      ← byte_loop
    e([0x91, 0xFD])        # STA ($FD),Y
    e([0xC8])              # INY
    e([0xD0, 0xF9])        # BNE byte_loop
    e([0xE6, 0xFC])        # INC $FC
    e([0xE6, 0xFE])        # INC $FE
    e([0xCA])              # DEX
    e([0xD0, 0xF0])        # BNE page_loop

if rem > 0:
    e([0xA0, 0x00])        # LDY #0           ← rem_loop
    e([0xB1, 0xFB])        # LDA ($FB),Y
    e([0x91, 0xFD])        # STA ($FD),Y
    e([0xC8])              # INY
    e([0xC0, rem])         # CPY #rem
    e([0xD0, 0xF7])        # BNE rem_loop

# --- Part 2: copy sprite frame 0 from SPRITE_SRC to VRAM $30000 ---
# VRAM $30000 = bank 12 ($8C), window address = $4000.
e([0xA9, MEMAC_SPRITE])           # LDA #$8C
e([0x8D, MEMAC_REG & 0xFF, MEMAC_REG >> 8])  # STA $D65D (MEMAC_A)

e([0xA9, SPRITE_SRC & 0xFF]);  e([0x85, 0xFB])  # LDA #lo / STA $FB
e([0xA9, SPRITE_SRC >> 8]);    e([0x85, 0xFC])  # LDA #hi / STA $FC
e([0xA9, VRAM_SPRITE & 0xFF]); e([0x85, 0xFD])  # LDA #lo / STA $FD
e([0xA9, VRAM_SPRITE >> 8]);   e([0x85, 0xFE])  # LDA #hi / STA $FE

# 256-byte copy using INY overflow trick (Y: 0→255→0 triggers exit).
e([0xA0, 0x00])   # LDY #0           ← sprite_loop
e([0xB1, 0xFB])   # LDA ($FB),Y
e([0x91, 0xFD])   # STA ($FD),Y
e([0xC8])         # INY
e([0xD0, 0xF9])   # BNE sprite_loop  (256 iterations)

e([0xA9, 0x00])                               # LDA #0
e([0x8D, MEMAC_REG & 0xFF, MEMAC_REG >> 8])  # STA $D65D (clear MEMAC_A)

# --- Part 3: zero ZP temporaries $FB-$FE ---
e([0xA9, 0x00])   # LDA #0
e([0x85, 0xFB])   # STA $FB
e([0x85, 0xFC])   # STA $FC
e([0x85, 0xFD])   # STA $FD
e([0x85, 0xFE])   # STA $FE

# --- Part 4: jump to game entry ---
e([0x4C, GAME_START & 0xFF, GAME_START >> 8])  # JMP $05B9

print(f"Install code: {len(ic)} bytes at $BC1E-${0xBC1E+len(ic)-1:04X}")

# === Sanity checks ===
ic_end = 0xBC1E + len(ic)
assert ic_end <= HANDLER_SRC, \
    f"Install code overflows into handler! ic_end=${ic_end:04X} > HANDLER_SRC=${HANDLER_SRC:04X}"
assert HANDLER_SRC + HANDLER_LEN <= SPRITE_SRC, \
    f"Handler overflows into sprite! end=${HANDLER_SRC+HANDLER_LEN:04X} > SPRITE_SRC=${SPRITE_SRC:04X}"
assert SPRITE_SRC + 256 <= 0xC000, \
    f"Sprite overflows past $BFFF! end=${SPRITE_SRC+256:04X}"

# === Build the extended copy-down segment ===
orig_cd = None
for s, e_addr, d in game_segs:
    if s == 0xBC00: orig_cd = bytearray(d); break

seg = bytearray(0x400)              # $BC00-$BFFF = 1024 bytes
seg[:30] = orig_cd[:30]             # original copy-down (30 bytes)
seg[26+1] = 0x1E; seg[26+2] = 0xBC # patched JMP → $BC1E

ic_off = 0xBC1E - 0xBC00           # = $1E = 30
seg[ic_off:ic_off+len(ic)] = ic

h_off = HANDLER_SRC - 0xBC00
seg[h_off:h_off+HANDLER_LEN] = handler_bin

s_off = SPRITE_SRC - 0xBC00
seg[s_off:s_off+256] = sprite_bin

seg_end = 0xBFFF
print(f"Segment: $BC00-${seg_end:04X} ({len(seg)} bytes)")
print(f"  copy-down:  $BC00-$BC1D (30 bytes)")
print(f"  install:    $BC1E-${ic_end-1:04X} ({len(ic)} bytes)")
print(f"  handler:    ${HANDLER_SRC:04X}-${HANDLER_SRC+HANDLER_LEN-1:04X} ({HANDLER_LEN} bytes)")
print(f"  sprite:     ${SPRITE_SRC:04X}-${SPRITE_SRC+255:04X} (256 bytes)")

# === Rebuild game XEX ===
game_segs = parse_xex(game_data)

output = bytearray()
for s, e_orig, d in game_segs:
    if s == 0xBC00:
        output += bytes([0xFF,0xFF, 0x00,0xBC, seg_end&0xFF, seg_end>>8])
        output += bytes(seg)
    elif s == 0x02E0:
        output += bytes([0xFF,0xFF, 0xE0,0x02, 0xE1,0x02]) + d
    else:
        output += bytes([0xFF,0xFF, s&0xFF,s>>8, e_orig&0xFF,e_orig>>8]) + d

open('Starquake_patched.xex', 'wb').write(output)

# Merge with VBXE loader
loader = open('vbxe_loader.xex', 'rb').read()
# Regression guard: any loader segment that extends into $BB80-$BBFF
# gets picked up by the game's copy-down ($2300-$BBFF to $0580-$9E7F)
# and corrupts the sprite/character data table that lives at RAM
# $9E00-$9E7F. Fail the build loudly instead of shipping a broken XEX.
for _ls, _le, _ld in parse_xex(loader):
    if _ls < 0xBB80 and _le >= 0xBB80:
        raise SystemExit(
            f"loader segment ${_ls:04X}-${_le:04X} overlaps copy-down "
            f"tail $BB80-$BBFF; game RAM $9E00-$9E7F would be "
            f"corrupted. Shrink or split the loader."
        )
merged = loader + bytes(output)
open('Starquake_VBXE.xex', 'wb').write(merged)
print(f"Merged XEX: {len(merged)} bytes")

# === Verify merged segments ===
print("\nSegments in Starquake_VBXE.xex:")
segs = parse_xex(merged)
for s, e, d in segs:
    lbl = ""
    if s == 0x02E2: lbl = f" (INITAD→${d[0]|d[1]<<8:04X})"
    if s == 0x02E0: lbl = f" (RUNAD→${d[0]|d[1]<<8:04X})"
    if s == 0xBC00: lbl = " (copy-down+install+handler+sprite)"
    print(f"  ${s:04X}-${e:04X} ({len(d)} bytes){lbl}")

# Spot-check VBI patch
# The merged XEX now has two segments that cover XEX $2956: the RLE
# loader segment (overlay data) and the real game seg 1 ($2300-$62FF).
# The OS loads segments in order, so the LAST segment to cover a given
# runtime address is the one that ends up in RAM. Pick the game segment
# by size: the RLE segment is 14909 bytes, game seg 1 is 16384 bytes,
# and only game seg 1 extends past $62FF.
game_seg1 = next(
    (d for s, e, d in segs if s == 0x2300 and e >= 0x62FF),
    None,
)
if game_seg1 is not None:
    vbi_off = 0x0BD6 + RELOC - 0x2300
    actual = bytes(game_seg1[vbi_off:vbi_off+3])
    expected = bytes([0x4C, 0x00, 0x9E])
    status = "OK" if actual == expected else "FAIL"
    print(
        f"\nVBI bytes at runtime $0BD6 (xex ${0x0BD6+RELOC:04X}): "
        f"{actual.hex()}"
    )
    print(f"Expected: {expected.hex()}  {status}")
