; VBXE Hook Code for Starquake
; Loads AFTER the game. INIT patches the game
; to enable VBXE overlay on title screen entry.
;
; Hook chain:
;   INIT → patches relocator JMP at $BC1A
;   relocator runs → JMPs to postrel
;   postrel → patches $0BBF with JMP tsetup
;   game reaches title screen → $0BBF fires
;   tsetup → enables VBXE, continues game

VBXE_VC    = $D640
VBXE_ID    = $10

VVBLKI     = $0222
GAME_ENTRY = $05B9
GAME_VBI   = $0BD6
RELOC_JMP  = $BC1A
HOOK_ADDR  = $0BBF
HOOK_CONT  = $0B81
SDMCTL     = $022F

        org $0400

; ---- INIT (called at XEX load, after game loaded) ----
hook_init
        ; Only patch if VBXE was detected (check core ver)
        lda VBXE_VC
        cmp #VBXE_ID
        beq dodet
        rts
dodet
        ; Patch relocator JMP at $BC1A to go to postrel
        lda #<postrel
        sta RELOC_JMP+1
        lda #>postrel
        sta RELOC_JMP+2
        rts

; ---- POST-RELOC (game relocated, now in runtime addresses) ----
postrel
        ; Patch title-ready point with JMP tsetup
        lda #$4C          ; JMP opcode
        sta HOOK_ADDR
        lda #<tsetup
        sta HOOK_ADDR+1
        lda #>tsetup
        sta HOOK_ADDR+2
        jmp GAME_ENTRY

; ---- TITLE SETUP (title screen is ready to display) ----
tsetup
        ; Enable VBXE XDL
        lda #$01
        sta VBXE_VC

        ; Do the original code at $0BBF:
        ;   LDA #$3A / CLI / BNE $0B81
        lda #$3A
        sta SDMCTL
        cli
        jmp HOOK_CONT

        .if * > $0580
        .error "Hook segment exceeds $0580!"
        .endif

; INIT vector for this segment
        org $02E2
        .word hook_init
