; VBXE Overlay Loader for Starquake
;
; Loads BEFORE the game. INIT decompresses overlay to
; VBXE VRAM, writes XDL, sets palette. Game segments
; then overwrite $8000+ — data is already in VRAM.
;
; The game's VBI is patched by the Python build script
; (build_vbxe.py) to auto-detect title screen ($AA=0)
; and enable/disable VBXE accordingly. No hook segment
; at $0400 needed.

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
NUM_COLORS = 12
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

        ; Write XDL to VRAM $00000
        lda #MEMAC_MCE+0
        sta MEMAC_A
        ldx #xdl_len-1
wxdl    lda xdl_data,x
        sta $4000,x
        dex
        bpl wxdl

        ; Decompress RLE overlay to VRAM $10000
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
nodshi
        lda ZDST+1
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
        lda #0
        sta MEMAC_A

        ; Set palette (palette 1, colors 1-7)
        lda #1
        sta VBXE_CSEL
        sta VBXE_PSEL

        ldx #0
ploop   lda pal_data,x
        sta VBXE_CR
        inx
        lda pal_data,x
        sta VBXE_CG
        inx
        lda pal_data,x
        sta VBXE_CB
        inx
        cpx #NUM_COLORS*3
        bcc ploop

        ; Set XDL address
        lda #0
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2

        ; Don't enable VIDEO_CONTROL — the patched VBI does it
        rts

xdl_data
        ins 'data/xdl.bin'
xdl_len = *-xdl_data

pal_data
        ins 'data/palette.bin'

cur_bank  .byte 0
fill_val  .byte 0

rle_data
        ins 'data/overlay_rle.bin'

        org $02E2
        .word vbxe_load
