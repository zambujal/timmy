; SOMNAV.BIN: o som de arranque, tocado com o navegador ja' no ecra.
;
; O BROWSE.BIN, no 1.o NMI depois de ligar, carrega este ficheiro em BC00h (BUF) e
; chama-o (antes de ler o indice e antes de passar ao NAVHR.BIN). O carregador:
;   - copia o leitor para FE00h-FFFFh (o NAV nao usa: IM 2 em FC00h-FDFFh);
;   - le o /SYS/NAV.SOM: o cabecalho e ate' 16K de dados para as paginas 13 e 14 do
;     DivMMC (as de rascunho dos plugins), passando por C000h.
; O NAV (BROWSE e NAVHR) chama FE00h logo a seguir a desenhar a 1.a pasta: o leitor toca
; o som todo com as interrupcoes desligadas (tudo parado ate' acabar) e volta. Em cada
; NMI o BROWSE.BIN poe um RET em FE00h antes de tudo: sem som, a chamada nao faz nada.
;
; Tempo: periodo 170 + 16*N1 T (N1 do cabecalho), igual ao do dot command e do plugin.
; Codigo em FE00h e dados em 2000h-3FFFh: sem contencao.

                    include "esxdos.inc"

BUF                 equ 0BC00h          ; o BUF do NAV (BROWSE.BIN reestruturado)
STAGE               equ 0C000h
PAG0                equ 80h+13
MAXDADOS            equ 4000h

                    org BUF

Carrega             ld hl,ResSrc
                    ld de,RES
                    ld bc,ResLen
                    ldir
                    ld a,'*'
                    ld hl,NomeSom
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (FH),a
                    ld hl,STAGE
                    ld bc,56
                    rst 08h
                    db F_READ
                    jp c,Fecha
                    ld hl,(STAGE)       ; "SOM1"
                    ld de,"OS"
                    or a
                    sbc hl,de
                    jp nz,Fecha
                    ld hl,(STAGE+2)
                    ld de,"1M"
                    or a
                    sbc hl,de
                    jp nz,Fecha
                    ld a,(STAGE+4)      ; N1 >= 8 (N2 = N1 - 7 >= 1)
                    cp 8
                    jp c,Fecha
                    sub 2
                    ld (PatchN1+1),a
                    sub 5
                    ld (PatchN2+1),a
                    ld hl,STAGE+8       ; T[n*4 + canal]
                    ld de,Tab
                    ld b,16
CTab                push hl
                    ld a,(hl)
                    ld (de),a
                    inc e
                    ld a,l
                    add a,16
                    ld l,a
                    ld a,(hl)
                    ld (de),a
                    inc e
                    ld a,l
                    add a,16
                    ld l,a
                    ld a,(hl)
                    ld (de),a
                    inc e
                    inc e
                    pop hl
                    inc hl
                    djnz CTab
                    ld hl,(STAGE+6)     ; ate' 16K (o resto do ficheiro fica de fora)
                    ld de,MAXDADOS
                    or a
                    sbc hl,de
                    add hl,de
                    jr c,CTam
                    ex de,hl
CTam                ld a,h
                    or l
                    jp z,Fecha
                    ld (Resta),hl
                    ld a,PAG0
                    ld (CPag),a
CBloco              ld a,(FH)
                    ld hl,STAGE
                    ld bc,2000h
                    rst 08h
                    db F_READ
                    jp c,Fecha
                    ld a,b
                    or c
                    jr z,CFim
                    di
                    ld a,(CPag)
                    out (0E3h),a
                    ld hl,STAGE
                    ld de,2000h
                    ldir
                    xor a
                    out (0E3h),a
                    ld a,(CPag)
                    inc a
                    ld (CPag),a
                    cp PAG0+2
                    jr nz,CBloco
CFim                ld a,1
                    ld (Ativo),a
Fecha               ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    ret

NomeSom             db "/SYS/NAV.SOM",0
FH                  db 0
CPag                db 0

; ---------------------------------------------------------------------------
ResSrc
                    disp 0FE00h
RES
Entrada             ld a,(Ativo)        ; (o BROWSE poe um RET em FE00h a cada NMI)
                    or a
                    ret z
                    xor a
                    ld (Ativo),a        ; so' uma vez
                    di
                    push iy
                    ld a,PAG0
                    out (0E3h),a
                    ld de,2000h
                    ld iy,(Resta)
                    ld bc,0FFFDh        ; registo 7 = 3Fh: sem tom nem ruido
                    ld a,7
                    out (c),a
                    ld b,0BFh
                    ld a,3Fh
                    out (c),a
                    ld c,0FDh
                    ld h,high Tab
; um byte = duas amostras; os dois periodos = 170 + 16*N1 (aqui N1' = N1-2, N2' = N1-7)
Byte                ld a,(de)           ; 7
                    and 0Fh             ; 7
                    add a,a             ; 4
                    add a,a             ; 4
                    ld l,a              ; 4
                    ld b,0FFh
                    ld a,8
                    out (c),a
                    ld b,0BFh
                    ld a,(hl)
                    out (c),a
                    inc l
                    ld b,0FFh
                    ld a,9
                    out (c),a
                    ld b,0BFh
                    ld a,(hl)
                    out (c),a
                    inc l
                    ld b,0FFh
                    ld a,10
                    out (c),a
                    ld b,0BFh
                    ld a,(hl)
                    out (c),a
                    inc l
PatchN1             ld a,0
D1                  dec a
                    jr nz,D1
                    inc hl              ; 6: acerto (o L nao passa de 3Fh, o H fica)
                    ld a,(de)           ; 7
                    and 0F0h            ; 7
                    rrca                ; 4
                    rrca                ; 4
                    ld l,a              ; 4
                    ld b,0FFh
                    ld a,8
                    out (c),a
                    ld b,0BFh
                    ld a,(hl)
                    out (c),a
                    inc l
                    ld b,0FFh
                    ld a,9
                    out (c),a
                    ld b,0BFh
                    ld a,(hl)
                    out (c),a
                    inc l
                    ld b,0FFh
                    ld a,10
                    out (c),a
                    ld b,0BFh
                    ld a,(hl)
                    out (c),a
                    inc l
                    inc de              ; 6
                    dec iy              ; 10
                    ld a,iyh            ; 8
                    or iyl              ; 8
                    jp z,Acabou         ; 10
                    ld a,d              ; 4
                    cp 40h              ; 7
                    jp z,MudaPag        ; 10
VoltaPag            ld a,(0)            ; 13: acerto
PatchN2             ld a,0              ; 7
D2                  dec a
                    jr nz,D2
                    jp Byte             ; 10

MudaPag             ld de,2000h         ; uma vez, aos 8K: essa amostra sai um pouco tarde
                    ld a,PAG0+1
                    out (0E3h),a
                    jp VoltaPag

Acabou              ld b,0FFh           ; volumes a 0
                    ld a,8
                    out (c),a
                    ld b,0BFh
                    xor a
                    out (c),a
                    ld b,0FFh
                    ld a,9
                    out (c),a
                    ld b,0BFh
                    xor a
                    out (c),a
                    ld b,0FFh
                    ld a,10
                    out (c),a
                    ld b,0BFh
                    xor a
                    out (c),a
                    out (0E3h),a        ; A = 0: tira a pagina
                    pop iy
                    ei                  ; o NAV chama com as interrupcoes ligadas (IM 2)
                    ret

Ativo               db 0
Resta               dw 0
                    align 256
Tab                 ds 64
RESFIM
                    assert RESFIM <= 10000h
                    ent
ResLen              equ RESFIM-RES
FimCarrega
                    assert FimCarrega <= STAGE
