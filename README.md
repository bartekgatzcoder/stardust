# Stardust — Starquake Atari XL/XE → VBXE Sprite Port

This project aims to port hi-resolution color sprites from the Commodore 64 version of **Starquake** to the Atari XL/XE version using **VBXE** hardware.

## Project Structure

```
Starquake (v1).xex          — Original Atari XL binary
disasm/
  starquake_mads.asm        — Full disassembly (MADS syntax)
  starquake_listing.asm     — Disassembly with address/hex listing
docs/
  DISASSEMBLY_NOTES.md      — Memory map, structure analysis, findings
tools/
  parse_xex.py              — XEX segment parser utility
```

## Stage 1: Disassembly (Complete)

Full disassembly of the Atari binary using [pcrow/atari_8bit_utils disasm](https://github.com/pcrow/atari_8bit_utils/tree/main/disasm) — a multi-pass 6502 disassembler with code-flow tracing and built-in Atari OS label support.

- **36,074 lines** of MADS-compatible assembly
- **Atari OS symbols** auto-applied (175 named equates)
- **Code-flow tracing** identified 848 code labels
- **Undocumented opcodes** preserved (69 instances — encrypted/obfuscated regions)

## Key Findings

| Area | Address | Notes |
|------|---------|-------|
| Display list | `$0A86` | Title screen: ANTIC mode 6 + mode 2 |
| Init routine | `$0A93` | `INIT1` — sets up display list |
| VBI handler | `$0BD6` | Immediate VBI — drives game logic + PMG |
| DLI handler | `$A3C6` | Color-splitting DLI for playfield colors |
| Main kernel | `$A381` | DMACTL + VCOUNT sync loop |
| Game loop | `$3672` | Entity updates + sound, VCOUNT-timed |
| Game init | `$A358` | Player init, entity setup |
| Run address | `$A845` | Copy-protection checksum → `$A800` |
| Data (86%) | Various | Graphics, maps, tile data dominate the binary |

## Next Stages (Planned)

- **Stage 2**: Identify and extract sprite/character graphics data
- **Stage 3**: Analyze C64 sprite format and map to VBXE blitter overlay sprites
- **Stage 4**: Implement VBXE sprite rendering code
- **Stage 5**: Integration and testing
