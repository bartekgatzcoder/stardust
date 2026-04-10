# Starquake (Atari XL) — Disassembly Notes

## XEX File Structure

| Segment | File Offset | Load Address | End Address | Size (bytes) | Content |
|---------|-------------|-------------|-------------|--------------|---------|
| 1 | `$0002` | `$0A86` | `$0ADF` | 90 | Loader / title screen display list + init |
| 2 | `$0062` | `$02E0` | `$02E3` | 4 | DOS run address vector |
| 3 | `$006C` | `$0AF0` | `$A87F` | 40,336 | Main game code + data |

**Total file size**: 40,448 bytes

## Memory Map

```
$0080-$00FF  Zero-page variables (game state, pointers)
$0A86-$0A92  Display list (title screen)
$0A93-$0ADF  Title screen data + INIT1 routine
$0AF0-$0BD5  Early game code / data
$0BD6-$????  VBI handler (immediate VBI)
$1A15-$????  Entity initialization
$3388-$????  Game state setup
$3672-$37xx  Secondary game loop (entity updates + sound)
$4150-$4C25  Tile/entity lookup tables (~2,772 bytes)
$4Cxx-$52xx  Additional tile/map data (~1,644 bytes)
$5xxx-$6xxx  Compressed/packed game data (~1,564 bytes)
$6xxx-$7xxx  Level map data or tile graphics (~6,021 bytes)
$88xx-$97xx  Sprite shapes or screen data (~4,068 bytes)
$A358        Game initialization entry
$A381        Main display kernel (DMACTL + VCOUNT sync)
$A38E        VBI/DLI vector setup
$A3C6        DLI handler (color-splitting)
$A800        Post-decryption entry (copy protection passed)
$A845        RUN entry point (copy-protection checksum)
```

## Display System

### Display List (Title Screen — $0A86)
```
$0A86: $70 $70 $70 $70    — 4× blank 8 scanlines
$0A8A: $46 $93 $0A        — ANTIC mode 6 (20-col text) + LMS → $0A93
$0A8D: $70 $70            — 2× blank 8 scanlines
$0A8F: $02                — ANTIC mode 2 (normal text)
$0A90: $41 $86 $0A        — JVB → $0A86
```

### DLI Handler ($A3C6)
- Waits for WSYNC
- Loads color from `ICPTHz` (zero-page $27)
- Writes to COLPF2
- Calls subroutine at `$33FD`
- Acknowledges NMI via NMIST, returns with RTI

### Main Kernel ($A381)
```
LA381: STA DMACTL        — write DMA control
       ...               — VBI/DLI vector setup
LA3B8: LDA VCOUNT        — poll for scanline $80 (line 256)
       CMP #$80
       BNE LA3B8
       LDA #$3A          — DMACTL: normal playfield + PM DMA
       CLI               — enable interrupts
       BNE LA381         — loop (always taken)
```

## Player/Missile Graphics

### Registers Found
| Register | Address | Usage |
|----------|---------|-------|
| HPOSP0 | `$D000` | Horizontal position — zeroed during init (hides player 0) |
| PCOLR0 | `$02C0` | Indexed access `PCOLR0,X` / `PCOLR0,Y` — 16-slot entity color table |
| COLPM0 | `$D012` | Written with `ICPTHz OR #$0E` |
| COLPM1 | `$D013` | Set to `#$0E` (bright white) |
| DMACTL | `$D400` | `$3A` = standard playfield + player/missile DMA |
| SDMCTL | `$022F` | Set to `$00` in copy-protection fail path |

### Not Found in Static Disassembly
- PMBASE (`$D407`) — likely set in VBI or decrypted code
- GRAFP0-3 (`$D00C-$D00F`) — PMG shape data probably DMA'd, not CPU-written
- SIZEP0-3 (`$D008-$D00B`)
- GRACTL (`$D01D`)
- CHBAS/CHBASE (`$02F4`/`$D409`)

This suggests the VBI handler at `$0BD6` manages most PMG operations, and some code regions are encrypted/obfuscated at load time.

## Code vs Data Ratio

| Type | Lines | Percentage |
|------|-------|------------|
| Data (`.byte`) | 31,152 | 86.3% |
| Instructions | 3,815 | 10.6% |
| Labels/equates/directives | 1,107 | 3.1% |

**69 undocumented opcodes** found — indicates encrypted or packed code regions that are decrypted at runtime.

## Copy Protection

The `RUN` entry point at `$A845`:
1. Checksums bytes `$0A86`–`$0ADF` (segment 1)
2. Expects result `$DE`
3. **Pass**: Jumps to `$A800` — decrypts/copies code, warm-starts via `WARMSV`
4. **Fail**: Issues SIO format command (`DCOMND=$21`), disables display, infinite random-color loop

**Warning**: The copy protection includes a destructive anti-tamper mechanism (disk format command on failure).

## Label Statistics

| Category | Count |
|----------|-------|
| Named OS equates | 175 |
| Auto-generated equates (Lxxxx) | 120 |
| Auto-generated code labels | 778 |
| Named code labels (INIT1, RUNAD, RUN) | 3 |
| **Total labels** | **1,076** |

## Obfuscated Regions

The area around `$A38E` contains undocumented opcodes (RRA, ANC, NOP $xx,X) that are likely decrypted at runtime before VBI/DLI vectors become active. Static disassembly of these regions shows raw byte interpretation.

## Disassembler Used

**pcrow/atari_8bit_utils disasm** ([GitHub](https://github.com/pcrow/atari_8bit_utils/tree/main/disasm))
- Multi-pass code-flow tracing
- Built-in Atari OS labels (atari, cio, float)
- MADS assembler syntax output
- Undocumented 6502 opcode support
- XEX format auto-detection

**Note**: A debug assertion in the original disasm.c (`addr == 0x8D` crash) was patched to complete disassembly. This is a bug in the disassembler triggered by the game's use of zero-page address `$8D`.
