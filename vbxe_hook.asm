; VBXE Hook Code for Starquake
; Loads AFTER the game. INIT patches the game
; to enable VBXE overlay on title screen entry
; and disable it when the next screen starts.
;
; Hook points (all in post-relocation runtime space):
;   $0BBF — title screen is ready to display
;   $20F2 — title screen done, next screen init begins
;
; Both fire-to-start and music-end paths converge at $20F2
; before calling the next-screen initializer at $2639.

VBXE_VC    = $D640
VBXE_ID    = $10

SDMCTL     = $022F
GAME_ENTRY = $05B9
RELOC_JMP  = $BC1A

; Title entry hook
HOOK_ADDR  = $0BBF       ; LDA #$3A / CLI / BNE $0B81
HOOK_CONT  = $0B81

; Title exit hook — next screen init
; Original: LDX #$00 / JSR $2639 / LDA #$86 / JMP $3611
EXIT_ADDR  = $20F2
EXIT_CONT  = $20F7       ; first intact instruction after 3 patched bytes

        org $0400

; ---- INIT (called at XEX load) ----
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
postrel
        ; Patch title entry: $0BBF -> JMP tsetup
        lda #$4C
        sta HOOK_ADDR
        lda #<tsetup
        sta HOOK_ADDR+1
        lda #>tsetup
        sta HOOK_ADDR+2

        ; Patch next-screen init: $20F2 -> JMP tdone
        lda #$4C
        sta EXIT_ADDR
        lda #<tdone
        sta EXIT_ADDR+1
        lda #>tdone
        sta EXIT_ADDR+2

        jmp GAME_ENTRY

; ---- TITLE ENTRY (enables VBXE overlay) ----
tsetup
        lda #$01
        sta VBXE_VC

        ; Original code at $0BBF:
        lda #$3A
        sta SDMCTL
        cli
        jmp HOOK_CONT

; ---- TITLE EXIT (disables VBXE overlay) ----
; Replaces $20F2-$20F4 (LDX #$00 / JSR opcode).
; Executes the overwritten instructions, then
; continues at $20F7 (LDA #$86 / JMP $3611).
tdone
        lda #$00
        sta VBXE_VC       ; XDL disabled

        ldx #$00          ; original $20F2
        jsr $2639         ; original $20F4
        jmp EXIT_CONT     ; -> $20F7

        .if * > $0580
        .error "Hook segment exceeds $0580!"
        .endif

; INIT vector
        org $02E2
        .word hook_init
