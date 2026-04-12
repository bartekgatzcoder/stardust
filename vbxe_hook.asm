; VBXE Hook Code for Starquake
; Loads AFTER the game. INIT patches the game
; to enable VBXE overlay on title screen entry
; and disable it on title screen exit.
;
; Hook chain:
;   INIT -> patches relocator JMP at $BC1A
;   relocator -> postrel
;   postrel -> patches $0BBF (title entry) and $36AC (title exit)
;   title screen entry ($0BBF) -> tsetup: enable VBXE
;   title screen exit  ($36AC) -> tdone:  disable VBXE

VBXE_VC    = $D640
VBXE_ID    = $10

SDMCTL     = $022F
GAME_ENTRY = $05B9
RELOC_JMP  = $BC1A
HOOK_ADDR  = $0BBF      ; title entry point
HOOK_CONT  = $0B81
EXIT_ADDR  = $36AC      ; title exit point
EXIT_CONT  = $36B0      ; continue after 3 patched bytes

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

        ; Patch title exit: $36AC -> JMP tdone
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
        sta VBXE_VC       ; XDL enabled

        ; Original code at $0BBF:
        ;   LDA #$3A / CLI / BNE $0B81
        lda #$3A
        sta SDMCTL
        cli
        jmp HOOK_CONT

; ---- TITLE EXIT (disables VBXE overlay) ----
tdone
        lda #$00
        sta VBXE_VC       ; XDL disabled

        ; Original code at $36AC-$36AF:
        ;   CLI / PHA / LDA #$00
        cli
        pha
        lda #$00
        jmp EXIT_CONT     ; continue at $36B0

        .if * > $0580
        .error "Hook segment exceeds $0580!"
        .endif

; INIT vector
        org $02E2
        .word hook_init
