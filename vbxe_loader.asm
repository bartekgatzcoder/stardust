; VBXE Overlay Title Screen for Starquake
; Clean implementation: pre-rendered 8bpp overlay
; from C64 title screen data.
;
; XEX structure:
;   [this segment: $8000, INIT=vbxe_load]
;   [game XEX: untouched]
;   [hook segment: $0400, INIT=hook_init]

; ---- VBXE registers (base $D640, FX 1.xx) ----
VBXE      = $D640
VBXE_VC   = VBXE+$00  ; VIDEO_CONTROL (write) / CORE_VERSION (read)
VBXE_XA0  = VBXE+$01  ; XDL_ADR0
VBXE_XA1  = VBXE+$02  ; XDL_ADR1
VBXE_XA2  = VBXE+$03  ; XDL_ADR2
VBXE_CSEL = VBXE+$04
VBXE_PSEL = VBXE+$05
VBXE_CR   = VBXE+$06
VBXE_CG   = VBXE+$07
VBXE_CB   = VBXE+$08
MEMAC_A   = VBXE+$1D  ; MEMAC-A bank select + MCE

; ---- Zero page temporaries ----
ZSRC      = $FB        ; 2 bytes: RLE source pointer
ZDST      = $FD        ; 2 bytes: VRAM dest pointer

; ---- Constants ----
MEMAC_MCE = $80        ; MEMAC CPU enable bit
OVL_BANK0 = 4          ; first VRAM bank for overlay ($10000/16K=4)
NUM_COLORS = 7
VBXE_ID   = $10        ; FX 1.xx core version

; ===================================================
; SEGMENT 1: Overlay data loader
; Loads before the game. INIT decompresses overlay
; to VBXE VRAM, writes XDL, sets palette.
; Game segments then overwrite $8000+ — that's fine,
; the data is already in VRAM.
; ===================================================

        org $8000

; ---- Entry point (called via INIT vector) ----
vbxe_load
        ; Detect VBXE at $D640
        lda VBXE_VC
        cmp #VBXE_ID
        beq detected
        rts              ; no VBXE, bail

detected
        ; Disable VBXE during setup
        lda #0
        sta VBXE_VC

        ; ---- Write XDL to VRAM $00000 ----
        lda #MEMAC_MCE+0 ; bank 0
        sta MEMAC_A

        ldx #xdl_len-1
wxdl    lda xdl_data,x
        sta $4000,x      ; VRAM $00000 via MEMAC
        dex
        bpl wxdl

        ; ---- Decompress RLE overlay to VRAM $10000 ----
        lda #MEMAC_MCE+OVL_BANK0
        sta MEMAC_A       ; bank 4 -> VRAM $10000
        sta cur_bank      ; track in RAM (register is write-only)

        lda #<rle_data
        sta ZSRC
        lda #>rle_data
        sta ZSRC+1
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1        ; dest = $4000 (MEMAC window start)

dloop   ldy #0
        lda (ZSRC),y      ; count
        beq ddone         ; 0 = end marker
        tax               ; X = run length
        iny
        lda (ZSRC),y      ; value
        sta fill_val      ; save in RAM (A gets trashed by bank switch)

        ; Advance ZSRC by 2
        clc
        lda ZSRC
        adc #2
        sta ZSRC
        bcc nosrhi
        inc ZSRC+1
nosrhi

wloop   lda fill_val      ; reload fill value each iteration
        ldy #0
        sta (ZDST),y

        ; Advance ZDST by 1
        inc ZDST
        bne nodshi
        inc ZDST+1
nodshi
        ; Check if ZDST reached $8000 (end of 16K MEMAC window)
        lda ZDST+1
        cmp #$80
        bcc nobnk

        ; Bank switch: reset window pointer, advance bank
        lda #$00
        sta ZDST
        lda #$40
        sta ZDST+1
        inc cur_bank
        lda cur_bank
        sta MEMAC_A

nobnk   dex
        bne wloop
        beq dloop         ; next RLE pair

ddone
        ; ---- Disable MEMAC ----
        lda #0
        sta MEMAC_A

        ; ---- Set palette (palette 1, colors 1-7) ----
        lda #1
        sta VBXE_CSEL     ; start at color index 1
        sta VBXE_PSEL     ; palette 1

        ldx #0
ploop   lda pal_data,x
        sta VBXE_CR
        inx
        lda pal_data,x
        sta VBXE_CG
        inx
        lda pal_data,x
        sta VBXE_CB       ; auto-advances CSEL
        inx
        cpx #NUM_COLORS*3
        bcc ploop

        ; ---- Set XDL address to $00000 ----
        lda #0
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2

        ; Don't enable VIDEO_CONTROL yet.
        ; The hook code enables it at title screen entry.
        rts

; ---- XDL data (13 bytes) ----
xdl_data
        ins 'data/xdl.bin'
xdl_len = *-xdl_data

; ---- Palette data (21 bytes) ----
pal_data
        ins 'data/palette.bin'

; ---- Variables ----
cur_bank  .byte 0
fill_val  .byte 0

; ---- RLE-compressed overlay (14873 bytes) ----
rle_data
        ins 'data/overlay_rle.bin'

endload = *
        .print "Loader segment: $8000-", endload-1, " (", endload-$8000, " bytes)"

; INIT vector for this segment
        org $02E2
        .word vbxe_load
