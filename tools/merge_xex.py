#!/usr/bin/env python3
"""
Merge the VBXE init XEX with the original Starquake XEX.

Creates a combined XEX where:
  1. Original segment 1 loads ($0A86-$0ADF) — display list + INIT1
  2. Original segment 2 loads ($02E0-$02E3) — sets RUNAD + triggers INIT1
  3. VBXE init code loads ($0600-$07xx)
  4. VBXE INITAD loads ($02E2-$02E3) — triggers vbxe_init
  5. Original segment 3 loads ($0AF0-$A87F) — main game

This preserves the copy-protection checksum (bytes $0A86-$0ADF
are not modified) and adds VBXE colours to the title screen.
"""

import sys
import struct


def parse_xex(data: bytes):
    """Parse an Atari XEX file into segments."""
    segments = []
    pos = 0
    while pos < len(data):
        if pos + 2 > len(data):
            break
        marker = struct.unpack_from('<H', data, pos)[0]
        if marker == 0xFFFF:
            pos += 2
            if pos + 4 > len(data):
                break
        start = struct.unpack_from('<H', data, pos)[0]
        end = struct.unpack_from('<H', data, pos + 2)[0]
        pos += 4
        length = end - start + 1
        if pos + length > len(data):
            length = len(data) - pos
        seg_data = data[pos:pos + length]
        pos += length
        segments.append((start, end, seg_data))
    return segments


def build_xex(segments):
    """Build an Atari XEX file from segments."""
    out = bytearray()
    first = True
    for start, end, seg_data in segments:
        if first:
            out += struct.pack('<H', 0xFFFF)
            first = False
        out += struct.pack('<HH', start, end)
        out += seg_data
    return bytes(out)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <original.xex> <vbxe_init.xex> <output.xex>")
        sys.exit(1)

    orig_path, vbxe_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(orig_path, 'rb') as f:
        orig_data = f.read()
    with open(vbxe_path, 'rb') as f:
        vbxe_data = f.read()

    orig_segs = parse_xex(orig_data)
    vbxe_segs = parse_xex(vbxe_data)

    print(f"Original XEX: {len(orig_segs)} segments")
    for i, (s, e, d) in enumerate(orig_segs):
        print(f"  Seg {i+1}: ${s:04X}-${e:04X} ({len(d)} bytes)")

    print(f"VBXE init XEX: {len(vbxe_segs)} segments")
    for i, (s, e, d) in enumerate(vbxe_segs):
        print(f"  Seg {i+1}: ${s:04X}-${e:04X} ({len(d)} bytes)")

    # Separate VBXE segments: code vs INITAD trigger
    vbxe_code_segs = [s for s in vbxe_segs if s[0] != 0x02E2]
    vbxe_init_segs = [s for s in vbxe_segs if s[0] == 0x02E2]

    # Build merged XEX:
    #   original seg 1 + seg 2 (triggers INIT1)
    #   VBXE code segments
    #   VBXE INITAD (triggers vbxe_init)
    #   original seg 3 (main game)
    merged = []
    merged.extend(orig_segs[:2])       # segs 1-2 (display list + RUNAD/INITAD)
    merged.extend(vbxe_code_segs)      # VBXE code
    merged.extend(vbxe_init_segs)      # VBXE INITAD trigger
    merged.extend(orig_segs[2:])       # seg 3 (main game)

    result = build_xex(merged)

    with open(out_path, 'wb') as f:
        f.write(result)

    print(f"\nMerged XEX written to {out_path} ({len(result)} bytes)")

    # Verify
    merged_segs = parse_xex(result)
    print(f"Merged XEX: {len(merged_segs)} segments")
    for i, (s, e, d) in enumerate(merged_segs):
        print(f"  Seg {i+1}: ${s:04X}-${e:04X} ({len(d)} bytes)")


if __name__ == '__main__':
    main()
