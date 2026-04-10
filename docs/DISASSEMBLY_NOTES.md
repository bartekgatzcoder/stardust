# Starquake (Atari XL) v2 — Disassembly Notes

## XEX Structure

| Seg | Load Address | End | Size | Content |
|-----|-------------|------|------|---------|
| 1 | `$2300` | `$62FF` | 16,384 | Game code + data (relocated to `$0580-$457F`) |
| 2 | `$6300` | `$BB7F` | 22,656 | Game code + data (relocated to `$4580-$9DFF`) |
| 3 | `$BC00` | `$BC1D` | 30 | RUN routine — copies seg 1+2 down by `$1D80` |
| 4 | `$02E0` | `$02E1` | 2 | RUNAD → `$BC00` |

**No loader, no copy protection, no INIT segments.**

## Startup Flow

1. `RUN` at `$BC00` copies `$2300-$BBFF` → `$0580-$9EFF` (offset -`$1D80`)
2. `JMP $05B9` — sets initial colours, then falls into main init at `$0600`

## Runtime Address Mapping

All disassembled addresses are **load addresses**. Subtract `$1D80` for runtime:

```
runtime = loaded - $1D80
$2300 → $0580 (start of relocated code)
$BBFF → $9E7F (end of relocated code)
```

## Title Screen

### Display

- **ANTIC mode `$F`** (GR.8 hires bitmap), 320×192, 1 bit/pixel
- Screen data at runtime `$A1F0` (loaded: not directly visible — generated at runtime)
- Display list at runtime `$395E` (loaded `$56DE`)
- 3× blank-8 + 192× mode F + JVB = 24 + 192 = 216 scanlines
- LMS reload at line 91 → `$B000` (page boundary crossing)
- DLIs at lines 47, 94, 144, 190

### Colours (set at entry point `$05B9`)

| Register | Value | Meaning |
|----------|-------|---------|
| COLBK (`$D01A`) | `$00` | Black border |
| COLOR4 (`$02C8`) | `$00` | Black border shadow |
| COLPF1 (`$D017`) | `$CA` | Green, luma 10 |
| COLOR1 (`$02C5`) | `$CA` | COLPF1 shadow |

In ANTIC mode F hires: lit pixels = COLPF1 luminance + COLPF2 hue.
Default COLPF2 = `$00` (black). Result: greenish-grey on black.

### DLI Handler (runtime `$0BC5`)

Changes colours mid-screen — responsible for any colour variation
between screen sections.

### VBI Handler (runtime `$0BD6`)

Immediate VBI — runs game logic every frame.

## Init Sequence (runtime `$0600`)

```
LDA $D40B       ; read VCOUNT
STA $3B
LDA $D20A       ; read random
STA $3C
LDX #$FF
TXS             ; reset stack
JSR $0B8D       ; ← sets up display list, DLI, VBI, NMIEN
JSR $20C5       ; further init
...
JSR $09E9       ; more setup
...clear memory, init entities...
JSR $337E
JSR $121A
JSR $1990
...game loop...
```

## Key Subroutine: Display Setup (`$0B8D`)

```
JSR $0B7B           ; wait for VCOUNT sync
LDA #$39
STA $D403           ; DLISTH = $39
LDA #$5E
STA $D402           ; DLISTL = $5E → display list at $395E
LDA #$C5
STA $0200           ; VDSLST low → DLI handler at $0BC5
LDA #$0B
STA $0201           ; VDSLST high
LDA #$D6
STA $0222           ; VVBLKI low → VBI handler at $0BD6
LDA #$0B
STA $0223           ; VVBLKI high
LDA #$C0
STA $D40E           ; NMIEN = $C0 (DLI + VBI enabled)
```
