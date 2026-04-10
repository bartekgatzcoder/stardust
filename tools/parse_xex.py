#!/usr/bin/env python3
"""Parse an Atari XEX (binary load) file and print all segments."""

import struct
import sys


def parse_xex(path):
    with open(path, "rb") as f:
        data = f.read()

    pos = 0
    size = len(data)

    # Verify FF FF header.
    if size < 2 or data[0] != 0xFF or data[1] != 0xFF:
        print("Error: not a valid XEX file (missing FF FF header)")
        sys.exit(1)
    pos = 2

    segment = 0
    print(f"File: {path}")
    print(f"Size: {size} bytes")
    print()
    print(f"{'Seg':>4}  {'Offset':>8}  {'Start':>6}  {'End':>6}  {'Length':>6}")
    print(f"{'---':>4}  {'------':>8}  {'-----':>6}  {'---':>6}  {'------':>6}")

    while pos < size:
        # Check for optional FF FF marker between segments.
        if pos + 1 < size and data[pos] == 0xFF and data[pos + 1] == 0xFF:
            pos += 2

        if pos + 3 >= size:
            break

        file_offset = pos
        start_addr = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        end_addr = struct.unpack_from("<H", data, pos)[0]
        pos += 2

        if end_addr < start_addr:
            print(f"Warning: segment {segment} has end (${end_addr:04X}) < start (${start_addr:04X}), stopping.")
            break

        data_len = end_addr - start_addr + 1

        if pos + data_len > size:
            print(f"Warning: segment {segment} data truncated (need {data_len}, have {size - pos}).")
            data_len = size - pos

        segment += 1
        print(f"{segment:4d}  {file_offset:08X}  ${start_addr:04X}  ${end_addr:04X}  {data_len:6d}")

        pos += data_len

    print()
    print(f"Total segments: {segment}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file.xex>")
        sys.exit(1)
    parse_xex(sys.argv[1])
