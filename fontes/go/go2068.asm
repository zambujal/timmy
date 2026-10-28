; GO2068: dot command para o DivTIESUS / Timmy: arranca o TC2068.
; Faz o mesmo que o NAV (menu das maquinas -> TC2068): carrega /BIN/2068.rom
;   24K: HOME 16K -> paginas 32,33 (e 34,35), EXROM 8K -> 36
;   32K: o mesmo e o firmware esxDOS do 2068 (ESX2068) -> 37
; apaga a pagina 0, F3 = 0, FF = 0, F4 = 0, ZXUNO DDh = 1 (modo TC2068),
; DFh = 80h (ROM em RAM) ou C0h (32K: tambem o DivMMC), IM 1, salta para 0.
; Sai-se com RESET+NMI (volta o TC2048).
;   .go2068 [ficheiro]

                    include "esxdos.inc"

PILA                equ 3deah
DIVCTRL             equ 0E3h
CODIGO              equ 5B00h

                    org 2000h

Main                ld a,h
                    or l
                    jr z,SemArgs
                    ld de,Nome
CopiaNome           ld a,(hl)
                    cp " "+1
                    jr c,FimNome
                    cp ":"
                    jr z,FimNome
                    ld (de),a
                    inc hl
                    inc de
                    jr CopiaNome
FimNome             xor a
                    ld (de),a
                    ld a,(Nome)
                    or a
                    jr nz,Abre
SemArgs             ld hl,NomeDefeito
                    ld de,Nome
                    ld bc,LNomeDefeito
                    ldir
Abre                xor a
                    rst 08h
                    db M_GETSETDRV
                    ld hl,Nome
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (FHandle),a
                    ld hl,StatBuf
                    rst 08h
                    db F_FSTAT
                    jp c,MauTamanho
                    ld hl,(StatBuf+9)
                    ld a,h
                    or l
                    jr nz,MauTamanho
                    ld hl,(StatBuf+7)
                    ld (Tamanho),hl
                    ld a,l
                    or a
                    jr nz,MauTamanho
                    ld a,h
                    cp 60h
                    ld c,80h            ; DF: ROM em RAM, sem o DivMMC
                    jr z,TamOk
                    cp 80h
                    jr nz,MauTamanho
                    ld c,0C0h           ; 32K: firmware na pagina 37, com o DivMMC
TamOk               ld a,c
                    ld (ValorDF),a
                    di
                    ld (BackupSP),sp
                    ld sp,PILA
                    ld a,(FHandle)
                    ld hl,8000h
                    ld bc,(Tamanho)
                    rst 08h
                    db F_READ
                    jr c,ErroLeitura
                    ld hl,(Tamanho)
                    or a
                    sbc hl,bc
                    jr nz,ErroLeitura
                    ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    ld a,(Tamanho+1)
                    ld (CTam+1-CodigoEnRAM+CodigoSrc),a
                    ld a,(ValorDF)
                    ld (CDF+1-CodigoEnRAM+CodigoSrc),a
                    ld hl,CodigoSrc
                    ld de,CODIGO
                    ld bc,LCodigo
                    ldir
                    jp CODIGO

MauTamanho          ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    ld hl,MsgTamanho
                    jr Print
ErroLeitura         ld a,(FHandle)      ; a pilha do BASIC ja' foi escrita: nao se volta
                    rst 08h
                    db F_CLOSE
                    ld hl,MsgLeitura
                    call Print
                    di
                    halt
Print               ld a,(hl)
                    or a
                    ret z
                    rst 10h
                    inc hl
                    jr Print

; ---------------------------------------------------------------------------
CodigoSrc
                    disp CODIGO
CodigoEnRAM         di
                    ld sp,6000h
                    ld hl,8000h         ; HOME 0000-1FFF -> 32 e 34
                    ld a,80h+32
                    call Copia
                    ld hl,8000h
                    ld a,80h+34
                    call Copia
                    ld hl,0A000h        ; HOME 2000-3FFF -> 33 e 35
                    ld a,80h+33
                    call Copia
                    ld hl,0A000h
                    ld a,80h+35
                    call Copia
                    ld hl,0C000h        ; EXROM -> 36
                    ld a,80h+36
                    call Copia
CTam                ld a,60h
                    cp 80h
                    jr nz,SemEsx
                    ld hl,0E000h        ; ESX2068 -> 37
                    ld a,80h+37
                    call Copia
SemEsx              ld a,80h+0          ; apaga a pagina 0: o esxDOS reinicia-se
                    out (DIVCTRL),a
                    ld hl,2000h
                    ld de,2001h
                    ld (hl),l
                    ld bc,1FFFh
                    ldir
                    xor a
                    ld bc,00F3h         ; F3 = 0 (antes da FF: com o bit 5 a FF e' ignorada)
                    out (c),a
                    out (0FFh),a
                    ld bc,0FFF4h
                    out (c),a
                    ld bc,0FC3Bh        ; DDh = 1: modo TC2068 na DivTIESUS
                    ld a,0DDh
                    out (c),a
                    inc b
                    ld a,1
                    out (c),a
                    dec b
                    ld a,0DFh           ; modo ROM em RAM (C0h: tambem o DivMMC)
                    out (c),a
                    inc b
CDF                 ld a,80h
                    out (c),a
                    xor a
                    out (DIVCTRL),a
                    ld a,3Fh
                    ld i,a
                    im 1
                    jp 0
Copia               out (DIVCTRL),a     ; HL -> pagina A (8K em 2000h)
                    ld de,2000h
                    ld bc,2000h
                    ldir
                    xor a
                    out (DIVCTRL),a
                    ret
                    ent
LCodigo             equ $-CodigoSrc
                    assert LCodigo <= 256

NomeDefeito         db "/BIN/2068.rom",0
LNomeDefeito        equ $-NomeDefeito
MsgTamanho          db "GO2068: 2068.rom de 24K ou 32K",13,0
MsgLeitura          db "GO2068: erro a ler",13,0
FHandle             db 0
Tamanho             dw 0
ValorDF             db 0
BackupSP            dw 0
StatBuf             ds 12
Nome                ds 64
