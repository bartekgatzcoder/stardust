; ============================================================
; VBXE test — minimal overlay following st2vbxe approach.
;
; st2vbxe by Piotr Fusik (pfusik) is a working VBXE viewer.
; This code mirrors its exact register/XDL setup:
;
;  - MEMAC-B ($D65D) for VRAM access (NOT MEMAC-A)
;  - XDL at VRAM $10000 (bank 4)
;  - Overlay bitmap at VRAM $10100
;  - VIDEO_CONTROL = $05 (xdl_enabled | no_trans)
;  - XDL: 20 blank + 200 lines GMON overlay, step=320
;  - Palette written via indirect (fx_ptr),Y addressing
;
; Fills the overlay with colour bands to prove VBXE works.
; ============================================================

; VRAM addresses (matching st2vbxe)
xdl_vbxe    = $10000
scr_vbxe    = $10100

; Zero page
fx_ptr      = $E0       ; 2 bytes — pointer to $D600 or $D700
zptr        = $E2       ; 2 bytes — VRAM write pointer

; ============================================================
        org $0480
; ============================================================
vbxe_init:
        ; --- Detect VBXE (matches st2vbxe fx_detect) ---
        lda #<$D600
        sta fx_ptr
        lda #>$D600
        sta fx_ptr+1
        jsr fx_try
        beq found
        inc fx_ptr+1       ; try $D700
        jsr fx_try
        beq found
        rts                ; no VBXE
fx_try: ldy #$40           ; CORE_VERSION
        lda (fx_ptr),y
        cmp #$10           ; FX 1.xx?
        rts
found:

        ; --- Map MEMAC-B to bank 4 ---
        ; VRAM $10000-$13FFF → CPU $4000-$7FFF
        ; Bank = $10000 >> 14 = 4.  Enable = $80.
        ldy #$5D            ; FX_MEMB
        lda #$84            ; $80 | 4
        sta (fx_ptr),y

        ; --- Copy XDL to VRAM $10000 = CPU $4000 ---
        ldy #xdl_len-1
cpxdl:  lda xdl,y
        sta $4000,y
        dey
        bpl cpxdl

        ; --- Fill overlay bitmap ---
        ; VRAM $10100 = CPU $4100.
        ; Fill ~48 pages (12288 bytes ≈ 38 rows of 320px).
        ; Colour = (page / 6) + 1, giving bands of entries 1-8.
        lda #<$4100
        sta zptr
        lda #>$4100
        sta zptr+1

        ldx #0              ; page counter
fillpg: txa
        lsr
        lsr                 ; /4 → gives ~8 colour bands
        clc
        adc #1              ; palette entries 1-13
        ldy #0
fillby: sta (zptr),y
        iny
        bne fillby
        inc zptr+1
        inx
        cpx #48             ; 48 pages ≈ 38 rows
        bne fillpg

        ; --- Unmap MEMAC-B ---
        ldy #$5D
        lda #0
        sta (fx_ptr),y

        ; --- Set palette (palette 0, entries 0-13) ---
        ldy #$44            ; FX_CSEL
        lda #0
        sta (fx_ptr),y
        iny                 ; FX_PSEL ($45)
        lda #0              ; palette 0
        sta (fx_ptr),y

        ; Entry 0: dark navy background
        jsr pal_0_5_5_35

        ; Entry 1: deep purple
        ldy #$46
        lda #50
        sta (fx_ptr),y
        iny
        lda #10
        sta (fx_ptr),y
        iny
        lda #60
        sta (fx_ptr),y

        ; Entry 2: purple-blue
        jsr pal_40_20_75

        ; Entry 3: blue
        jsr pal_25_35_90

        ; Entry 4: cyan-blue
        jsr pal_20_55_95

        ; Entry 5: teal
        jsr pal_15_65_80

        ; Entry 6: cyan
        jsr pal_20_80_80

        ; Entry 7: bright cyan
        jsr pal_40_95_90

        ; Entry 8: white-cyan
        ldy #$46
        lda #65
        sta (fx_ptr),y
        iny
        lda #105
        sta (fx_ptr),y
        iny
        lda #110
        sta (fx_ptr),y

        ; Entries 9-13: repeat bright tones
        jsr pal_40_95_90
        jsr pal_20_80_80
        jsr pal_15_65_80
        jsr pal_20_55_95
        jsr pal_25_35_90

        ; --- Enable VBXE display ---
        ; (Matches st2vbxe setup_vbxe)
        ldy #$40            ; VIDEO_CONTROL
        lda #$05            ; xdl_enabled | no_trans
        sta (fx_ptr),y
        iny                 ; XDL_ADR0
        lda #<[xdl_vbxe]
        sta (fx_ptr),y
        iny                 ; XDL_ADR1
        lda #>[xdl_vbxe]
        sta (fx_ptr),y
        iny                 ; XDL_ADR2
        lda #0              ; xdl_vbxe >> 16 = 1, but >>16 of $10000 = 1
        ora #1
        sta (fx_ptr),y

        rts

; --- Palette helper subroutines (auto-advance CSEL) ---
pal_0_5_5_35:
        ldy #$46
        lda #5
        sta (fx_ptr),y
        iny
        lda #5
        sta (fx_ptr),y
        iny
        lda #35
        sta (fx_ptr),y
        rts

pal_40_20_75:
        ldy #$46
        lda #40
        sta (fx_ptr),y
        iny
        lda #20
        sta (fx_ptr),y
        iny
        lda #75
        sta (fx_ptr),y
        rts

pal_25_35_90:
        ldy #$46
        lda #25
        sta (fx_ptr),y
        iny
        lda #35
        sta (fx_ptr),y
        iny
        lda #90
        sta (fx_ptr),y
        rts

pal_20_55_95:
        ldy #$46
        lda #20
        sta (fx_ptr),y
        iny
        lda #55
        sta (fx_ptr),y
        iny
        lda #95
        sta (fx_ptr),y
        rts

pal_15_65_80:
        ldy #$46
        lda #15
        sta (fx_ptr),y
        iny
        lda #65
        sta (fx_ptr),y
        iny
        lda #80
        sta (fx_ptr),y
        rts

pal_20_80_80:
        ldy #$46
        lda #20
        sta (fx_ptr),y
        iny
        lda #80
        sta (fx_ptr),y
        iny
        lda #80
        sta (fx_ptr),y
        rts

pal_40_95_90:
        ldy #$46
        lda #40
        sta (fx_ptr),y
        iny
        lda #95
        sta (fx_ptr),y
        iny
        lda #90
        sta (fx_ptr),y
        rts

; ============================================================
; XDL — matches st2vbxe exactly.
;
; Entry 1: 20 blank lines (OVOFF + RPTL)
; Entry 2: 200 lines overlay (GMON + RPTL + OVADR + END)
; ============================================================
xdl:
        .word $0024         ; XDLC = OVOFF($04) | RPTL($20)
        .byte 19            ; 20 blank lines

        .word $8062         ; XDLC = GMON($02) | RPTL($20)
                            ;      | OVADR($40) | END($8000)
        .byte 199           ; 200 lines

        ; OVADR: 3-byte address + 2-byte step
        .byte <[scr_vbxe&$FFFF]   ; $00
        .byte >[scr_vbxe&$FFFF]   ; $01
        .byte 1                     ; bank 1 ($10000>>16)
        .word 320                   ; step = 320 bytes/line
xdl_len = *-xdl

; ============================================================
        org $02E2
        .word vbxe_init
