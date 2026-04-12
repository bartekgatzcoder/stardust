; VBXE Hook Code for Starquake
;
; Hook points (in the $20C5 title/screen cycling loop):
;   $20CA — JSR $356C: title screen setup → enable VBXE
;   $20F2 — LDX #$00 / JSR $2639: next screen init → disable VBXE
;
; $20CA hook uses JSR-redirect: the original JSR $356C
; is replaced with JSR tsetup. tsetup enables VBXE then
; JMPs to $356C. When $356C does RTS, it returns to
; $20CD (the return address pushed by the ORIGINAL JSR).
; Stack-neutral — no extra frames.
;
; $20F2 hook uses the same pattern for $2639.

VBXE_VC     = $D640
VBXE_ID     = $10

GAME_ENTRY  = $05B9
RELOC_JMP   = $BC1A

; Addresses in the $20C5 title/screen loop
TENAB_ADDR  = $20CA      ; JSR $356C
TENAB_ORIG  = $356C
TDISAB_ADDR = $20F2      ; LDX #$00 at $20F2, JSR $2639 at $20F4

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
postrel
        ; $20CA: replace JSR $356C with JSR tsetup
        ; tsetup does VBXE enable then JMP $356C.
        ; $356C's RTS pops $20CC → continues at $20CD.
        lda #<tsetup
        sta TENAB_ADDR+1
        lda #>tsetup
        sta TENAB_ADDR+2
        ; (opcode at $20CA stays $20 = JSR, unchanged)

        ; $20F2: replace LDX #$00 / JSR $2639 with
        ; JSR tdone / NOP NOP.
        ; tdone does VBXE disable, LDX #0, JMP $2639.
        ; $2639's RTS pops $20F4 → continues at $20F5.
        ; But $20F5 has the old target bytes ($39 $26),
        ; which would execute as AND $26. BAD!
        ;
        ; Instead: replace all 5 bytes $20F2-$20F6 with
        ; JSR tdone + NOP + NOP. tdone does everything
        ; and JMPs to $20F7 directly.
        lda #$20          ; JSR opcode
        sta TDISAB_ADDR
        lda #<tdone
        sta TDISAB_ADDR+1
        lda #>tdone
        sta TDISAB_ADDR+2
        lda #$EA          ; NOP
        sta TDISAB_ADDR+3
        sta TDISAB_ADDR+4

        jmp GAME_ENTRY

; ---- TITLE ENABLE ----
; Called via JSR from $20CA. Enables VBXE then falls
; into $356C. When $356C does RTS, it returns to $20CD
; (the address pushed by the JSR at $20CA).
tsetup
        lda #$00
        sta VBXE_VC+1     ; XDL_ADR0 = 0
        sta VBXE_VC+2     ; XDL_ADR1 = 0
        sta VBXE_VC+3     ; XDL_ADR2 = 0
        lda #$01
        sta VBXE_VC       ; XDL enabled
        jmp TENAB_ORIG    ; -> $356C

; ---- NEXT SCREEN DISABLE ----
; Called via JSR from $20F2. Disables VBXE, does the
; original LDX #0, then JMPs to $2639. When $2639
; does RTS, it returns to $20F5 — but we NOPed those
; bytes, so it falls through to $20F7. Clean.
tdone
        lda #$00
        sta VBXE_VC
        ldx #$00
        jmp $2639

        .if * > $0580
        .error "Hook segment exceeds $0580!"
        .endif

; INIT vector
        org $02E2
        .word hook_init
