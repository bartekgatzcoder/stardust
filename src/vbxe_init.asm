; ============================================================
; VBXE Title Screen Enhancement for Starquake (Atari XL/XE)
; Assembled with MADS assembler
;
; Uses VBXE Colour Attribute Map to add per-character colors
; to the title screen, creating a C64-like blue/purple/cyan
; gradient effect.
;
; VRAM layout (bank 0, $0000-$3FFF):
;   $0000: XDL data (~40 bytes)
;   $0100: Attribute map for ANTIC mode 6 line (20 cells)
;   $0150: Attribute map for ANTIC mode 2 line (40 cells)
; ============================================================

; --- VBXE registers (base $D640) ---
VBXE        = $D640
VCTL        = VBXE+$00   ; VIDEO_CONTROL
XDLA0       = VBXE+$01   ; XDL address bits 0-7
XDLA1       = VBXE+$02   ; XDL address bits 8-15
XDLA2       = VBXE+$03   ; XDL address bits 16-18
CSEL        = VBXE+$04   ; Colour register select
PSEL        = VBXE+$05   ; Palette select
CR          = VBXE+$06   ; Red (7-bit)
CG          = VBXE+$07   ; Green (7-bit)
CB          = VBXE+$08   ; Blue (7-bit)
MEMB        = VBXE+$14   ; MEMAC-B control

; --- Atari shadow registers ---
COLOR0      = $02C4       ; COLPF0 shadow
COLOR1      = $02C5       ; COLPF1 shadow
COLOR2      = $02C6       ; COLPF2 shadow
COLOR3      = $02C7       ; COLPF3 shadow
COLOR4      = $02C8       ; COLBK shadow

; --- XDL control word bits ---
XDLC_ATT    = $0008       ; Enable attribute map
XDLC_MAPADR = $0400       ; Set map address + step
XDLC_MAPPAR = $0800       ; Set map cell parameters
XDLC_RPTL   = $4000       ; Repeat N scanlines
XDLC_END    = $8000       ; Last XDL entry

; --- VRAM offsets (CPU addr = $4000 + offset) ---
VRAM_XDL    = $4000        ; XDL at VRAM $0000
VRAM_MAP6   = $4100        ; Mode 6 attr map at VRAM $0100
VRAM_MAP2   = $4150        ; Mode 2 attr map at VRAM $0150

; ============================================================
        org $0600
; ============================================================
vbxe_init:
        ; --- Detect VBXE ---
        ; Reading VIDEO_CONTROL returns core version ($1x).
        ; On a stock Atari, $D640 is open bus / $FF.
        lda VCTL
        and #$F0
        cmp #$10           ; FX core 1.x?
        beq detected
        jmp vexit          ; No VBXE, bail out
detected:

        ; --- Enable MEMAC-B bank 0 ---
        ; Maps $4000-$7FFF to VRAM $0000-$3FFF.
        lda #$80
        sta MEMB

        ; --- Clear VRAM work area ---
        lda #$00
        tax
clr0:  sta $4000,x
        dex
        bne clr0
clr1:  sta $4100,x
        dex
        bne clr1
clr2:  sta $4200,x
        dex
        bne clr2

        ; --- Write XDL to VRAM $0000 ---
        ldx #0
cpxdl: lda xdl_data,x
        sta VRAM_XDL,x
        inx
        cpx #xdl_end-xdl_data
        bne cpxdl

        ; --- Write mode 6 attribute map (20 cells) ---
        ldx #0
cpm6:  lda map6_data,x
        sta VRAM_MAP6,x
        inx
        cpx #map6_end-map6_data
        bne cpm6

        ; --- Generate mode 2 attribute map (40 cells) ---
        ; All 40 characters: light cyan text on dark blue.
        ldx #0
gm2:   lda #$9E           ; PF0 = bright blue
        sta VRAM_MAP2,x
        inx
        lda #$9A           ; PF1 = light blue (text)
        sta VRAM_MAP2,x
        inx
        lda #$92           ; PF2 = dark blue (background)
        sta VRAM_MAP2,x
        inx
        lda #$00           ; CTRL
        sta VRAM_MAP2,x
        inx
        cpx #160           ; 40 cells * 4 bytes
        bne gm2

        ; --- Set C64-like RGB palette entries ---
        jsr set_palette

        ; --- Point XDL to VRAM $0000 ---
        lda #$00
        sta XDLA0
        sta XDLA1
        sta XDLA2

        ; --- Enable XCOLOR + XDL ---
        lda #$03
        sta VCTL

        ; --- Set Atari colour registers (C64 blue theme) ---
        lda #$92           ; dark blue
        sta COLOR4         ; background
        lda #$96           ; medium blue
        sta COLOR2         ; PF2
        lda #$0E           ; white
        sta COLOR1         ; PF1 (text)
        lda #$9A           ; light blue
        sta COLOR0         ; PF0

        ; --- Disable MEMAC-B (restore normal RAM) ---
        lda #$00
        sta MEMB

vexit:  rts

; ============================================================
; Set VBXE palette entries to C64-accurate RGB values.
; Each entry: write PSEL=0, CSEL=index, then CR/CG/CB.
; ============================================================
set_palette:
        lda #$00
        sta PSEL           ; palette 0

        ; --- Background / border colours ---

        ; $92 = dark blue bg -> C64 blue (53,40,121)
        lda #$92
        sta CSEL
        lda #26
        sta CR
        lda #20
        sta CG
        lda #60
        sta CB

        ; $96 = medium blue -> C64 med blue
        lda #$96
        sta CSEL
        lda #32
        sta CR
        lda #28
        sta CG
        lda #72
        sta CB

        ; $9A = light blue
        lda #$9A
        sta CSEL
        lda #45
        sta CR
        lda #47
        sta CG
        lda #95
        sta CB

        ; $9E = bright blue
        lda #$9E
        sta CSEL
        lda #55
        sta CR
        lda #55
        sta CG
        lda #105
        sta CB

        ; --- STARQUAK gradient colours ---

        ; $56 = purple (S)
        lda #$56
        sta CSEL
        lda #55
        sta CR
        lda #20
        sta CG
        lda #67
        sta CB

        ; $58 = purple-blue (T)
        lda #$58
        sta CSEL
        lda #45
        sta CR
        lda #25
        sta CG
        lda #75
        sta CB

        ; $7A = blue (A)
        lda #$7A
        sta CSEL
        lda #35
        sta CR
        lda #35
        sta CG
        lda #85
        sta CB

        ; $88 = deep blue (R)
        lda #$88
        sta CSEL
        lda #25
        sta CR
        lda #45
        sta CG
        lda #90
        sta CB

        ; $AA = cyan (Q-U)
        lda #$AA
        sta CSEL
        lda #20
        sta CR
        lda #70
        sta CG
        lda #80
        sta CB

        ; $AC = bright cyan (A2)
        lda #$AC
        sta CSEL
        lda #25
        sta CR
        lda #82
        sta CG
        lda #82
        sta CB

        ; $AE = white-cyan (K)
        lda #$AE
        sta CSEL
        lda #40
        sta CR
        lda #95
        sta CG
        lda #90
        sta CB

        ; $0E = white
        lda #$0E
        sta CSEL
        lda #115
        sta CR
        lda #115
        sta CG
        lda #115
        sta CB

        ; $00 = black
        lda #$00
        sta CSEL
        lda #0
        sta CR
        lda #0
        sta CG
        lda #0
        sta CB

        rts

; ============================================================
; XDL data — controls VBXE display per-scanline.
;
; Title screen ANTIC display list structure:
;   4x $70 = 32 blank scanlines
;   $46 LMS = ANTIC mode 6 (16 scanlines, 20 chars)
;   2x $70 = 16 blank scanlines
;   $02    = ANTIC mode 2 (8 scanlines, 40 chars)
;   $41    = JVB
; ============================================================
xdl_data:
        ; Entry 1: 32 blank scanlines — no attr map
        .word XDLC_RPTL
        .byte 31                       ; repeat=31 -> 32 lines

        ; Entry 2: 16 scanlines (mode 6) — attr map ON
        .word XDLC_ATT|XDLC_MAPADR|XDLC_MAPPAR|XDLC_RPTL
        ; MAPADR: 3-byte address + 2-byte step
        .byte <$0100, >$0100, $00      ; VRAM $000100
        .byte <0, >0                   ; step = 0
        ; MAPPAR: H_SIZE, V_SIZE, antic_pal, ov_pal
        .byte $00                      ; 8-pixel wide cells
        .byte $0F                      ; 16-scanline tall cells
        .byte $00, $00                 ; default palettes
        ; RPTL
        .byte 15                       ; 16 scanlines

        ; Entry 3: 16 blank scanlines — attr map off
        .word XDLC_RPTL
        .byte 15

        ; Entry 4: 8 scanlines (mode 2) — attr map ON
        .word XDLC_ATT|XDLC_MAPADR|XDLC_MAPPAR|XDLC_RPTL
        .byte <$0150, >$0150, $00      ; VRAM $000150
        .byte <0, >0                   ; step = 0
        .byte $00                      ; 8-pixel wide
        .byte $07                      ; 8-scanline tall
        .byte $00, $00
        .byte 7                        ; 8 scanlines

        ; Entry 5: rest of frame — end
        .word XDLC_END|XDLC_RPTL
        .byte 167                      ; remaining scanlines
xdl_end:

; ============================================================
; Attribute map for ANTIC mode 6 line (20 chars x 4 bytes).
; Format per cell: PF0, PF1, PF2, CTRL
;
; Positions 0-5 and 14-19 are spaces (dark blue).
; Positions 6-13 are "STARQUAK" with a purple->cyan gradient.
; ============================================================
map6_data:
        ; Spaces (positions 0-5)
        :6 .byte $92,$92,$92,$00

        ; S — deep purple
        .byte $56,$56,$92,$00
        ; T — purple-blue
        .byte $58,$58,$92,$00
        ; A — blue
        .byte $7A,$7A,$92,$00
        ; R — deep blue
        .byte $88,$88,$92,$00
        ; Q — cyan-blue
        .byte $9A,$9A,$92,$00
        ; U — cyan
        .byte $AA,$AA,$92,$00
        ; A — bright cyan
        .byte $AC,$AC,$92,$00
        ; K — white-cyan
        .byte $AE,$AE,$92,$00

        ; Spaces (positions 14-19)
        :6 .byte $92,$92,$92,$00
map6_end:

; ============================================================
; INITAD trigger — loaded at $02E2 to call vbxe_init
; ============================================================
        org $02E2
        .word vbxe_init
