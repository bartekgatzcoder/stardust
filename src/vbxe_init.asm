; ============================================================
; VBXE Title Screen Enhancement for Starquake (Atari XL/XE)
; Assembled with MADS assembler
;
; Uses VBXE XCOLOR mode + Colour Attribute Map to give each
; character cell independent foreground/background colours.
;
; In standard ANTIC mode 2, PF1 luminance is combined with
; PF2 hue — you can't get independent colours.  XCOLOR=1
; bypasses this: PF1 and PF2 become direct 8-bit palette
; indices with full RGB independence.
;
; The attribute map overrides the global colour registers
; per character cell:
;   byte 0 = fill pattern ($FF = solid PF2 background)
;   byte 1 = PF1 (foreground / text colour)
;   byte 2 = PF2 (background colour)
;   byte 3 = CTRL
;
; VRAM layout (MEMAC-B bank 0):
;   $0000 (CPU $4000): XDL — 12 bytes
;   $0100 (CPU $4100): Attribute map — 30 rows × 160 bytes
; ============================================================

; --- VBXE registers (base $D640) ---
VBXE        = $D640
VCTL        = VBXE+$00
XDLA0       = VBXE+$01
XDLA1       = VBXE+$02
XDLA2       = VBXE+$03
CSEL        = VBXE+$04
PSEL        = VBXE+$05
CR          = VBXE+$06
CG          = VBXE+$07
CB          = VBXE+$08
MEMB        = VBXE+$14

; --- Temp zero-page (safe during init) ---
PTR         = $E0          ; 16-bit VRAM write pointer
FG          = $E2          ; current row foreground colour

; ============================================================
        org $0480
; ============================================================
vbxe_init:
        ; --- Detect VBXE ---
        lda VCTL
        and #$F0
        cmp #$10           ; FX core 1.x?
        beq go
        rts
go:
        ; --- Enable MEMAC-B bank 0 ---
        ; Maps CPU $4000-$7FFF to VRAM $0000-$3FFF.
        lda #$80
        sta MEMB

        ; --- Write XDL to VRAM $0000 (CPU $4000) ---
        ldx #0
cpxdl:  lda xdl_data,x
        sta $4000,x
        inx
        cpx #xdl_end-xdl_data
        bne cpxdl

        ; --- Generate attribute map ---
        ; 30 rows × 40 columns × 4 bytes = 4800 bytes
        ; at VRAM $0100 (CPU $4100).
        lda #<$4100
        sta PTR
        lda #>$4100
        sta PTR+1

        ldx #0             ; row counter (0-29)
rowlp:  lda row_fg,x       ; foreground for this row
        sta FG

        ldy #0             ; byte offset within row (0-159)
collp:
        ; byte 0: fill pattern — $FF = solid PF2 background
        ;   (in ANTIC hires, '1' bits show PF2 colour,
        ;    '0' bits show COLBK — we want full PF2)
        lda #$FF
        sta (PTR),y
        iny

        ; byte 1: PF1 — foreground / text colour
        lda FG
        sta (PTR),y
        iny

        ; byte 2: PF2 — background colour (dark navy)
        lda #$92
        sta (PTR),y
        iny

        ; byte 3: CTRL — no special flags
        lda #$00
        sta (PTR),y
        iny

        cpy #160           ; 40 cells × 4 bytes
        bne collp

        ; Advance pointer by 160
        clc
        lda PTR
        adc #160
        sta PTR
        bcc noc
        inc PTR+1
noc:
        inx
        cpx #30
        bne rowlp

        ; --- Set C64-like palette ---
        jsr set_palette

        ; --- Point XDL to VRAM $0000 ---
        lda #$00
        sta XDLA0
        sta XDLA1
        sta XDLA2

        ; --- Enable XCOLOR + XDL ---
        ; bit 0 = XCOLOR  (8-bit palette indices, no hue/luma)
        ; bit 1 = XDL_ENABLED
        lda #$03
        sta VCTL

        ; --- Disable MEMAC-B (restore normal RAM) ---
        lda #$00
        sta MEMB

        rts

; ============================================================
; XDL — single entry covering all 240 visible scanlines.
;
; XDLC bits set:
;   3  = ATT       (colour attribute map on)
;   10 = MAPADR    (set map address + step)
;   11 = MAPPAR    (set map cell dimensions)
;   14 = RPTL      (repeat scanlines)
;   15 = END       (last entry)
;
; XDLC word = $0008 | $0400 | $0800 | $4000 | $8000 = $CC08
; ============================================================
xdl_data:
        .byte $08,$CC              ; XDLC (little-endian)
        ; --- MAPADR (5 bytes) ---
        .byte $00,$01,$00          ; map address = VRAM $000100
        .byte $A0,$00              ; step = 160 per map row
        ; --- MAPPAR (4 bytes) ---
        .byte $00                  ; H_SIZE = 0 → 8 pixels wide
        .byte $07                  ; V_SIZE = 7 → 8 scanlines tall
        .byte $00                  ; ANTIC palette bank = 0
        .byte $00                  ; Overlay palette bank = 0
        ; --- RPTL (1 byte) ---
        .byte 239                  ; 240 scanlines total
xdl_end:

; ============================================================
; Per-row foreground colours (30 entries, one per 8-scanline
; text row).  These are VBXE palette indices.
;
; Designed to approximate the C64 Starquake title screen:
;   top/bottom = dark (invisible on dark bg)
;   border rows = teal
;   title area = purple → blue → cyan gradient
;   credits = light blue
; ============================================================
row_fg:
        .byte $92              ; row 0  — overscan (invisible)
        .byte $92              ; row 1
        .byte $92              ; row 2
        .byte $96              ; row 3  — top border, dark teal
        .byte $AA              ; row 4  — teal
        .byte $9A              ; row 5  — light blue (top text)
        .byte $9A              ; row 6
        .byte $AA              ; row 7  — teal separator
        .byte $56              ; row 8  — purple (title start)
        .byte $58              ; row 9  — purple-blue
        .byte $7A              ; row 10 — blue
        .byte $9A              ; row 11 — blue-cyan
        .byte $AA              ; row 12 — cyan
        .byte $AC              ; row 13 — bright cyan
        .byte $AE              ; row 14 — white-cyan
        .byte $AC              ; row 15 — bright cyan
        .byte $AA              ; row 16 — cyan (subtitle area)
        .byte $9A              ; row 17 — light blue
        .byte $9A              ; row 18 — light blue (credits)
        .byte $AA              ; row 19 — teal
        .byte $9A              ; row 20 — light blue (credits)
        .byte $9A              ; row 21
        .byte $AA              ; row 22 — teal
        .byte $96              ; row 23 — dark teal border
        .byte $92              ; row 24 — invisible
        .byte $92              ; row 25
        .byte $92              ; row 26
        .byte $92              ; row 27
        .byte $92              ; row 28
        .byte $92              ; row 29

; ============================================================
; Set VBXE palette entries to C64-accurate RGB values.
; With XCOLOR=1, all 8 bits of a colour register are used
; as a direct palette index.
; ============================================================
set_palette:
        lda #$00
        sta PSEL               ; palette 0

        ; --- Grayscale range ($0x) → blue gradient ---
        ; These affect any screen using default grey colours.

        ; $00 → dark navy
        lda #$00
        sta CSEL
        lda #5
        sta CR
        lda #5
        sta CG
        lda #35
        sta CB

        ; $02
        lda #$02
        sta CSEL
        lda #8
        sta CR
        lda #10
        sta CG
        lda #44
        sta CB

        ; $04
        lda #$04
        sta CSEL
        lda #14
        sta CR
        lda #18
        sta CG
        lda #54
        sta CB

        ; $06
        lda #$06
        sta CSEL
        lda #22
        sta CR
        lda #28
        sta CG
        lda #64
        sta CB

        ; $08
        lda #$08
        sta CSEL
        lda #32
        sta CR
        lda #40
        sta CG
        lda #76
        sta CB

        ; $0A
        lda #$0A
        sta CSEL
        lda #45
        sta CR
        lda #55
        sta CG
        lda #88
        sta CB

        ; $0C
        lda #$0C
        sta CSEL
        lda #62
        sta CR
        lda #74
        sta CG
        lda #102
        sta CB

        ; $0E → bright cyan-white
        lda #$0E
        sta CSEL
        lda #82
        sta CR
        lda #100
        sta CG
        lda #118
        sta CB

        ; --- Purple range ($5x) ---

        ; $56 → deep purple
        lda #$56
        sta CSEL
        lda #52
        sta CR
        lda #18
        sta CG
        lda #64
        sta CB

        ; $58 → purple-blue
        lda #$58
        sta CSEL
        lda #44
        sta CR
        lda #26
        sta CG
        lda #76
        sta CB

        ; --- Blue range ($7x, $9x) ---

        ; $7A → blue
        lda #$7A
        sta CSEL
        lda #30
        sta CR
        lda #35
        sta CG
        lda #88
        sta CB

        ; $92 → dark blue (attribute map background)
        lda #$92
        sta CSEL
        lda #10
        sta CR
        lda #10
        sta CG
        lda #48
        sta CB

        ; $94 → standard Atari blue
        lda #$94
        sta CSEL
        lda #20
        sta CR
        lda #18
        sta CG
        lda #58
        sta CB

        ; $96 → dark teal
        lda #$96
        sta CSEL
        lda #28
        sta CR
        lda #30
        sta CG
        lda #68
        sta CB

        ; $98
        lda #$98
        sta CSEL
        lda #36
        sta CR
        lda #40
        sta CG
        lda #78
        sta CB

        ; $9A → light blue
        lda #$9A
        sta CSEL
        lda #48
        sta CR
        lda #55
        sta CG
        lda #92
        sta CB

        ; $9C
        lda #$9C
        sta CSEL
        lda #60
        sta CR
        lda #68
        sta CG
        lda #104
        sta CB

        ; $9E → bright blue
        lda #$9E
        sta CSEL
        lda #75
        sta CR
        lda #82
        sta CG
        lda #116
        sta CB

        ; --- Cyan range ($Ax) ---

        ; $AA → teal
        lda #$AA
        sta CSEL
        lda #18
        sta CR
        lda #70
        sta CG
        lda #78
        sta CB

        ; $AC → bright cyan
        lda #$AC
        sta CSEL
        lda #30
        sta CR
        lda #85
        sta CG
        lda #88
        sta CB

        ; $AE → white-cyan
        lda #$AE
        sta CSEL
        lda #52
        sta CR
        lda #102
        sta CG
        lda #100
        sta CB

        rts

; ============================================================
; INITAD trigger
; ============================================================
        org $02E2
        .word vbxe_init
