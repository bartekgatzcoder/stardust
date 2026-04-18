; VBXE Sprite Handler for Starquake — Phase 1 (minimal VBI).
;
; Installed at $9E00 by the copy-down extension.
; VBXE_VC is set to 1 once in the loader and stays on permanently —
; this VBI only flips the XDL address between title and gameplay.
;
; The original VBI at $0BD6 did four things before JMP XITVBV:
;   LDA $AA / STA $D018    ; update COLPF0 from game variable
;   LDA #$00 / STA $5F     ; clear $5F (frame-timer flag used by
;                          ; the animation code at $3401-$3416)
; We REPLACE that 18-byte region with `JMP $9E00` + NOPs, so this
; handler MUST reproduce both of those writes. Otherwise the frame
; timer never resets and the game hangs waiting on animation frames.
;
; Title:    $27 = 0    → XDL at VRAM $00000
; Gameplay: $27 != 0   → XDL at VRAM $00020

VBXE_XA0 = $D641
VBXE_XA1 = $D642
VBXE_XA2 = $D643
MEMAC_A  = $D65D
COLPF0   = $D018
XITVBV   = $E462

TITLE_FG = $27
FRAME_VAR = $AA    ; game-side source for COLPF0
FRAME_FLAG = $5F   ; cleared every VBI; incremented by timing code

        org $9E00

sprite_handler
        ; === Original VBI side-effects we displaced ===
        lda FRAME_VAR
        sta COLPF0
        lda #$00
        sta FRAME_FLAG

        ; === XDL switch ===
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
