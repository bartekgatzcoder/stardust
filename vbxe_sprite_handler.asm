; VBXE Sprite Handler for Starquake — v3
; Installed at $9E00 by copy-down extension.
;
; Title:    XDL=$00000, VBXE on.
; Gameplay: draw 16x16 colour sprite from VRAM $30000 to overlay
;           VRAM $20000 at the BLOB's P/M position, VBXE on with
;           gameplay XDL at $00020.
;
; Overlay canvas: 160 bytes/row, LR mode (1 byte = 2 colour clocks).
; Sprite VRAM:    $30000, 16 rows × 16 bytes = 256 bytes.
; VRAM access:    MEMAC_A only ($4000-$7FFF window).

VBXE_VC  = $D640
VBXE_XA0 = $D641
VBXE_XA1 = $D642
VBXE_XA2 = $D643
MEMAC_A  = $D65D
XITVBV   = $E462

TITLE_FG  = $27   ; 0=title, nonzero=gameplay
BLOB_X    = $9B   ; P/M HPOS of BLOB (colour clocks)
BLOB_Y    = $9D   ; scan line of BLOB top

; ZP temporaries (reused from install code, always zeroed before $05B9)
ZSL       = $FB   ; source pointer lo
ZSH       = $FC   ; source pointer hi
ZDL       = $FD   ; dest pointer lo
ZDH       = $FE   ; dest pointer hi

; Row buffer in handler data area (after the 4 single-byte variables).
; Must be handler_data+4 to avoid clobbering ov_x_save/dest_lo/dest_hi/ov_bank
; during the 16-byte sprite-row read.
ROW_BUF   = handler_data+4 ; 16 bytes

        org $9E00

sprite_handler
        lda TITLE_FG
        bne do_gameplay

        ; --- Title: XDL at VRAM $00000, VBXE on ---
        lda #$00
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC
        jmp XITVBV

        ; --- Gameplay: draw sprite, enable VBXE with gameplay XDL ---
do_gameplay

        ; Compute overlay X from BLOB_X ($9B).
        ; P/M HPOS 48 = left edge of display. Overlay pixel = 2 colour
        ; clocks. overlay_x = ($9B - 48) / 2, clamped 0-143.
        lda BLOB_X
        sec
        sbc #48
        bcc @cx_clamp
        lsr             ; divide by 2
        cmp #143
        bcc @cx_ok
        lda #143
        bne @cx_ok
@cx_clamp
        lda #0
@cx_ok  sta ZSL         ; store overlay_x in ZSL temporarily

        ; Compute overlay Y from BLOB_Y ($9D).
        ; Scan line 8 = row 0. Clamped 0-175 (leaves room for 16-row sprite).
        lda BLOB_Y
        sec
        sbc #8
        bcc @cy_clamp
        cmp #175
        bcc @cy_ok
        lda #175
        bne @cy_ok
@cy_clamp
        lda #0
@cy_ok  sta ZSH         ; overlay_y in ZSH temporarily

        ; --- Draw 16x16 sprite from VRAM $30000 to overlay $20000 ---
        ;
        ; Sprite source: VRAM $30000 = MEMAC_A bank 12 ($8C).
        ;   Row r source addr in window = $4000 + r*16.
        ;
        ; Overlay dest: VRAM $20000 = MEMAC_A bank 8 ($88), or bank 9
        ;   ($89) for rows >= 102. Row r dest offset = r*160 + x.
        ;   Boundary: bank 8 covers rows 0-101 (16384/160=102 rows).
        ;
        ; We draw 16 rows. For simplicity handle all rows within one
        ; bank check per row (adds 3 bytes/row but keeps code small).

        ; Set up sprite source pointer: $4000+0 = $4000
        lda #$00
        sta ZSL
        lda #$40
        sta ZSH

        ; Compute first overlay dest addr: y*160+x
        ; y*160 = y*128 + y*32. Both computed with 16-bit result.
        ; Save overlay_x (was in $FB) now clobbered, re-read BLOB_X.
        ; Recompute overlay_x into ov_x_save below.

        ; overlay_x is still in $FB (ZSL) from above — save it first.
        lda ZSL         ; = overlay_x
        sta ov_x_save

        ; y (ZSH) * 160 → dest_hi:dest_lo
        lda ZSH         ; = overlay_y
        ; *128: hi = y>>1, lo = (y&1)<<7
        lsr
        sta dest_hi     ; y>>1 = y*128 high byte
        lda #$00
        ror             ; carry (= y bit 0) → bit 7 of A = y*128 lo
        sta dest_lo
        ; *32: hi = y>>3, lo = (y<<5)&$FF
        lda ZSH
        asl
        asl
        asl
        asl
        asl             ; y<<5, carry = y bit 3
        ; add y*32 lo to dest_lo
        clc
        adc dest_lo
        sta dest_lo
        lda dest_hi
        adc #$00        ; propagate carry
        sta dest_hi
        ; add y*32 hi = (y>>3) to dest_hi
        lda ZSH
        lsr
        lsr
        lsr             ; y>>3
        clc
        adc dest_hi
        sta dest_hi
        ; add overlay_x to dest_lo
        lda ov_x_save
        clc
        adc dest_lo
        sta dest_lo
        bcc @no_xc
        inc dest_hi
@no_xc

        ; dest_hi:dest_lo = absolute offset within VRAM $20000.
        ; Convert to MEMAC_A bank+address:
        ;   if offset < $4000 → bank 8, addr = $4000+offset
        ;   if offset >= $4000 → bank 9, addr = $4000+(offset-$4000)
        ; dest_hi >= $40 → bank 9, else bank 8.
        lda dest_hi
        cmp #$40
        bcc @bank8
        lda #$89        ; bank 9
        bne @bnkset
@bank8  lda #$88        ; bank 8
@bnkset sta ov_bank

        ; Add $4000 to dest offset to get MEMAC window address.
        ; If bank 9: subtract $4000 (i.e., mask off top bit of hi byte).
        lda ov_bank
        cmp #$89
        bne @bk8adj
        lda dest_hi
        sec
        sbc #$40
        sta dest_hi
@bk8adj
        ; addr_hi = dest_hi + $40 (for bank 8/9, window base $4000)
        lda dest_hi
        clc
        adc #$40
        sta ZDH
        lda dest_lo
        sta ZDL

        ; Draw loop: 16 rows
        ldx #16
@row_loop
        ; Set MEMAC_A → sprite bank 12
        lda #$8C
        sta MEMAC_A

        ; Read 16 bytes from sprite → row buffer
        ldy #$0F
@rd     lda (ZSL),y     ; ZSL:ZSH = sprite source (starts $4000)
        sta ROW_BUF,y
        dey
        bpl @rd

        ; Advance sprite source by 16 bytes
        lda ZSL
        clc
        adc #$10
        sta ZSL
        bcc @no_sh
        inc ZSH
@no_sh

        ; Set MEMAC_A → overlay bank
        lda ov_bank
        sta MEMAC_A

        ; Write 16 bytes from row buffer → overlay (skip transparent=0)
        ldy #$0F
@wr     lda ROW_BUF,y
        beq @skip
        sta (ZDL),y     ; ZDL:ZDH = overlay dest
@skip   dey
        bpl @wr

        ; Advance overlay dest by 160 bytes (next row)
        lda ZDL
        clc
        adc #$A0        ; 160 = $A0
        sta ZDL
        lda ZDH
        adc #$00
        sta ZDH

        ; Check bank boundary: if ZDH >= $80, wrap to bank 9
        ; (i.e. overflow past $7FFF → start of next bank)
        lda ZDH
        cmp #$80
        bcc @no_bank_cross
        ; crossed into bank 9
        lda #$89
        sta ov_bank
        lda ZDH
        sec
        sbc #$40        ; adjust back by 16KB
        sta ZDH
@no_bank_cross

        dex
        bne @row_loop

        ; Clear MEMAC_A
        lda #$00
        sta MEMAC_A

        ; Enable VBXE with gameplay XDL at VRAM $00020
        lda #$20
        sta VBXE_XA0
        lda #$00
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC

        jmp XITVBV

        ; --- Handler data area ---
handler_data
ov_x_save .byte 0
dest_lo   .byte 0
dest_hi   .byte 0
ov_bank   .byte $88     ; default bank 8
        .ds 16          ; ROW_BUF (16 bytes)

handler_end = *
