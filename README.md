# Stardust — Starquake Atari XL/XE → VBXE Sprite Port

Port hi-resolution colour sprites from the C64 version of **Starquake**
to the Atari XL/XE version using **VBXE** hardware.

## Project Structure

```
Starquake (v2).xex          — Vanilla Atari XL binary (no loader)
disasm/
  starquake_v2_mads.asm     — Full disassembly (MADS syntax)
  starquake_v2_listing.asm  — Disassembly with address/hex listing
docs/
  DISASSEMBLY_NOTES.md      — Memory map, title screen analysis
tools/
  parse_xex.py              — XEX segment parser
```

## Key Findings (v2 binary)

- **No copy protection** — clean 4-segment XEX
- Code loads at `$2300-$BBFF`, relocated to `$0580-$9EFF` at runtime
- Title screen is **ANTIC mode F hires bitmap** (320×192, GR.8)
- Screen at `$A1F0`, display list at `$395E`
- 4 DLIs for colour changes across the screen
- Colours: green/grey on black (COLPF1=`$CA`, COLBK=`$00`)
