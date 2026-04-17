; VBXE Sprite Handler for Starquake
; Runs at $9E00 during VBI, renders 16x16 color sprites
; via VBXE overlay during gameplay.
;
; Assembled with MADS, included by vbxe_loader.asm.
; The loader copies this code block to $9E00 at init time.

; --- Hardware registers ---
HPOSP0   = $D000
COLPM0   = $D012
VBXE_VC  = $D640
VBXE_XA0 = $D641
VBXE_XA1 = $D642
VBXE_XA2 = $D643
MEMAC_A  = $D65D
XITVBV   = $E462

; --- Game zero-page variables ---
PLAYER_X = $9B       ; P/M color-clock X
PLAYER_Y = $9D       ; P/M scan-line Y
ANIM_FRM = $A1       ; Animation frame index
TITLE_FG = $27       ; 0 = title screen, nonzero = gameplay

; --- VRAM addresses ---
; Title XDL at VRAM $00000  (bank 0)
; Gameplay XDL at VRAM $00020  (bank 0)
; Gameplay overlay at VRAM $20000  (bank 8, MEMAC_A=$88)
;   160 bytes per scan line, 192 lines
; Overlay is linear: pixel at (x,y) = VRAM $20000 + y*160 + x

OVL_BANK_BASE = $88  ; MEMAC_A value for VRAM bank 8 ($20000)
OVL_WIDTH     = 160   ; Overlay stride in bytes

; --- Zero-page temporaries (safe during VBI) ---
ZSRC     = $F7       ; Source pointer (sprite frame in RAM)
ZDST     = $FB       ; Dest pointer (VRAM via $4000-$7FFF window)

; --- Playfield horizontal offset ---
; Standard ANTIC playfield starts at color clock ~48.
; 160px mode: each pixel = 2 color clocks.
; overlay_x = (pm_x - 48) / 2
; Adjust -4 to center the wider 16px sprite over the old 8px one.
PF_OFFSET = 48
SPRITE_W  = 16
SPRITE_H  = 16

        org $9E00

; This file is assembled to produce data/handler.bin
; which gets copied to $9E00 by the loader at init time.

; =============================================
; Entry point — called from patched VBI
; =============================================
sprite_handler
        ; Note: OS VBI framework already saved A/X/Y.
        ; XITVBV will restore them. We can freely use regs.

        ; --- Title or gameplay? ---
        lda TITLE_FG
        bne do_gameplay

        ; --- Title screen path ---
        ; XDL address = $000000 (title XDL)
        lda #$00
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC        ; Enable VBXE
        jmp handler_exit

do_gameplay
        ; --- Gameplay path ---
        ; XDL address = $000020 (gameplay XDL)
        lda #$20
        sta VBXE_XA0
        lda #$00
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC        ; Enable VBXE

        ; --- Clear previous sprite from overlay ---
        lda prev_drawn
        beq skip_clear     ; No previous sprite to clear

        ; Compute VRAM dest for old position
        ldx prev_x
        lda prev_y
        jsr calc_ovl_ptr   ; Sets ZDST, selects MEMAC_A bank

        ; Clear 16 rows of 16 bytes
        ldx #SPRITE_H
        lda #$00           ; Transparent
@clr_row
        ldy #SPRITE_W-1
@clr_col
        sta (ZDST),y
        dey
        bpl @clr_col
        ; Advance ZDST by OVL_WIDTH (160)
        jsr advance_row
        dex
        bne @clr_row

skip_clear
        ; --- Compute new sprite screen position ---
        lda PLAYER_X
        sec
        sbc #PF_OFFSET     ; Subtract playfield offset
        bcs @xok
        lda #0             ; Clamp to 0 if negative
@xok    lsr                ; Divide by 2: color clocks → 160px
        ; Center: subtract 4 to offset for wider sprite
        sec
        sbc #4
        bcs @xok2
        lda #0
@xok2   sta cur_x

        lda PLAYER_Y
        sta cur_y

        ; Save as previous for next frame
        lda cur_x
        sta prev_x
        lda cur_y
        sta prev_y
        lda #1
        sta prev_drawn

        ; --- Draw new sprite ---
        ; Set up source: sprite frame data in RAM
        ; Frames stored at sprite_data + frame * 256
        lda ANIM_FRM
        clc
        adc #>sprite_data  ; High byte of base
        sta ZSRC+1
        lda #0
        sta ZSRC           ; Low byte = 0 (256-aligned)

        ; Set up dest: overlay VRAM position
        ldx cur_x
        lda cur_y
        jsr calc_ovl_ptr

        ; Copy 16 rows of 16 bytes
        ldx #SPRITE_H
@draw_row
        ldy #SPRITE_W-1
@draw_col
        lda (ZSRC),y
        beq @skip_px       ; Skip transparent pixels (don't overwrite)
        sta (ZDST),y
@skip_px
        dey
        bpl @draw_col
        ; Advance source by 16
        clc
        lda ZSRC
        adc #SPRITE_W
        sta ZSRC
        bcc @nosrc_hi
        inc ZSRC+1
@nosrc_hi
        ; Advance dest by OVL_WIDTH
        jsr advance_row
        dex
        bne @draw_row

        ; --- Hide P/M player 0 ---
        lda #$00
        sta HPOSP0         ; Move P0 off screen

handler_exit
        jmp XITVBV

; =============================================
; calc_ovl_ptr — Set ZDST and MEMAC_A for
;   overlay pixel at (X=x_pos, A=y_pos)
;
; Overlay VRAM base = $20000
; Pixel addr = $20000 + A*160 + X
; MEMAC_A bank = (addr >> 14) | $80
; CPU addr = (addr & $3FFF) + $4000
;
; Clobbers: A, Y, temp vars
; Input: A=Y position, X=X position
; Output: ZDST set, MEMAC_A set
; =============================================
calc_ovl_ptr
        ; Save X position
        stx @save_x

        ; Compute y * 160 = y * 128 + y * 32
        ; = y * (128 + 32) = y << 7 + y << 5
        sta @y_val
        lda #0
        sta @addr_lo
        sta @addr_mi
        sta @addr_hi

        ; y * 32
        lda @y_val
        asl            ; *2
        asl            ; *4
        asl            ; *8
        asl            ; *16
        asl            ; *32
        sta @t32_lo
        lda #0
        rol            ; Carry from shifts goes to high byte
        sta @t32_hi

        ; Actually, y can be up to ~192, so y*32 can be up to 6144.
        ; Need 16-bit result. Let me redo with proper carry tracking.

        ; y * 32 (16-bit)
        lda @y_val
        sta @t32_lo
        lda #0
        sta @t32_hi
        ; Shift left 5 times
        .rept 5
        asl @t32_lo
        rol @t32_hi
        .endr

        ; y * 128 (16-bit)
        lda @y_val
        sta @t128_lo
        lda #0
        sta @t128_hi
        .rept 7
        asl @t128_lo
        rol @t128_hi
        .endr

        ; y*160 = y*128 + y*32
        clc
        lda @t128_lo
        adc @t32_lo
        sta @addr_lo
        lda @t128_hi
        adc @t32_hi
        sta @addr_mi

        ; Add X position
        clc
        lda @addr_lo
        adc @save_x
        sta @addr_lo
        lda @addr_mi
        adc #0
        sta @addr_mi

        ; Add overlay base $20000
        ; $20000 = bit 17 set in a 3-byte address
        ; @addr_hi += 2 (since $20000 >> 16 = 2)
        lda #2
        sta @addr_hi

        ; Carry from addr_mi to addr_hi
        ; (addr_mi is at most ~192*160/256 + 255/256 ≈ 120, so no carry needed)

        ; Now compute MEMAC_A bank:
        ; VRAM bank = addr >> 14
        ; MEMAC_A = bank | $80
        ; For $20000-$27FFF: bank 8 ($88)
        ; For $28000-$2BFFF: bank 10 ($8A)
        ; Since max addr = $20000 + 191*160 + 159 = $20000 + 30719 = $27FFF
        ; All within bank 8! (0x20000-0x23FFF) and bank 9 (0x24000-0x27FFF)

        ; bank = (addr_hi << 2) | (addr_mi >> 6)
        lda @addr_hi
        asl
        asl
        sta @bank
        lda @addr_mi
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        ora @bank
        ora #$80        ; MEMAC_MCE bit
        sta MEMAC_A

        ; CPU address = $4000 + (addr & $3FFF)
        lda @addr_mi
        and #$3F
        ora #$40        ; Add $4000 base
        sta ZDST+1
        lda @addr_lo
        sta ZDST

        rts

; =============================================
; advance_row — Add OVL_WIDTH (160) to ZDST,
;   handle bank crossing
; =============================================
advance_row
        clc
        lda ZDST
        adc #<OVL_WIDTH  ; +160
        sta ZDST
        lda ZDST+1
        adc #>OVL_WIDTH  ; +0 (160 < 256)
        sta ZDST+1
        ; Check if we crossed the $8000 boundary
        bpl @no_cross    ; If bit 7 clear, still in $4000-$7FFF
        ; Crossed: wrap to $4000 and advance bank
        lda ZDST+1
        and #$3F
        ora #$40
        sta ZDST+1
        ; Increment MEMAC_A bank
        lda MEMAC_A
        clc
        adc #1
        sta MEMAC_A
@no_cross
        rts

; =============================================
; Local variables
; =============================================
prev_x      .byte 0
prev_y      .byte 0
prev_drawn  .byte 0    ; 0 = no prev sprite to clear
cur_x       .byte 0
cur_y       .byte 0
@save_x     .byte 0
@y_val      .byte 0
@t32_lo     .byte 0
@t32_hi     .byte 0
@t128_lo    .byte 0
@t128_hi    .byte 0
@addr_lo    .byte 0
@addr_mi    .byte 0
@addr_hi    .byte 0
@bank       .byte 0

handler_end = *

; =============================================
; Sprite frame data — loaded here by init
; Must be 256-byte aligned for easy frame indexing
; 11 frames × 256 bytes = 2816 bytes
; =============================================
; Sprite data is at $A000 in RAM (loaded by init)
sprite_data = $A000
