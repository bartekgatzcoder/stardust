; VBXE Sprite Handler for Starquake — Phase 1 (minimal VBI).
;
; Installed at $9E00 by the copy-down extension.
; VBXE_VC is set to 1 once in the loader and stays on permanently —
; this VBI only flips the XDL address between title and gameplay.
;
; Title:    $27 = 0       → XDL at VRAM $00000
; Gameplay: $27 != 0      → XDL at VRAM $00020
;
; No MEMAC access, no ZP use, no sprite drawing. Sprite rendering
; for gameplay lives in a separate routine called from the main
; loop — wired up in a later phase.

VBXE_XA0 = $D641
VBXE_XA1 = $D642
VBXE_XA2 = $D643
XITVBV   = $E462

TITLE_FG = $27

        org $9E00

sprite_handler
        lda TITLE_FG
        bne @game

        ; Title path: XDL at VRAM $00000.
        lda #$00
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        jmp XITVBV

@game
        ; Gameplay path: XDL at VRAM $00020.
        lda #$20
        sta VBXE_XA0
        lda #$00
        sta VBXE_XA1
        sta VBXE_XA2
        jmp XITVBV

handler_end = *
