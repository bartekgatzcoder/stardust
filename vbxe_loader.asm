; VBXE Overlay + Sprite Loader for Starquake
;
; Loads BEFORE the game. INIT does:
; 1. Detect VBXE
; 2. Write title XDL to VRAM $00000
; 3. Write gameplay XDL to VRAM $00020
; 4. Decompress title overlay to VRAM $10000
; 5. Clear gameplay overlay buffer at VRAM $20000 (160×192)
; 6. Copy sprite frame data to VRAM $30000
; 7. Set palette (title colors + sprite colors)
; 8. Copy sprite handler code to $9E00 in RAM
; 9. Copy sprite frame data to RAM at sprite_data address
;
; The game's VBI is patched by build_vbxe.py to JMP $9E00.

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
OVL_BANK0 = 4            ; Title overlay bank
GAME_OVL_BANK = 8        ; Gameplay overlay bank
SPRITE_BANK = 12          ; Sprite data bank
NUM_TITLE_COLORS = 9
NUM_SPRITE_COLORS = 5
VBXE_ID   = $10

HANDLER_DEST = $9E00      ; Runtime address for sprite handler
SPRITE_DEST  = $A000      ; Runtime address for sprite frame data

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
        ; === 4. Clear gameplay overlay buffer at VRAM $20000 ===
        ; 160 * 192 = 30720 bytes, across banks 8-9
        ; Bank 8: $20000-$23FFF (16384 bytes)
        ; Bank 9: $24000-$27FFF (14336 bytes used)
        lda #MEMAC_MCE+GAME_OVL_BANK
        sta MEMAC_A
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1
        ; Clear 30720 bytes = 120 pages of 256 bytes
        ldx #0          ; Page counter
        lda #0
@clr_pg ldy #0
@clr_lp sta (ZDST),y
        iny
        bne @clr_lp
        inc ZDST+1
        ; Check bank boundary
        lda ZDST+1
        cmp #$80
        bcc @no_clr_bnk
        lda #$40
        sta ZDST+1
        lda MEMAC_A
        clc
        adc #1
        sta MEMAC_A
@no_clr_bnk
        lda #0
        inx
        cpx #120        ; 120 pages = 30720 bytes
        bcc @clr_pg

        ; === 5. Set palette ===
        ; Palette 1: title colors (1-9) then sprite colors (1-5)
        ; Sprite colors use the same palette indices 1-5
        ; (title uses colors 1-8, sprites use 1-5 which overlap)
        ; We'll set sprite colors as palette 1, indices 1-5
        ; Then title colors as palette 1, indices 1-9
        ; (title colors will overwrite sprite colors 1-5 for title screen)
        ;
        ; Actually, both title and gameplay use the same palette.
        ; For gameplay, we need sprite colors at indices 1-3 (brown, yellow-green, white).
        ; For title, we need the title colors at indices 1-8.
        ; These conflict!
        ;
        ; Solution: use different palette banks.
        ; Title uses palette 1. Gameplay uses palette 0.
        ; Or: swap palette in the VBI when switching modes.
        ;
        ; Simpler: The gameplay XDL can specify which palette to use.
        ; For now, set sprite colors first, then title colors overwrite.
        ; The VBI handler will re-set sprite palette during gameplay.
        ;
        ; ACTUALLY: simplest approach - set sprite colors at higher indices.
        ; Use palette 1 for both, but sprite colors at indices 1-3 and
        ; title colors at indices 1-8. Since title overlay uses different
        ; pixel values, there's no conflict IF we design the palette carefully.
        ;
        ; Best approach: during gameplay, the VBI handler swaps the palette.
        ; During title, the existing palette is fine.
        ;
        ; For now: set title palette (indices 1-8) AND sprite palette (indices 1-3).
        ; During title, the overlay data uses title pixel values.
        ; During gameplay, the overlay data uses sprite pixel values.
        ; Since the data is different, the palette just needs all entries set.

        ; Set palette 1, start at color 1
        lda #1
        sta VBXE_CSEL     ; Start at color index 1
        sta VBXE_PSEL     ; Palette 1

        ; First write sprite colors (indices 1-5)
        ldx #0
@spal   lda sprite_pal_data,x
        sta VBXE_CR
        inx
        lda sprite_pal_data,x
        sta VBXE_CG
        inx
        lda sprite_pal_data,x
        sta VBXE_CB
        inx
        cpx #NUM_SPRITE_COLORS*3
        bcc @spal

        ; Now overwrite with title colors (also start at index 1)
        lda #1
        sta VBXE_CSEL
        ldx #0
@tpal   lda title_pal_data,x
        sta VBXE_CR
        inx
        lda title_pal_data,x
        sta VBXE_CG
        inx
        lda title_pal_data,x
        sta VBXE_CB
        inx
        cpx #NUM_TITLE_COLORS*3
        bcc @tpal

        ; === 6. Set XDL address (title by default) ===
        lda #0
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2

        ; === 7. Copy sprite handler to $9E00 ===
        ; Handler is handler_code_len bytes
        lda #<handler_src
        sta ZSRC
        lda #>handler_src
        sta ZSRC+1
        lda #<HANDLER_DEST
        sta ZDST
        lda #>HANDLER_DEST
        sta ZDST+1
        ; Copy full pages first
        ldx #handler_code_len/256
        beq @cpyh_rem
@cpyh_page
        ldy #0
@cpyh_lp
        lda (ZSRC),y
        sta (ZDST),y
        iny
        bne @cpyh_lp
        inc ZSRC+1
        inc ZDST+1
        dex
        bne @cpyh_page
@cpyh_rem
        ; Copy remaining bytes
        ldy #0
@cpyh_rlp
        cpy #handler_code_len-((handler_code_len/256)*256)
        beq @cpyh_done
        lda (ZSRC),y
        sta (ZDST),y
        iny
        bne @cpyh_rlp
@cpyh_done

        ; === 8. Copy sprite frame data to $A000 ===
        ; 2816 bytes = 11 pages of 256 bytes
        lda #<sprite_frame_src
        sta ZSRC
        lda #>sprite_frame_src
        sta ZSRC+1
        lda #<SPRITE_DEST
        sta ZDST
        lda #>SPRITE_DEST
        sta ZDST+1
        ldx #11         ; 11 pages (2816 bytes)
@cpys   ldy #0
@cpysl  lda (ZSRC),y
        sta (ZDST),y
        iny
        bne @cpysl
        inc ZSRC+1
        inc ZDST+1
        dex
        bne @cpys

        ; === 9. Set sprite palette during gameplay ===
        ; The handler will do this in VBI. For now, done.

        lda #0
        sta MEMAC_A     ; Reset bank select
        rts

; =============================================
; Data includes
; =============================================

xdl_title_data
        ins 'data/xdl.bin'
xdl_title_len = *-xdl_title_data

xdl_game_data
        ins 'data/gameplay_xdl.bin'
xdl_game_len = *-xdl_game_data

title_pal_data
        ins 'data/palette.bin'

sprite_pal_data
        ins 'data/sprite_palette.bin'

cur_bank  .byte 0
fill_val  .byte 0

; Handler code — will be copied to $9E00 at runtime
handler_src
        ins 'data/handler.bin'
handler_code_len = *-handler_src

; Sprite frame data — will be copied to $A000 at runtime
sprite_frame_src
        ins 'data/sprite_frames.bin'

; RLE title overlay data (must be last — largest)
rle_data
        ins 'data/overlay_rle.bin'

        org $02E2
        .word vbxe_load
