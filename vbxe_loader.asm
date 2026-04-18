; VBXE Overlay + Sprite Loader for Starquake
;
; SEGMENT LAYOUT
;
;   $2300-$5DDC  RLE-compressed title overlay (14909 bytes).
;                Loaded first. The game's own seg 1 later overwrites
;                this region at $2300-$62FF, but only AFTER this
;                loader's INIT has already decompressed the data to
;                VBXE VRAM, so the clash is harmless.
;   $8000-$????  Loader code + small data (XDL, palettes).
;                Capped well below $BB80 so the copy-down does not
;                corrupt game sprite data at RAM $9E00-$9E7F (which
;                comes from XEX $BB80-$BBFF).
;   $02E2-$02E3  INITAD → $8000, fires after the two segments above
;                are in RAM.
;
; INIT steps performed at $8000:
;   1. Detect VBXE
;   2. Write title XDL to VRAM $00000
;   3. Write gameplay XDL to VRAM $00020
;   4. Decompress title overlay from RAM $2300 to VRAM $10000
;   5. Clear gameplay overlay buffer at VRAM $20000
;   6. Set palette
;   7. Point XDL at title, enable VBXE permanently
;   8. Clear INITAD so subsequent segments don't re-trigger us
;
; Sprite frame data is written to VRAM $30000 later by the copy-down
; install code (not here — it would overflow this segment).

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

INITAD    = $02E2

ZSRC      = $FB
ZDST      = $FD

MEMAC_MCE = $80
OVL_BANK0 = 4
GAME_OVL_BANK = 8
SPRITE_VRAM_BANK = 12
NUM_TITLE_COLORS = 9
NUM_SPRITE_COLORS = 5
VBXE_ID   = $10

; === Segment 1: RLE data ===
; Placed FIRST in source so MADS emits it as the first XEX segment,
; which means the OS has this data in RAM before INITAD fires.

        org $2300
rle_data
        ins 'data/overlay_rle.bin'
rle_end

; === Segment 2: loader code ===

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
        ; 30720 bytes = 120 pages, spanning MEMAC bank 8 ($20000-$23FFF,
        ; 64 pages) then bank 9 ($24000-$277FF, 56 pages).
        ; MEMAC_A is effectively write-only from the CPU side on VBXE —
        ; reading it back does not return the value we wrote — so we
        ; track the current bank in cur_bank (shared with the RLE
        ; decompressor above, which already uses the same pattern).
        lda #MEMAC_MCE+GAME_OVL_BANK
        sta MEMAC_A
        sta cur_bank
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
        ; Window full: wrap dest to $4000 and advance the tracked bank.
        lda #$40
        sta ZDST+1
        inc cur_bank
        lda cur_bank
        sta MEMAC_A
@no_cb  inx
        cpx #120
        bcc @clr_pg

        ; === 5. Set palette ===
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

        ; === 6. Set default XDL (title), clear MEMAC ===
        lda #0
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        sta MEMAC_A

        ; === 7. Enable VBXE permanently (title XDL active) ===
        ; The VBI handler only switches XDL address after this point;
        ; VBXE_VC is never written again.
        lda #$01
        sta VBXE_VC

        ; === 8. Clear INITAD so later XEX segments don't re-run us ===
        ; Some loaders leave $02E2-$02E3 unchanged between segments.
        ; Rebuilding VBXE state after game segments have loaded (which
        ; overwrite the RLE buffer at $2300) would corrupt the overlay.
        lda #0
        sta INITAD
        sta INITAD+1

        rts

; === Code-segment data (XDL descriptors, palettes, scratch) ===
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

; === Segment 3: INITAD ===

        org INITAD
        .word vbxe_load
