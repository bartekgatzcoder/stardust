; ============================================================
; VBXE Title Screen Colour Enhancement for Starquake
; Assembled with MADS assembler
;
; Remaps the VBXE palette so that the Atari's grayscale
; colour entries ($00-$0E) become a blue gradient instead
; of black-to-white.  This turns the B&W title screen into
; a C64-style "cyan-on-navy" look.
;
; Loaded at $0480 (safe from the game's $0600-$0FFF decrypt).
; Runs once via INITAD, then can be overwritten.
; ============================================================

; --- VBXE registers (base $D640) ---
VBXE        = $D640
VCTL        = VBXE+$00   ; VIDEO_CONTROL (read: core version)
CSEL        = VBXE+$04   ; Colour register select
PSEL        = VBXE+$05   ; Palette select
CR          = VBXE+$06   ; Red   (0-127)
CG          = VBXE+$07   ; Green (0-127)
CB          = VBXE+$08   ; Blue  (0-127)

; ============================================================
        org $0480
; ============================================================
vbxe_init:
        ; --- Detect VBXE ---
        ; $D640 returns core version ($1x for FX) on VBXE,
        ; open-bus / $FF on stock hardware.
        lda VCTL
        and #$F0
        cmp #$10
        beq detected
        rts
detected:

        ; Select palette 0 (the default playfield palette).
        lda #$00
        sta PSEL

        ; ------------------------------------------------
        ; Remap grayscale entries ($00,$02,...,$0E).
        ; Original: black → white.
        ; New:      dark navy → light cyan (C64 feel).
        ; ------------------------------------------------

        ; $00 — was black → now dark navy
        lda #$00
        sta CSEL
        lda #5
        sta CR
        lda #5
        sta CG
        lda #32
        sta CB

        ; $02
        lda #$02
        sta CSEL
        lda #8
        sta CR
        lda #10
        sta CG
        lda #42
        sta CB

        ; $04
        lda #$04
        sta CSEL
        lda #12
        sta CR
        lda #16
        sta CG
        lda #52
        sta CB

        ; $06
        lda #$06
        sta CSEL
        lda #18
        sta CR
        lda #24
        sta CG
        lda #62
        sta CB

        ; $08
        lda #$08
        sta CSEL
        lda #26
        sta CR
        lda #34
        sta CG
        lda #72
        sta CB

        ; $0A
        lda #$0A
        sta CSEL
        lda #38
        sta CR
        lda #48
        sta CG
        lda #84
        sta CB

        ; $0C
        lda #$0C
        sta CSEL
        lda #55
        sta CR
        lda #68
        sta CG
        lda #98
        sta CB

        ; $0E — was white → now bright cyan
        lda #$0E
        sta CSEL
        lda #75
        sta CR
        lda #95
        sta CG
        lda #115
        sta CB

        ; ------------------------------------------------
        ; Also remap blue-range entries the game may use
        ; so the in-game colours look more C64-like.
        ; ------------------------------------------------

        ; $90 — dark blue
        lda #$90
        sta CSEL
        lda #10
        sta CR
        lda #8
        sta CG
        lda #45
        sta CB

        ; $92 — blue
        lda #$92
        sta CSEL
        lda #16
        sta CR
        lda #14
        sta CG
        lda #55
        sta CB

        ; $94 — blue (standard Atari bg blue)
        lda #$94
        sta CSEL
        lda #26
        sta CR
        lda #20
        sta CG
        lda #60
        sta CB

        ; $96
        lda #$96
        sta CSEL
        lda #32
        sta CR
        lda #28
        sta CG
        lda #72
        sta CB

        ; $98
        lda #$98
        sta CSEL
        lda #40
        sta CR
        lda #38
        sta CG
        lda #80
        sta CB

        ; $9A
        lda #$9A
        sta CSEL
        lda #50
        sta CR
        lda #50
        sta CG
        lda #92
        sta CB

        ; $9C
        lda #$9C
        sta CSEL
        lda #62
        sta CR
        lda #64
        sta CG
        lda #102
        sta CB

        ; $9E — bright blue
        lda #$9E
        sta CSEL
        lda #78
        sta CR
        lda #80
        sta CG
        lda #115
        sta CB

        ; ------------------------------------------------
        ; Purple/violet range ($5x) for gradient effects
        ; ------------------------------------------------

        ; $56 — purple
        lda #$56
        sta CSEL
        lda #50
        sta CR
        lda #18
        sta CG
        lda #62
        sta CB

        ; $58
        lda #$58
        sta CSEL
        lda #60
        sta CR
        lda #28
        sta CG
        lda #75
        sta CB

        ; ------------------------------------------------
        ; Cyan range ($Ax) for highlights
        ; ------------------------------------------------

        ; $AA — cyan
        lda #$AA
        sta CSEL
        lda #18
        sta CR
        lda #68
        sta CG
        lda #78
        sta CB

        ; $AC
        lda #$AC
        sta CSEL
        lda #30
        sta CR
        lda #82
        sta CG
        lda #85
        sta CB

        ; $AE
        lda #$AE
        sta CSEL
        lda #48
        sta CR
        lda #98
        sta CG
        lda #95
        sta CB

        rts

; ============================================================
; INITAD trigger — loaded at $02E2 to call vbxe_init
; ============================================================
        org $02E2
        .word vbxe_init
