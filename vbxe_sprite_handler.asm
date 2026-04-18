; VBXE Sprite Handler for Starquake — v2
; Runs at $9E00 during VBI.
;
; Phase 1: VBXE on/off + gameplay XDL switch.
;          Sprite drawing disabled until MEMAC_B conflict is resolved.
;          (Handler lives at $9E00 inside $8000-$BFFF, so MEMAC_B
;          would remap the handler's own code to VRAM mid-execution.)

VBXE_VC  = $D640
VBXE_XA0 = $D641
VBXE_XA1 = $D642
VBXE_XA2 = $D643
MEMAC_A  = $D65D
XITVBV   = $E462

TITLE_FG = $27

        org $9E00

sprite_handler
        lda TITLE_FG
        bne do_gameplay

        ; --- Title screen: XDL at $00000, VBXE on ---
        lda #$00
        sta VBXE_XA0
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC
        jmp XITVBV

do_gameplay
        ; --- Gameplay: XDL at $00020, VBXE on ---
        lda #$20
        sta VBXE_XA0
        lda #$00
        sta VBXE_XA1
        sta VBXE_XA2
        lda #$01
        sta VBXE_VC

        ; TODO: sprite drawing via MEMAC_A two-pass
        ; (read sprite row from VRAM bank, copy to ZP temp,
        ;  switch to overlay bank, write from temp)

        jmp XITVBV
