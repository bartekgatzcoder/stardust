; VBXE Overlay + Sprite Loader for Starquake
;
; INIT segment at $8000. Runs before game loads. Does:
; 1. Detect VBXE
; 2. Write title XDL to VRAM $00000
; 3. Write gameplay XDL to VRAM $00020
; 4. Decompress title overlay to VRAM $10000
; 5. Clear gameplay overlay buffer at VRAM $20000
; 6. Copy sprite frame data to VRAM $30000
; 7. Set palette
;
; Handler code is loaded to $9E00 by the copy-down extension,
; NOT by this INIT. Sprite data read via MEMAC_B during VBI.

VBXE      = $D640
VBXE_VC   = VBXE+$00
VBXE_XA0  = VBXE+$01
VBXE_XA1  = VBXE+$02
VBXE_XA2  = VBXE+$03
VBXE_CSEL = VBXE+$04
VBXE_PSEL = VBXE+$05
VBXE_CR   = VBXE+$06
VBXE_CG   = VBXE+$07
VBXE_CB   = VBXE+$08
MEMAC_A   = VBXE+$1D

ZSRC      = $FB
ZDST      = $FD

MEMAC_MCE = $80
OVL_BANK0 = 4
GAME_OVL_BANK = 8
SPRITE_VRAM_BANK = 12    ; Sprite data at VRAM $30000
NUM_TITLE_COLORS = 9
NUM_SPRITE_COLORS = 5
VBXE_ID   = $10

        org $8000

vbxe_load
        lda VBXE_VC
        cmp #VBXE_ID
        beq detected
        rts

detected
        lda #0
        sta VBXE_VC

        ; === 1. Write title XDL to VRAM $00000 ===
        lda #MEMAC_MCE+0
        sta MEMAC_A
        ldx #xdl_title_len-1
@wxdl   lda xdl_title_data,x
        sta $4000,x
        dex
        bpl @wxdl

        ; === 2. Write gameplay XDL to VRAM $00020 ===
        ldx #xdl_game_len-1
@wgxdl  lda xdl_game_data,x
        sta $4020,x
        dex
        bpl @wgxdl

        ; === 3. Decompress RLE title overlay to VRAM $10000 ===
        lda #MEMAC_MCE+OVL_BANK0
        sta MEMAC_A
        sta cur_bank
        lda #<rle_data
        sta ZSRC
        lda #>rle_data
        sta ZSRC+1
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1

dloop   ldy #0
        lda (ZSRC),y
        beq ddone
        tax
        iny
        lda (ZSRC),y
        sta fill_val
        clc
        lda ZSRC
        adc #2
        sta ZSRC
        bcc nosrhi
        inc ZSRC+1
nosrhi
wloop   lda fill_val
        ldy #0
        sta (ZDST),y
        inc ZDST
        bne nodshi
        inc ZDST+1
nodshi  lda ZDST+1
        cmp #$80
        bcc nobnk
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1
        inc cur_bank
        lda cur_bank
        sta MEMAC_A
nobnk   dex
        bne wloop
        beq dloop
ddone

        ; === 4. Clear gameplay overlay at VRAM $20000 ===
        lda #MEMAC_MCE+GAME_OVL_BANK
        sta MEMAC_A
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1
        ldx #0
@clr_pg ldy #0
        lda #0
@clr_lp sta (ZDST),y
        iny
        bne @clr_lp
        inc ZDST+1
        lda ZDST+1
        cmp #$80
        bcc @no_cb
        lda #$40
        sta ZDST+1
        lda MEMAC_A
        clc
        adc #1
        sta MEMAC_A
@no_cb  lda #0
        inx
        cpx #120           ; 120 pages = 30720 bytes
        bcc @clr_pg

        ; === 5. Copy sprite frames to VRAM $30000 ===
        lda #MEMAC_MCE+SPRITE_VRAM_BANK
        sta MEMAC_A
        lda #<sprite_data
        sta ZSRC
        lda #>sprite_data
        sta ZSRC+1
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1
        ; 2816 bytes = 11 pages
        ldx #11
@spy_pg ldy #0
@spy_lp lda (ZSRC),y
        sta (ZDST),y
        iny
        bne @spy_lp
        inc ZSRC+1
        inc ZDST+1
        dex
        bne @spy_pg

        ; === 6. Set palette ===
        ; Sprite colors first (indices 1-5)
        lda #1
        sta VBXE_CSEL
        sta VBXE_PSEL
        ldx #0
@spal   lda sprite_pal,x
        sta VBXE_CR
        inx
        lda sprite_pal,x
        sta VBXE_CG
        inx
        lda sprite_pal,x
        sta VBXE_CB
        inx
        cpx #NUM_SPRITE_COLORS*3
        bcc @spal

        ; Title colors (indices 1-9, overwrites 1-5 for title)
        lda #1
        sta VBXE_CSEL
        ldx #0
@tpal   lda title_pal,x
        sta VBXE_CR
        inx
        lda title_pal,x
        sta VBXE_CG
        inx
        lda title_pal,x
        sta VBXE_CB
        inx
        cpx #NUM_TITLE_COLORS*3
        bcc @tpal

        ; === 7. Set default XDL (title) ===
        lda #0
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2

        lda #0
        sta MEMAC_A
        rts

; === Data ===
xdl_title_data
        ins 'data/xdl.bin'
xdl_title_len = *-xdl_title_data

xdl_game_data
        ins 'data/gameplay_xdl.bin'
xdl_game_len = *-xdl_game_data

title_pal
        ins 'data/palette.bin'

sprite_pal
        ins 'data/sprite_palette.bin'

cur_bank  .byte 0
fill_val  .byte 0

sprite_data
        ins 'data/sprite_frames.bin'

rle_data
        ins 'data/overlay_rle.bin'

        org $02E2
        .word vbxe_load
