; VBXE Hook Code for Starquake
;
; The game zeroes pages 4-5 ($0400-$057F) during gameplay.
; Hook trampolines must live in the GAME's own runtime
; space. $9E00-$9E7F is unused (beyond game data end).
;
; Strategy:
;   - INIT/postrel at $0400 (one-time, can be destroyed)
;   - postrel copies trampoline code to $9E00 at runtime
;   - Patches $20CA/$20F2 to call $9E00/$9E0D
;   - $9E00 survives gameplay

VBXE_VC     = $D640
VBXE_ID     = $10

GAME_ENTRY  = $05B9
RELOC_JMP   = $BC1A

TENAB_ADDR  = $20CA      ; JSR $356C → JSR tsetup
TDISAB_ADDR = $20F2      ; LDX #$00 / JSR $2639 → JSR tdone

SAFE_ADDR   = $9E00      ; unused game space for runtime hooks

        org $0400

; ---- INIT ----
hook_init
        lda VBXE_VC
        cmp #VBXE_ID
        beq dodet
        rts
dodet
        lda #<postrel
        sta RELOC_JMP+1
        lda #>postrel
        sta RELOC_JMP+2
        rts

; ---- POST-RELOC ----
; Copies trampoline code to $9E00, patches hook sites,
; then starts the game. This code at $0400 will be
; destroyed during gameplay — that's fine.
postrel
        ; Copy trampoline code to $9E00
        ldx #tramp_len-1
cloop   lda tramp_code,x
        sta SAFE_ADDR,x
        dex
        bpl cloop

        ; Patch $20CA: JSR $356C → JSR $9E00 (tsetup)
        lda #<SAFE_ADDR
        sta TENAB_ADDR+1
        lda #>SAFE_ADDR
        sta TENAB_ADDR+2

        ; Patch $20F2: LDX#0/JSR$2639 → JSR $9E0D/NOP/NOP
        lda #$20
        sta TDISAB_ADDR
        lda #<[SAFE_ADDR+tsetup_len]
        sta TDISAB_ADDR+1
        lda #>[SAFE_ADDR+tsetup_len]
        sta TDISAB_ADDR+2
        lda #$EA
        sta TDISAB_ADDR+3
        sta TDISAB_ADDR+4

        jmp GAME_ENTRY

; ---- Trampoline code (copied to $9E00 at runtime) ----
; Must be position-independent relative to SAFE_ADDR.
tramp_code

; tsetup: enable VBXE, then jump to title builder.
; Called via JSR from $20CA. $356C's RTS returns to $20CD.
t_tsetup = *-tramp_code
        lda #$00
        sta VBXE_VC+1     ; XDL_ADR0
        sta VBXE_VC+2     ; XDL_ADR1
        sta VBXE_VC+3     ; XDL_ADR2
        lda #$01
        sta VBXE_VC       ; XDL enabled
        jmp $356C
tsetup_len = *-tramp_code

; tdone: disable VBXE, then jump to next-screen init.
; Called via JSR from $20F2. $2639's RTS returns to
; $20F5 (NOP NOP → $20F7).
t_tdone = *-tramp_code-tsetup_len
        lda #$00
        sta VBXE_VC       ; XDL disabled
        ldx #$00
        jmp $2639

tramp_len = *-tramp_code

        .print "Trampoline: ", tramp_len, " bytes at $9E00"

        .if * > $0580
        .error "Hook segment exceeds $0580!"
        .endif
        .if tramp_len > $80
        .error "Trampoline too large for $9E00-$9E7F!"
        .endif

; INIT vector
        org $02E2
        .word hook_init
