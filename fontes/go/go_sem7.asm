; GO128: dot command para o DivTIESUS num Timex TC2048 com os bancos 128K
; (bancos128.v). Carrega uma ROM de 32K do Spectrum 128 (ROM0 + ROM1) nas
; paginas 32-35 da memoria DivMMC, liga os bancos de RAM em C000-FFFF e
; arranca a ROM 0. Baseado no LOADROM do DivTIESUS (Miguel Angel Rodriguez
; Jodar), GPL v3. Nao altera o GO3E nem o LOADROM.
;
;   .go128            usa /bin/128.rom, com as traps do DivMMC (NMI) ligadas.
;                     F3 = 35: AY 128, preto unico, barramento flutuante na
;                     porta FF (sem modos Timex), tempos do 48K (50 Hz),
;                     contencao so' na RAM de video (4000h-7FFFh e bancos 5/7)
;   .go128 [-menu] [-cc] [-ts] [-timex] [-menu] [ficheiro]
;      -cc    : contencao tambem nos bancos 1 e 3, como num 128K (tambem -ct)
;      -ts    : tempos do 128K (228 T x 311 linhas, 49,4 Hz) (tambem -49)
;      -timex : a porta FF volta a ser o registo do Timex (modos de ecra)
;      -bus   : o mesmo que -timex: sem barramento flutuante na porta FF
;      -penta : Pentagon 128: tempos (224 T x 320 linhas = 71680 T, INT 80 linhas antes do
;               ecra), sem contencao nos bancos 1 e 3 (F3 bit 7) e, se o SCLD e o DivTIESUS
;               tiverem o modo sombra, as leituras da RAM de video vem da SRAM (sem contencao):
;               copia a RAM de video para a SRAM e liga o F3 bit 6. Sem sombra: so' os tempos.
;      -ayext : AY numa placa de fora (do lado do Z80): o SCLD nao responde ao FFFD/BFFD
;               (F3 bit 0 a 0) e, no Pentagon intercalado, essas portas nao esperam
;      -io    : contencao de E/S so' nas portas que o SCLD le' (F3 bit 4): as outras
;               (divMMC E3/E7/EB, Kempston 1F, ZXUNO FC3B/FD3B...) sem contencao
;      -menu  : menu do 128K, sem as traps do DivMMC (sem NMI nem esxDOS) (tambem -n)
;   .go128 -reset     sai do modo 128K e reinicia o Timex normal (com esxDOS)
;      (-50, -sc e -float continuam aceites: sao o que ja' e' o normal)
;
; Paginas: ROM0 -> 32,33   ROM1 -> 34,35   (bit 4 do 7FFD escolhe a ROM;
;          o CPLD so vai la buscar a ROM com os bancos ligados. O esxDOS e
;          o browser do NMI usam as paginas 0-15)
;          bancos 0-7 -> 16-31 (precisa a SRAM de 512K)
; Modo 128K: F4 = F0 (SCLD e DivTIESUS seguem o mesmo porto). Bancos 5 e 7
; na RAM de video do Timmy (4464 + BNK), os outros na SRAM do DivTIESUS.
; Reset + NMI desliga o modo ROM em RAM; os bancos so' saem com
; OUT 65524,0 ou desligando.

; GO1024 (-DGO1024): Pentagon 1024 no Timmy da Tang: como o .go256 e ainda o registo
; ZXUNO DDh bit 2 = 1 (1024K) e EFF7 = 0: o 7FFD usa os bits 6, 7 e 5 como bits 3, 4 e 5
; do banco (64 bancos de 16K) e o bit 5 deixa de ser o trinco. O EFF7 bit 2 = 1 volta ao 128K.
                    IFDEF GO1024
                    DEFINE GO256
                    ENDIF
                    include "esxdos.inc"
                    include "errors.inc"

PILA                equ 3deah
DIVCTRL             equ 0E3h
ZXUNOADDR           equ 0FC3Bh
MODE                equ 0DFh
CODIGO              equ 23296       ; 5B00h, buffer da impressora
PILARAM             equ 6000h       ; abaixo de 8000h, onde fica a ROM lida

                    org 2000h

Main                ld a,h
                    or l
                    jr z,SemArgs
                    call GetCmdLine
                    ld a,(ErroOp)       ; opcao desconhecida: avisa e nao faz nada
                    or a
                    jr z,OpcoesOk
                    ld hl,MsgOpcao      ; "GO128: -penti not available"
                    call Print
                    ld hl,(ErroPtr)
MostraOp            ld a,(hl)
                    cp " "+1
                    jr c,MostraFim
                    cp ":"
                    jr z,MostraFim
                    rst 10h
                    inc hl
                    jr MostraOp
MostraFim           ld hl,MsgOpcao2
                    call Print
                    or a
                    ret
OpcoesOk            ld a,(Reset)
                    or a
                    jp nz,FazReset
                    ld a,(BufferParam)
                    or a
                    jr nz,Abre
SemArgs             ld hl,NomeDefeito
                    ld de,BufferParam
                    ld bc,LNomeDefeito
                    ldir

Abre                xor a
                    rst 08h
                    db M_GETSETDRV
                    ld hl,BufferParam
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (FHandle),a

                    ; o ficheiro tem de ter 32768 bytes (ROM0+ROM1) ou 16384
                    ; (uma ROM so', copiada para os dois lugares, p.ex. a ROM
                    ; de diagnostico)
                    ld hl,StatBuf
                    rst 08h
                    db F_FSTAT
                    jp c,FechaErro
                    ld hl,(StatBuf+9)
                    ld a,h
                    or l
                    jr nz,MauTamanho
                    ld hl,(StatBuf+7)
                    ld (Tamanho),hl
                    ld de,32768
                    or a
                    sbc hl,de
                    jr z,TamanhoOk
                    ld hl,(StatBuf+7)
                    ld de,16384
                    or a
                    sbc hl,de
                    jr nz,MauTamanho
TamanhoOk
                    ; le a ROM para 8000h. A pilha do BASIC fica nessa
                    ; zona, por isso usa-se a pilha na area do comando.
                    di
                    ld (BackupSP),sp
                    ld sp,PILA
                    ld a,(FHandle)
                    ld hl,32768
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

                    ; ROM de 16K: copia-a tambem para C000h (ROM1 = ROM0)
                    ld hl,(Tamanho)
                    ld a,h
                    cp 40h
                    jr nz,Rom32
                    ld hl,32768
                    ld de,49152
                    ld bc,16384
                    ldir
Rom32
                    ld a,(DivMMCOption)
                    ld (PatchDivMMCOption+1),a
                    ld a,(OpcaoF3)
                    bit 7,a             ; Timex 128 (-timex/-bus, sem Pentagon): so' o AY do
                    jr nz,F3pronto      ; Timex (F5/F6), o SCLD larga o FFFD/BFFD (bit 0 a 0)
                    bit 5,a
                    jr nz,F3pronto
                    and 0FEh
F3pronto            ld (PatchF3+1),a
                    ld hl,CodigoEnRAM
                    ld de,CODIGO
                    ld bc,LCodigoEnRAM
                    ldir
                    jp CODIGO

MauTamanho          ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    ld hl,MsgTamanho
                    call Print
                    or a
                    ret

FechaErro           push af
                    ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    pop af
                    ret

                    ; a pilha e as UDG do BASIC ja foram escritas por cima:
                    ; nao se pode voltar ao BASIC
ErroLeitura         ld a,(FHandle)
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
; Corre na RAM principal a partir de 5B00h
CodigoEnRAM         di
                    ld sp,PILARAM
                    ld hl,32768
                    ld a,128+32         ; ROM0 -> paginas 32,33; ROM1 -> 34,35
                    ld b,4
CopiaPag            push bc
                    out (DIVCTRL),a
                    ld de,8192
                    ld bc,8192
                    ldir
                    inc a
                    pop bc
                    djnz CopiaPag

                    ld a,128+0          ; apaga a pagina 0, como o LOADROM
                    out (DIVCTRL),a
                    ld hl,8192
                    ld de,8193
                    ld (hl),l
                    ld bc,8191
                    ldir

                    ; 7FFD = 0 (ROM0, banco 0) e 1FFD = 0, ainda com a
                    ; descodificacao do +2A, antes de ligar os bancos
                    xor a
                    ld bc,7ffdh
                    out (c),a
                    ld b,1fh
                    out (c),a

                    ; Timex: ecra normal, sem DOCK; 8000-FFFF fora da RAM
                    ; interna (F4 = F0): e' o modo 128K no SCLD e no
                    ; DivTIESUS. FFF4 para nao tocar no 7FFD.
                    out (0ffh),a
PatchF3             ld a,3              ; OUT 243,3: AY 128 e preto unico (o resto com -49 e -cc)
                    ld bc,00f3h
                    out (c),a
                    ld a,0f0h
                    ld bc,0fff4h
                    out (c),a

                    ; -penta: modo sombra (leituras da RAM de video na SRAM do DivTIESUS)
                    ld a,(CODIGO+PatchF3+1-CodigoEnRAM)
                    ld d,a              ; d = F3
                    and 80h
                    jr z,SemSombra
                    ld hl,CODIGO+TestaScld0-CodigoEnRAM   ; o teste do SCLD corre fora da RAM de
                    ld de,TestaScldF    ; video (em F000h, banco 0): durante o teste as
                    ld bc,LTestaScld    ; leituras da RAM de video nao tem resposta
                    ldir
                    ld a,(CODIGO+PatchF3+1-CodigoEnRAM)
                    ld d,a
                    xor a
                    call PoeDD          ; copia desligada
                    ld e,5Ah            ; o SCLD tem o modo? (com o bit 6 e sem copia, ninguem
                    call TestaScld      ; responde a' leitura: le-se outra coisa)
                    jr z,SemSombra
                    ld e,0A5h
                    call TestaScld
                    jr z,SemSombra
                    ld a,2
                    call PoeDD          ; copia ligada
                    ld e,55h            ; a DivTIESUS copia? (pagina 26 do divMMC em 2000h)
                    call TestaCopia
                    jr nz,SemCopia
                    ld e,0AAh
                    call TestaCopia
                    jr nz,SemCopia
                    ld hl,4000h         ; copia: ler e escrever cada byte de 4000h-7FFFh
CopiaV              ld a,(hl)
                    ld (hl),a
                    inc hl
                    ld a,h
                    cp 80h
                    jr nz,CopiaV
                    ld a,d
                    or 40h              ; F3 bit 6: modo sombra
                    ld d,a
                    call LigaSombra     ; o OUT corre em F000h (fora da RAM de video): o 1.o
                    jr Marca            ; opcode depois do OUT ja' nao vem de 5Bxxh
SemCopia            xor a
                    call PoeDD
                    jr Marca
SemSombra           ld a,d
                    and 80h
                    jr z,ROMram
Marca               ld a,128+12         ; para o NAV: os bits 6-7 do F3 na pagina 12 ("MN",F3,3)
                    out (DIVCTRL),a
                    ld hl,"MN"
                    ld (3FFCh),hl
                    ld a,d
                    and 0C8h            ; bits 6-7 (sombra, Pentagon) e 3 (Pentagon 256)
                    bit 7,a             ; o bit 3 so' com o Pentagon (bit 7); JR: este codigo
                    jr nz,MarcaP        ; corre em 5B00h, um JP iria para o endereco montado
                    and 0C0h
MarcaP              ld (3FFEh),a
                    ld a,d              ; maquina: 3 ZX 128K (F3 bit 5, barramento flutuante)
                    and 20h             ; ou 4 Timex 128 (-bus)
                    ld a,3
                    jr nz,MaqZX
                    inc a
MaqZX               ld (3FFFh),a
                    xor a
                    out (DIVCTRL),a
ROMram
                    ld a,d              ; DDh sempre escrito (2026-10-20): bit 0 = 0 (sai do TC2068, se
                    and 40h             ; vinha dele), bit 1 = copia se a sombra ficou ligada,
                    rrca                ; bit 2 = 1024K (so' no .go1024)
                    rrca
                    rrca
                    rrca
                    rrca
                    IFDEF GO1024
                    or 4
                    ENDIF
                    call PoeDD
                    IFDEF GO1024
                    xor a               ; EFF7 = 0: 1024K ligado
                    ld bc,0EFF7h
                    out (c),a
                    ENDIF

                    ; (o registo ZXUNO DE ja nao e' usado: o modo vem do F4)

                    ; modo ROM em RAM
                    ld bc,ZXUNOADDR
                    ld a,MODE
                    out (c),a
                    inc b
PatchDivMMCOption   ld a,0              ; bit 6 = traps do DivMMC
                    in l,(c)
                    set 7,l
                    or l
                    out (c),a

                    xor a               ; CONMEM desligado
                    out (DIVCTRL),a
                    jp 0

; (sub-rotinas do CodigoEnRAM: chamadas em 5B00h+, com enderecos relativos ao CODIGO)
PoeDD               equ CODIGO+PoeDD0-CodigoEnRAM
TestaScldF          equ 0F000h
TestaScld           equ TestaScldF
LigaSombra          equ TestaScldF+LigaSombra0-TestaScld0
TestaCopia          equ CODIGO+TestaCopia0-CodigoEnRAM
PoeDD0              push bc             ; registo ZXUNO DDh = A
                    ld bc,ZXUNOADDR
                    push af
                    ld a,0DDh
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    pop bc
                    ret
TestaScld0          ld a,e              ; Z = le-se o que esta' em 4000h (o SCLD nao fechou o 245)
                    ld (4000h),a
                    ld a,d
                    or 40h
                    ld bc,00f3h
                    out (c),a
                    ld a,(4000h)
                    out (c),d
                    ld b,0              ; espera antes do RET (a pilha esta' na RAM de video)
TS1                 djnz TS1
                    cp e
                    ret
; A = F3 com o bit 6. Corre em F000h+: depois do OUT espera ~1 ms antes de voltar a ler
; a RAM de video (o RET e o codigo em 5Bxxh), para os dois CPLDs ja' estarem no modo
; sombra: sem isto o 1.o opcode podia vir da DRAM e da SRAM ao mesmo tempo.
LigaSombra0         ld bc,00f3h
                    out (c),a
                    ld b,0
LS1                 djnz LS1
                    ret
LTestaScld          equ $-TestaScld0
LLigaSombra         equ $-LigaSombra0
LigaSombraF         equ 0F000h
TestaCopia0         ld a,e              ; Z = a SRAM (pagina 26) tem o byte escrito em 4000h
                    ld (4000h),a
                    ld a,128+26
                    out (DIVCTRL),a
                    ld a,(2000h)
                    push af
                    xor a
                    out (DIVCTRL),a
                    pop af
                    cp e
                    ret
LCodigoEnRAM        equ $-CodigoEnRAM
                    assert LCodigoEnRAM <= 512     ; 5B00h-5CFFh (as variaveis do BASIC ja nao contam: arranca a ROM)

; ---------------------------------------------------------------------------
; -reset: sai do modo 128K. Corre em 5B00h: 7FFD = 0, desliga o modo ROM em
; RAM, F4 = 0 (FFF4), F3 = 0, FF = 0, apaga a pagina 0 do DivMMC (o esxDOS
; reinicia-se) e salta para 0: arranca a ROM do Timex.
FazReset            ld hl,MsgReset
                    call Print
                    di
                    ld hl,LigaSombra0   ; o OUT do F3 corre em F000h (fora da RAM de video, por causa
                    ld de,LigaSombraF   ; da sombra do Pentagon)
                    ld bc,LLigaSombra
                    ldir
                    ld hl,CodigoReset
                    ld de,CODIGO
                    ld bc,LCodigoReset
                    ldir
                    jp CODIGO
CodigoReset         di
                    ld sp,PILARAM
                    xor a               ; F3 = 0 primeiro, a correr em F000h (com a sombra ligada um
                    call LigaSombraF    ; OUT em 5B00h estragava o codigo)
                    ld bc,7ffdh         ; banco 0, ROM0 (ainda no modo 128K)
                    out (c),a
                    ld bc,0fff4h        ; F4 = 0: o Timex volta a ter a RAM interna
                    out (c),a
                    out (0ffh),a        ; ecra normal
                    ld bc,ZXUNOADDR     ; DDh = 0 (sem TC2068, sem copia, sem 1024K)
                    ld a,0DDh
                    out (c),a
                    inc b
                    xor a
                    out (c),a
                    ld a,128+0          ; apaga a pagina 0: o esxDOS reinicia-se
                    out (DIVCTRL),a
                    ld hl,8192
                    ld de,8193
                    ld (hl),l
                    ld bc,8191
                    ldir
                    xor a               ; CONMEM desligado
                    out (DIVCTRL),a
                    ; o modo ROM em RAM (DF bit 7) so' se desliga com RESET+NMI: no Timmy da Tang o
                    ; registo ZXUNO A2h = 52h fa'-lo sozinho; no clone espera-se pelo botao
                    ld bc,ZXUNOADDR
                    ld a,0A2h
                    out (c),a
                    inc b
                    ld a,52h
                    out (c),a
                    ld bc,0FC3Bh        ; 2026-10-20: com a DivTIESUS nova o A2h = 52h ja' fez o master
                    ld a,0DFh           ; reset dos registos: se o modo ROM em RAM se desligou, arranca
                    out (c),a           ; ja' o TC2048 (sem o botao); senao (CPLD antigo, ou a Tang,
                    inc b               ; que faz o RESET+NMI daqui a pouco) espera.
                    in a,(c)
                    rlca
                    jr c,CRpara
                    xor a
                    out (0E3h),a
                    jp 0
CRpara              ld a,2              ; borda a piscar: RESET com o NMI carregado
                    out (0feh),a
                    ld b,0
CRp1                djnz CRp1
                    xor a
                    out (0feh),a
CRp2                djnz CRp2
                    jr CRpara
LCodigoReset        equ $-CodigoReset

; ---------------------------------------------------------------------------
GetCmdLine          ld a,(hl)
                    inc hl
                    cp " "
                    jr z,GetCmdLine
                    cp "-"
                    jr z,Opcao
                    ld de,BufferParam
                    dec hl
CopiaNome           ld a,(hl)
                    or a
                    jr z,FimNome
                    cp ":"
                    jr z,FimNome
                    cp 13
                    jr z,FimNome
                    cp " "
                    jr z,FimNome
                    ldi
                    jr CopiaNome
FimNome             xor a
                    ld (de),a
                    ret
Opcao               call Valida         ; a palavra inteira tem de estar na tabela
                    jr z,OpcaoBoa
                    ld a,(ErroOp)       ; guarda so' a primeira errada
                    or a
                    jr nz,SaltaPalavra
                    inc a
                    ld (ErroOp),a
                    ld (ErroPtr),hl
SaltaPalavra        ld a,(hl)           ; salta a palavra errada
                    cp " "+1
                    jp c,GetCmdLine
                    cp ":"
                    jp z,GetCmdLine
                    inc hl
                    jr SaltaPalavra
OpcaoBoa            ld a,(hl)
                    inc hl
                    cp "5"              ; -50: tempos do 48K (ja' e' o normal)
                    jp z,Opcao50
                    cp "4"              ; -49 = -ts
                    jp z,Opcao49
                    or 20h
                    cp "f"              ; -float: ja' e' o normal
                    jr z,SaltaLetras
                    cp "c"              ; -cc (ou -ct): contencao tambem nos bancos 1 e 3
                    jr z,OpcaoCT
                    cp "s"              ; -sc: sem contencao nos bancos 1 e 3 (ja' e' o normal)
                    jr z,OpcaoSC
                    cp "m"              ; -menu
                    jr z,OpcaoMenu
                    cp "r"              ; -reset
                    jr z,OpcaoReset
                    cp "t"              ; -ts ou -timex
                    jr z,OpcaoT
                    cp "b"              ; -bus: sem barramento flutuante (= -timex)
                    jr z,OpcaoBus
                    cp "p"              ; -penta: tempos do Pentagon (F3 bit 7)
                    jr z,OpcaoPenta
                    cp "i"              ; -io: contencao de E/S so' nas portas do SCLD (F3 bit 4)
                    jr z,OpcaoIO
                    cp "a"              ; -ayext: AY de fora (F3 bit 0 a 0: o SCLD larga o FFFD/BFFD)
                    jr z,OpcaoAY
                    cp "n"
                    jr nz,SaltaLetras
                    xor a
                    ld (DivMMCOption),a
                    jr SaltaLetras
OpcaoT              ld a,(hl)
                    or 20h
                    cp "s"
                    jr z,Opcao49        ; -ts: tempos do 128K
OpcaoBus            ld a,(OpcaoF3)      ; -timex / -bus: porta FF = registo do Timex
                    and 0dfh
                    ld (OpcaoF3),a
                    jr SaltaLetras
OpcaoPenta          ld a,(OpcaoF3)
                    or 80h
                    ld (OpcaoF3),a
                    jr SaltaLetras
OpcaoIO             ld a,(OpcaoF3)
                    or 10h
                    ld (OpcaoF3),a
                    jr SaltaLetras
OpcaoAY             ld a,(OpcaoF3)
                    and 0FEh
                    ld (OpcaoF3),a
                    jp SaltaLetras
OpcaoMenu           xor a               ; -menu = -n: sem traps, a ROM0 arranca no menu
                    ld (DivMMCOption),a
                    jr SaltaLetras
OpcaoReset          ld a,1
                    ld (Reset),a
                    jr SaltaLetras
OpcaoCT             ld a,(OpcaoF3)
                    or 8                ; bit 3: contencao tambem nos bancos 1 e 3
                    ld (OpcaoF3),a
                    jr SaltaLetras
OpcaoSC             ld a,(OpcaoF3)
                    and 0f7h            ; bit 3 a 0
                    ld (OpcaoF3),a
SaltaLetras         ld a,(hl)           ; salta o resto da opcao
                    or 20h
                    cp "a"
                    jp c,GetCmdLine
                    cp "z"+1
                    jp nc,GetCmdLine
                    inc hl
                    jr SaltaLetras
Opcao49             ld a,(OpcaoF3)
                    or 4                ; bit 2 a 1: tempos do 128K
                    ld (OpcaoF3),a
                    jr SaltaResto
Opcao50             ld a,(OpcaoF3)
                    and 0fbh            ; bit 2 a 0: tempos do 48K
                    ld (OpcaoF3),a
SaltaResto          ld a,(hl)           ; salta o resto ("9", "0" ou "s")
                    cp " "+1
                    jp c,GetCmdLine
                    cp ":"
                    jp z,GetCmdLine
                    inc hl
                    jr SaltaResto

; HL = palavra depois do "-": Z se esta' na tabela (nao mexe em HL)
Valida              ld de,TabOpcoes
VLoop               ld a,(de)
                    or a
                    jr z,VNao
                    push hl
VCmp                ld a,(de)
                    or a
                    jr z,VFimP
                    ld c,a
                    ld a,(hl)
                    or 20h
                    cp c
                    jr nz,VDif
                    inc hl
                    inc de
                    jr VCmp
VFimP               ld a,(hl)           ; a palavra tem de acabar aqui
                    cp " "+1
                    jr c,VSim
                    cp ":"
                    jr z,VSim
VDif                pop hl
VSalta              ld a,(de)
                    inc de
                    or a
                    jr nz,VSalta
                    jr VLoop
VSim                pop hl
                    xor a
                    ret
VNao                inc a               ; A=1: NZ
                    ret
TabOpcoes           db "50",0,"49",0,"float",0,"cc",0,"ct",0,"sc",0,"menu",0,"n",0
                    db "reset",0,"ts",0,"timex",0,"bus",0,"penta",0,"io",0,"ayext",0,0
ErroOp              db 0
ErroPtr             dw 0
MsgOpcao            db "GO128: -",0
MsgOpcao2           db " not available",13
                    db "Options: -penta -bus -io -ayext",13
                    db "-cc -ts -timex -menu -reset",13,0

NomeDefeito         db "/bin/128.rom",0
LNomeDefeito        equ $-NomeDefeito
MsgTamanho          db "GO128: the ROM must have 32768",13
                    db "(ROM0+ROM1) or 16384 bytes.",13,0
MsgLeitura          db 13,"GO128: read error. Reset.",0
MsgReset            db "GO128: RESET com NMI",13,0

FHandle             db 0
Reset               db 0
DivMMCOption        db 64
                    IFDEF GO256
OpcaoF3             db 34+80h+8         ; .go256 = Pentagon 256 (F3 bit 7 + bit 3: 7FFD bit 6); bit 0 a 0: AY de fora
                    ELSE
OpcaoF3             db 34               ; porto F3: bit0 AY 128 (a 0: o AY e' o de fora, do lado do CPU), bit1 preto unico,
                                        ; bit2 tempos do 128K (-50 tira), bit3 contencao 1/3 (-ct),
                                        ; bit5 barramento flutuante na porta FF (-timex tira)
                    ENDIF
BackupSP            dw 0
Tamanho             dw 0
StatBuf             ds 11
BufferParam         db 0
