; VBXE Title Screen - XCOLOR palette remap.
; Fills all 256 palette entries: 0=black, 1-255=cyan.
; This way any COLPF value the game's DLI sets maps
; to either black (background) or cyan (foreground).
; No ANTIC changes needed. One-shot VBI hook.

VBXE_VC   = $D640
VBXE_CSEL = $D644
VBXE_PSEL = $D645
VBXE_CR   = $D646
VBXE_CG   = $D647
VBXE_CB   = $D648

SDMCTL    = $022F
VVBLKI    = $0222

GAME_ENTRY = $05B9
GAME_VBI   = $0BD6
RELOC_JMP  = $BC1A
HOOK_ADDR  = $0BBF
HOOK_CONT  = $0B81

        org $0400

; --- INIT (XEX load time) ---
init    lda #<postrel
        sta RELOC_JMP+1
        lda #>postrel
        sta RELOC_JMP+2
        rts

; --- POST-RELOC ---
postrel lda #$4C
        sta HOOK_ADDR
        lda #<tsetup
        sta HOOK_ADDR+1
        lda #>tsetup
        sta HOOK_ADDR+2
        jmp GAME_ENTRY

; --- TITLE SETUP ---
tsetup  sei
        lda #<vbihook
        sta VVBLKI
        lda #>vbihook
        sta VVBLKI+1
        lda #$3A
        sta SDMCTL
        cli
        jmp HOOK_CONT

; --- VBI HOOK (one-shot) ---
vbihook
        ; Palette page 0, entry 0 = black
        lda #0
        sta VBXE_PSEL
        sta VBXE_CSEL
        sta VBXE_CR
        sta VBXE_CG
        sta VBXE_CB          ; CSEL auto-advances to 1

        ; Fill entries 1-255 with C64 cyan
        ldx #255
fill    lda #106
        sta VBXE_CR
        lda #191
        sta VBXE_CG
        lda #198
        sta VBXE_CB          ; auto-advance
        dex
        bne fill

        ; Enable XCOLOR
        lda #$01
        sta VBXE_VC

        ; Unhook → game VBI
        lda #<GAME_VBI
        sta VVBLKI
        lda #>GAME_VBI
        sta VVBLKI+1

        jmp GAME_VBI

        .if * > $0580
        .error "Too large!"
        .endif

        org $02E2
        .word init
