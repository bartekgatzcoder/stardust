; VBXE Hook Code for Starquake
;
; Hook points (in the $20C5 title/screen cycling loop):
;   $20CA — JSR $356C: title screen about to display → enable VBXE
;   $20F2 — LDX #$00 / JSR $2639: next screen init → disable VBXE
;
; Does NOT hook $0BBF — that code is shared by all screens
; and would re-enable VBXE during non-title screen inits.

VBXE_VC    = $D640
VBXE_ID    = $10

GAME_ENTRY = $05B9
RELOC_JMP  = $BC1A

; Title enable: $20CA has JSR $356C (3 bytes)
TENAB_ADDR = $20CA
TENAB_ORIG = $356C       ; original JSR target
TENAB_CONT = $20CD       ; next instruction after JSR

; Title disable: $20F2 has LDX #$00 (2b) + JSR $2639 (3b)
TDISAB_ADDR = $20F2
TDISAB_CONT = $20F7      ; first intact instruction after 3 patched bytes

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
        ; Patch $20CA: JSR $356C -> JMP tsetup
        lda #$4C
        sta TENAB_ADDR
        lda #<tsetup
        sta TENAB_ADDR+1
        lda #>tsetup
        sta TENAB_ADDR+2

        ; Patch $20F2: LDX #$00/JSR -> JMP tdone
        lda #$4C
        sta TDISAB_ADDR
        lda #<tdone
        sta TDISAB_ADDR+1
        lda #>tdone
        sta TDISAB_ADDR+2

        jmp GAME_ENTRY

; ---- TITLE SCREEN ENABLE ----
; Replaces JSR $356C at $20CA.
tsetup
        lda #$01
        sta VBXE_VC       ; overlay on
        jsr TENAB_ORIG    ; JSR $356C (original)
        jmp TENAB_CONT    ; -> $20CD

; ---- NEXT SCREEN DISABLE ----
; Replaces LDX #$00 / JSR $2639 at $20F2.
tdone
        lda #$00
        sta VBXE_VC       ; overlay off
        ldx #$00          ; original $20F2
        jsr $2639         ; original $20F4
        jmp TDISAB_CONT   ; -> $20F7

        .if * > $0580
        .error "Hook segment exceeds $0580!"
        .endif

; INIT vector
        org $02E2
        .word hook_init
