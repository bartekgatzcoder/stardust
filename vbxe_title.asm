; VBXE Title Screen Patch for Starquake (v4)
; 
; Hook: Patch game's VVBLKI setup at $0BA4/$0BA9 to
; point to our hook instead of $0BD6. The game's VBI
; handler at $0BD6 stays UNMODIFIED.

VBXE    = $D640
VBXE_VC = VBXE+$00
VBXE_XA0 = VBXE+$01
VBXE_XA1 = VBXE+$02
VBXE_XA2 = VBXE+$03
VBXE_CSEL = VBXE+$04
VBXE_PSEL = VBXE+$05
VBXE_CR = VBXE+$06
VBXE_CG = VBXE+$07
VBXE_CB = VBXE+$08
VBXE_MC = VBXE+$1E
VBXE_MB = VBXE+$1F

PORTB    = $D301
NMIEN    = $D40E
COLPF1_HW = $D017
COLPF2_HW = $D018
COLBK_HW = $D01A
COLPF1_S = $02C5
COLPF2_S = $02C6
COLBK_S  = $02C8

BITMAP_ADDR = $A1F0
DL_ADDR   = $395E
GAME_VBI  = $0BD6
GAME_ENTRY = $05B9
RELOC_JMP = $BC1A
; Game's VVBLKI setup: LDA #$0B at $0BA4, LDA #$D6 at $0BA9
GAME_VBI_HI_PATCH = $0BA5   ; operand of LDA #$0B
GAME_VBI_LO_PATCH = $0BAA   ; operand of LDA #$D6
NUM_COLORS = 7
DATA_VRAM = $C000
DATA_BMP  = $D800

ZSRC = $FB
ZDST = $FD

        org $0400

; === Data ===
pal_data  ins 'data/c64_palette.bin'
copy_pg   .byte 0

; === Copy subroutine ===
copy_pages
        ldy #0
cp_lp   lda (ZSRC),y
        sta (ZDST),y
        iny
        bne cp_lp
        inc ZSRC+1
        inc ZDST+1
        dec copy_pg
        bne cp_lp
        rts

; === INIT ===
init_routine
        lda #<post_reloc
        sta RELOC_JMP+1
        lda #>post_reloc
        sta RELOC_JMP+2
        rts

; === POST-RELOC ===
; Patches game's VBI address setup to install our hook.
; The game at $0BA4: LDA #$0B / STA $0223
;                    LDA #$D6 / STA $0222
; We change the operands to our hook address.
post_reloc
        lda #>vbi_hook
        sta GAME_VBI_HI_PATCH
        lda #<vbi_hook
        sta GAME_VBI_LO_PATCH
        jmp GAME_ENTRY

; === VBI HOOK ===
; Called as the VBI immediate handler (instead of $0BD6).
; Checks for title screen; when ready, sets up VBXE.
; Always ends by calling the original handler at $0BD6.
vbi_hook
        ; NMI handler already pushed A/X/Y
        lda DL_ADDR
        cmp #$70
        bne vskip
        lda DL_ADDR+3
        cmp #$4F
        bne vskip
        lda DL_ADDR+5
        cmp #>BITMAP_ADDR
        bne vskip
        lda BITMAP_ADDR+210
        bne vsetup
vskip   jmp GAME_VBI

vsetup
        ; === Disable OS ROM to access data ===
        lda PORTB
        pha
        and #$FE
        sta PORTB

        ; === Upload VRAM data $C000→VBXE $00000 ===
        lda #$58
        sta VBXE_MC
        lda #$80
        sta VBXE_MB
        lda #$00
        sta ZSRC
        sta ZDST
        lda #>DATA_VRAM
        sta ZSRC+1
        lda #$50
        sta ZDST+1
        lda #$10
        sta copy_pg
        jsr copy_pages

        ; === Upload bitmap $D800→VBXE $01000 ===
        lda #$81
        sta VBXE_MB
        lda #$00
        sta ZSRC
        sta ZDST
        lda #>DATA_BMP
        sta ZSRC+1
        lda #$50
        sta ZDST+1
        lda #$10
        sta copy_pg
        jsr copy_pages

        ; === Upload bitmap remainder→VBXE $02000 ===
        lda #$82
        sta VBXE_MB
        lda #$00
        sta ZDST
        lda #$50
        sta ZDST+1
        lda #14
        sta copy_pg
        jsr copy_pages

        lda #0
        sta VBXE_MC
        sta VBXE_MB

        ; === Restore OS ROM ===
        pla
        sta PORTB

        ; === Copy bitmap from VBXE→$A1F0 ===
        lda #$58
        sta VBXE_MC
        lda #$81
        sta VBXE_MB
        lda #$00
        sta ZSRC
        lda #$50
        sta ZSRC+1
        lda #<BITMAP_ADDR
        sta ZDST
        lda #>BITMAP_ADDR
        sta ZDST+1
        lda #$10
        sta copy_pg
        jsr copy_pages

        lda #$82
        sta VBXE_MB
        lda #$00
        sta ZSRC
        lda #$50
        sta ZSRC+1
        lda #14
        sta copy_pg
        jsr copy_pages

        lda #0
        sta VBXE_MC
        sta VBXE_MB

        ; === Palette ===
        lda #0
        sta VBXE_PSEL
        sta VBXE_CSEL
        ldx #0
vpl     lda pal_data,x
        sta VBXE_CR
        inx
        lda pal_data,x
        sta VBXE_CG
        inx
        lda pal_data,x
        sta VBXE_CB
        inx
        cpx #NUM_COLORS*3
        bne vpl

        ; === Zero ANTIC + disable DLI ===
        lda #0
        sta COLPF1_HW
        sta COLPF2_HW
        sta COLBK_HW
        sta COLPF1_S
        sta COLPF2_S
        sta COLBK_S
        lda #$40
        sta NMIEN

        ; === Enable VBXE ===
        lda #0
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$03
        sta VBXE_VC

        ; === Unhook: restore game's VVBLKI to $0BD6 ===
        sei
        lda #<GAME_VBI
        sta $0222
        lda #>GAME_VBI
        sta $0223
        cli

        ; Jump to original VBI handler
        jmp GAME_VBI

code_end
        .if code_end > $0580
        .error "Code overflows!"
        .endif

; === DATA ===
        org DATA_VRAM
        ins 'data/vbxe_vram.bin'
        org DATA_BMP
        ins 'data/c64_bitmap.bin'
        org $02E2
        .word init_routine
