; ============================================================
; VBXE Title Screen Enhancement for Starquake (Atari XL/XE)
; Assembled with MADS assembler
;
; Based on the Mad-Pascal VBXE library (tebe6502/Mad-Pascal).
;
; CRITICAL FIX: Register offsets are from $D640 base, so
; VIDEO_CONTROL = $D640+$00, not $D640+$40!
; The Mad-Pascal lib uses indirect (fxptr=$D600, Y=$40+),
; but for absolute addressing the offsets must be $00+.
; ============================================================

; --- Absolute VBXE register addresses ---
VBXE_VC     = $D640    ; VIDEO_CONTROL
VBXE_XDL0   = $D641    ; XDL address bits 0-7
VBXE_XDL1   = $D642    ; XDL address bits 8-15
VBXE_XDL2   = $D643    ; XDL address bits 16-18
VBXE_CSEL   = $D644    ; Colour index select
VBXE_PSEL   = $D645    ; Palette select
VBXE_CR     = $D646    ; Red   (0-127)
VBXE_CG     = $D647    ; Green (0-127)
VBXE_CB     = $D648    ; Blue  (0-127)
VBXE_BLT    = $D653    ; Blitter start/busy
VBXE_IRQ    = $D654    ; IRQ control
VBXE_P0     = $D655    ; Priority 0
VBXE_P1     = $D656    ; Priority 1
VBXE_P2     = $D657    ; Priority 2
VBXE_P3     = $D658    ; Priority 3
VBXE_MEMB   = $D65D    ; MEMAC-B control
VBXE_MEMC   = $D65E    ; MEMAC-A control
VBXE_MEMS   = $D65F    ; MEMAC-A bank select

; --- VIDEO_CONTROL bits ---
VC_XDL      = $01      ; Enable XDL
VC_XCOLOR   = $02      ; Extended colour mode

; --- VRAM addresses ---
VBXE_XDLADR = $0000    ; XDL in VRAM
VBXE_MAPADR = $1000    ; Colour map in VRAM

; --- MEMAC-A window ---
VBXE_WINDOW = $B000    ; 4K CPU window

; --- Temp zero-page ---
PTR         = $E0
FG          = $E2

; ============================================================
        org $0480
; ============================================================
vbxe_init:
        ; --- Detect VBXE ---
        lda VBXE_VC
        and #$F0
        cmp #$10
        beq detected
        rts
detected:

        ; --- Configure MEMAC-A ---
        ; Control = hi(VBXE_WINDOW) | $08 = $B0 | $08 = $B8
        ; Maps 4K at CPU $B000, CPU access on, ANTIC off.
        lda #$B8
        sta VBXE_MEMC

        ; --- Write XDL to VRAM $0000 ---
        ; Bank 0: MEMS = $80 + (VRAM addr / $1000)
        lda #$80
        sta VBXE_MEMS

        ldx #0
cpxdl:  lda xdl_data,x
        sta VBXE_WINDOW,x
        inx
        cpx #xdl_end-xdl_data
        bne cpxdl

        ; Unmap bank
        lda #$00
        sta VBXE_MEMS

        ; --- Fill colour map at VRAM $1000 ---
        ; Bank 1: MEMS = $80 + 1 = $81
        lda #$81
        sta VBXE_MEMS

        lda #<VBXE_WINDOW
        sta PTR
        lda #>VBXE_WINDOW
        sta PTR+1

        ldx #0             ; row counter (0-23)
rowlp:  lda row_fg,x
        sta FG

        ldy #0
collp:
        ; byte 0: PF0 colour / fill pattern
        lda #$FF
        sta (PTR),y
        iny

        ; byte 1: PF1 (foreground)
        lda FG
        sta (PTR),y
        iny

        ; byte 2: PF2 (background)
        lda #$94
        sta (PTR),y
        iny

        ; byte 3: palette config
        ; bits 7-6 = PF palette 0, bits 5-4 = OV palette 0
        lda #$00
        sta (PTR),y
        iny

        cpy #160           ; 40 cells × 4 bytes
        bne collp

        ; Advance PTR by 160
        clc
        lda PTR
        adc #160
        sta PTR
        bcc noc
        inc PTR+1
noc:
        inx
        cpx #24
        bne rowlp

        ; Unmap bank
        lda #$00
        sta VBXE_MEMS

        ; --- Set palette ---
        jsr set_palette

        ; --- Priority registers ---
        lda #$FF
        sta VBXE_P0
        lda #$00
        sta VBXE_P1
        sta VBXE_P2
        sta VBXE_P3
        sta VBXE_IRQ
        sta VBXE_BLT

        ; --- XDL address = VRAM $000000 ---
        lda #$00
        sta VBXE_XDL0
        sta VBXE_XDL1
        sta VBXE_XDL2

        ; --- Enable XDL + XCOLOR ---
        lda #VC_XDL|VC_XCOLOR  ; = $03
        sta VBXE_VC

        rts

; ============================================================
; XDL data — 23-byte structure matching Mad-Pascal vbxeinit.asm
;
; Entry 1: 24 blank scanlines
; Entry 2: 192 scanlines with colour map
;
; XDLC for entry 2 includes ALL field bits so the complete
; data block is present (matching the proven layout).
; ============================================================
xdl_data:
        ; --- Entry 1: blank top border ---
        .word $0020            ; XDLC = RPTL
        .byte 23               ; 24 scanlines

        ; --- Entry 2: main display ---
        ; XDLC = END|MAPON|RPTL|OVADR|CHBASE|MAPADR|MAPPAR|OVATT
        ; = $8000|$0008|$0020|$0040|$0100|$0200|$0400|$0800
        ; = $8F68
        .word $8F68
        .byte 191              ; RPTL: 192 scanlines

        ; OVADR (5 bytes): overlay address + step
        ; No overlay active, but fields must be present.
        .byte $00,$00,$00      ; overlay addr = 0
        .byte $40,$01          ; overlay step = 320

        ; CHBASE (1 byte)
        .byte $02              ; char base = $1000/$800 = 2

        ; MAPADR (5 bytes): map address + step
        .byte <VBXE_MAPADR    ; $00
        .byte >VBXE_MAPADR    ; $10
        .byte $00              ; bank 0
        .byte <160             ; step = 160
        .byte >160             ; = $00A0

        ; MAPPAR (4 bytes): scroll + cell dimensions
        .byte $00              ; HSCROL = 0
        .byte $00              ; VSCROL = 0
        .byte 7                ; WIDTH = 8 cells - 1
        .byte 7                ; HEIGHT = 8 scanlines - 1

        ; OVATT (2 bytes): palette + priority
        .byte $01              ; PF pal 0, OV pal 0, width=normal
        .byte $FF              ; priority: overlay above all
xdl_end:

; ============================================================
; Per-row foreground colours (24 rows of text)
; ============================================================
row_fg:
        .byte $96              ; row 0  — dark teal
        .byte $AA              ; row 1  — teal
        .byte $9C              ; row 2  — light blue
        .byte $9E              ; row 3  — bright blue
        .byte $AA              ; row 4  — teal
        .byte $96              ; row 5  — dark teal
        .byte $56              ; row 6  — purple
        .byte $58              ; row 7  — purple-blue
        .byte $7A              ; row 8  — blue
        .byte $9A              ; row 9  — light blue
        .byte $AA              ; row 10 — cyan
        .byte $AC              ; row 11 — bright cyan
        .byte $AE              ; row 12 — white-cyan
        .byte $AC              ; row 13 — bright cyan
        .byte $AA              ; row 14 — cyan
        .byte $9A              ; row 15 — light blue
        .byte $96              ; row 16 — dark teal
        .byte $9A              ; row 17 — light blue
        .byte $9C              ; row 18 — bright blue
        .byte $9A              ; row 19 — light blue
        .byte $96              ; row 20 — dark teal
        .byte $AA              ; row 21 — teal
        .byte $96              ; row 22 — dark teal
        .byte $94              ; row 23 — near-invisible

; ============================================================
; Palette setup
; ============================================================
set_palette:
        lda #$00
        sta VBXE_PSEL

        ; Grayscale ($0x) → blue gradient
        ldx #0
graylp: lda gray_idx,x
        sta VBXE_CSEL
        lda gray_r,x
        sta VBXE_CR
        lda gray_g,x
        sta VBXE_CG
        lda gray_b,x
        sta VBXE_CB
        inx
        cpx #8
        bne graylp

        ; Coloured entries
        ldx #0
clrlp:  lda col_idx,x
        beq paldone
        sta VBXE_CSEL
        lda col_r,x
        sta VBXE_CR
        lda col_g,x
        sta VBXE_CG
        lda col_b,x
        sta VBXE_CB
        inx
        bne clrlp
paldone:
        rts

gray_idx: .byte $00,$02,$04,$06,$08,$0A,$0C,$0E
gray_r:   .byte   5,  8, 14, 22, 32, 45, 62, 82
gray_g:   .byte   5, 10, 18, 28, 40, 55, 74,100
gray_b:   .byte  35, 44, 54, 64, 76, 88,102,118

col_idx:  .byte $56,$58,$7A,$92,$94,$96,$98,$9A,$9C,$9E,$AA,$AC,$AE,$00
col_r:    .byte  52, 44, 30, 10, 20, 28, 36, 48, 60, 75, 18, 30, 52
col_g:    .byte  18, 26, 35, 10, 18, 30, 40, 55, 68, 82, 70, 85,102
col_b:    .byte  64, 76, 88, 48, 58, 68, 78, 92,104,116, 78, 88,100

; ============================================================
        org $02E2
        .word vbxe_init
