; VBXE Sprite Handler for Starquake
; Runs at $9E00 during VBI
;
; Sprite frame data lives in VBXE VRAM at $30000.
; We read it via MEMAC_B ($8000-$BFFF window) during VBI.
; Overlay buffer in VRAM at $20000, written via MEMAC_A ($4000-$7FFF).

HPOSP0   = $D000
COLPM0   = $D012
VBXE_VC  = $D640
VBXE_XA0 = $D641
VBXE_XA1 = $D642
VBXE_XA2 = $D643
MEMAC_A  = $D65D       ; Maps VRAM bank to $4000-$7FFF
MEMAC_B_CTRL = $D65E   ; MEMAC_B control
MEMAC_B_BANK = $D65F   ; MEMAC_B bank select
XITVBV   = $E462

PLAYER_X = $9B
PLAYER_Y = $9D
ANIM_FRM = $A1
TITLE_FG = $27

ZDST     = $FB         ; Dest pointer for VRAM overlay write
ZSRC     = $F7         ; Source pointer for sprite read from MEMAC_B

PF_OFFSET = 48
SPRITE_W  = 16
SPRITE_H  = 16
OVL_WIDTH = 160

; MEMAC_B: bit 3 = enable, bits 0-2 = CPU window at $8000
; Bank = value written to MEMAC_B_BANK
; To read VRAM $30000: bank = $30000 >> 14 = $0C
; MEMAC_B_CTRL = $88 (enable + window $8000)? Check docs.
; Actually MEMAC_B_CTRL: bit 7 = enable. Lower bits = base addr control.
; MEMAC_B_BANK: selects which 16KB bank appears at the window.
;
; For FX core: MEMAC_B = $D65E (1 byte), value:
;   bit 7: 1 = enable MEMAC_B window
;   bits 0-6: bank number (bank * $4000 = VRAM start)
; CPU window at $8000-$BFFF when enabled.
;
; To access VRAM $30000 (bank 12): MEMAC_B = $80 | 12 = $8C

MEMAC_B  = $D65E       ; Single register for B window
SPR_VRAM_BANK = $8C    ; Bank 12 = VRAM $30000

        org $9E00

sprite_handler
        lda TITLE_FG
        bne do_gameplay

        ; Title screen: XDL at $00000
        lda #$00
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC
        jmp XITVBV

do_gameplay
        ; Gameplay: XDL at $00020
        lda #$20
        sta VBXE_XA0
        lda #$00
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC

        ; === Clear old sprite ===
        lda prev_drawn
        beq skip_clear

        ldx prev_x
        lda prev_y
        jsr calc_ovl_ptr   ; ZDST + MEMAC_A set

        ldx #SPRITE_H
        lda #$00
@clr_row
        ldy #SPRITE_W-1
@clr_col
        sta (ZDST),y
        dey
        bpl @clr_col
        jsr advance_row
        dex
        bne @clr_row

skip_clear
        ; === Compute screen position ===
        lda PLAYER_X
        sec
        sbc #PF_OFFSET
        bcs @xok
        lda #0
@xok    lsr               ; /2: color clocks → 160px
        sec
        sbc #4            ; Center wider sprite
        bcs @xok2
        lda #0
@xok2   sta cur_x
        sta prev_x

        lda PLAYER_Y
        sta cur_y
        sta prev_y
        lda #1
        sta prev_drawn

        ; === Draw new sprite ===
        ; Enable MEMAC_B to read sprite frames from VRAM $30000
        ; Sprite data at VRAM $30000 + frame * 256
        ; Bank 12 base = $30000, frame offset in low bits
        lda ANIM_FRM
        clc
        adc #$0C           ; Bank 12 + (frame>>2 for 16KB pages)
        ; Actually: VRAM $30000 + frame*256.
        ; Bank 12 covers $30000-$33FFF. Frame 0 at $30000, frame 15 at $30F00.
        ; All 11 frames fit in bank 12 (11*256=2816 < 16384). 
        lda #SPR_VRAM_BANK ; $8C = bank 12
        sta MEMAC_B        ; Enable MEMAC_B window at $8000

        ; Sprite source in MEMAC_B window:
        ; $8000 + frame * 256
        ; frame_addr_lo = 0, frame_addr_hi = $80 + frame
        lda ANIM_FRM
        clc
        adc #$80           ; $80 = base of MEMAC_B window
        sta ZSRC+1
        lda #$00
        sta ZSRC

        ; Set up overlay destination
        ldx cur_x
        lda cur_y
        jsr calc_ovl_ptr   ; ZDST + MEMAC_A set

        ; Copy 16 rows of 16 bytes
        ldx #SPRITE_H
@draw_row
        ldy #SPRITE_W-1
@draw_col
        lda (ZSRC),y       ; Read from VRAM via MEMAC_B
        beq @skip_px       ; Skip transparent
        sta (ZDST),y       ; Write to overlay via MEMAC_A
@skip_px
        dey
        bpl @draw_col

        ; Advance source by 16
        clc
        lda ZSRC
        adc #SPRITE_W
        sta ZSRC
        bcc @nosrc
        inc ZSRC+1
@nosrc
        ; Advance dest row
        jsr advance_row
        dex
        bne @draw_row

        ; Disable MEMAC_B (restore normal RAM at $8000)
        lda #$00
        sta MEMAC_B

        ; Hide P/M player 0
        lda #$00
        sta HPOSP0

        jmp XITVBV

; =============================================
; calc_ovl_ptr: overlay address for pixel (X, A=Y)
; Sets ZDST and MEMAC_A
; =============================================
calc_ovl_ptr
        stx save_x
        sta save_y

        ; addr = y * 160 + x + $20000
        ; y * 160 = y * 128 + y * 32

        ; y * 32 (16-bit)
        lda save_y
        sta tmp_lo
        lda #0
        sta tmp_hi
        .rept 5
        asl tmp_lo
        rol tmp_hi
        .endr

        ; y * 128 (16-bit)
        lda save_y
        sta tmp2_lo
        lda #0
        sta tmp2_hi
        .rept 7
        asl tmp2_lo
        rol tmp2_hi
        .endr

        ; y*160 = y*128 + y*32
        clc
        lda tmp2_lo
        adc tmp_lo
        sta addr_lo
        lda tmp2_hi
        adc tmp_hi
        sta addr_mi

        ; + x
        clc
        lda addr_lo
        adc save_x
        sta addr_lo
        lda addr_mi
        adc #0
        sta addr_mi

        ; VRAM base = $20000 (addr_hi = 2)
        ; MEMAC_A bank = ((2 << 14) | addr) >> 14
        ;             = 8 + (addr_mi >> 6)
        lda addr_mi
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc #8             ; Bank 8 base
        ora #$80           ; MEMAC_MCE enable bit
        sta MEMAC_A

        ; CPU addr = $4000 + (addr & $3FFF)
        lda addr_mi
        and #$3F
        ora #$40
        sta ZDST+1
        lda addr_lo
        sta ZDST
        rts

; =============================================
; advance_row: ZDST += 160, bank check
; =============================================
advance_row
        clc
        lda ZDST
        adc #<OVL_WIDTH
        sta ZDST
        lda ZDST+1
        adc #>OVL_WIDTH
        sta ZDST+1
        bpl @ok            ; Still in $4000-$7FFF?
        ; Crossed bank boundary
        lda ZDST+1
        and #$3F
        ora #$40
        sta ZDST+1
        lda MEMAC_A
        clc
        adc #1
        sta MEMAC_A
@ok     rts

; =============================================
; Variables
; =============================================
prev_x      .byte 0
prev_y      .byte 0
prev_drawn  .byte 0
cur_x       .byte 0
cur_y       .byte 0
save_x      .byte 0
save_y      .byte 0
tmp_lo      .byte 0
tmp_hi      .byte 0
tmp2_lo     .byte 0
tmp2_hi     .byte 0
addr_lo     .byte 0
addr_mi     .byte 0

handler_end = *
