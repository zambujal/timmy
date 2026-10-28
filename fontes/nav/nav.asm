; NAV: navegador para o NMI do esxDOS (no lugar do /BIN/BROWSE.BIN do Bob Fossil).
; O NMI.SYS carrega-o em 84D0h e chama-o; ao voltar, repoe a RAM e o programa.
;
; Coluna das letras (DIR, 0-9, A-Z, #) e coluna dos ficheiros, a partir dos
; indices _NAV/*.IDX que o gera_nav.py escreve em cada pasta (nomes grandes,
; nome 8.3 e maquina). Sem indice, mostra a pasta tal como o esxDOS a le.
; Os ficheiros correm com os plugins do Bob Fossil (/BIN/BPLUGINS/<EXT>).
;
; Teclas: 7/6 cima/baixo (SYM+7/6 pagina), 5/8 letras/ficheiros,
;         ENTER corre ou entra na pasta, ESPACO volta (pasta de cima),
;         A-Z salta para a letra, 0 todas, 1 48K, 2 48K+AY, 3 128K, 4 Timex,
;         9 outras, EDIT (CS+1) NMI original, BREAK (CS+ESPACO) sai.
;
; Memoria: codigo 84D0h-9FFBh (guardado na pagina 12 do DivMMC enquanto o
; plugin corre), trampolim A000h-A3DFh, codigo A3E0h-BBE1h (pagina 40),
; registos BC00h-F3FFh, leitura F400h-F7FFh, tabela do IM 2 FC00h-FD00h.

                    include "esxdos.inc"

; HIRES = 1: o mesmo navegador no modo de alta resolucao do Timex (512x192, 64 colunas,
; 2 cores). Monta-se com  sjasmplus -DHIRES=1  e fica /BIN/NAVHR.BIN. O normal (BROWSE.BIN)
; carrega-o sozinho quando a FFh e' o registo do Timex (no Timmy tambem nos modos ZX).
                    IFNDEF HIRES
                    DEFINE HIRES 0
                    ENDIF

TRAMP               equ 0A000h
CODE2               equ 0A3E0h              ; 2.a parte do codigo: A3E0h-BBE1h (o NMI.SYS apaga de BBE2h)
CODE2MAX            equ 0BBE2h
PAG2                equ 40                  ; pagina do DivMMC com a copia de A3E0h-BBE1h (plugins)
BUF                 equ 0BC00h
MAXREC              equ 224                 ; 224 x 64 = 3800h -> F400h
TMP                 equ 0F400h              ; 1K = 16 registos
TABELA              equ 0FC00h              ; 257 bytes a FDh -> vector FDFDh
VECTOR              equ 0FDFDh
NLIN                equ 21                  ; linhas 2..22 (hi-res v15: a barra das pastas e' a linha 1)
                    IF HIRES
LIN0                equ 2                   ; primeira linha da lista (v15: era 1)
LPAST               equ 1                   ; linha da barra das pastas (v15: era 22, em baixo)
LCEL                equ 4                   ; celulas (2 colunas) da coluna das letras
HIRESFF             equ 36h                 ; FFh: modo 110 (512x192), cor 110
                    ELSE
LIN0                equ 2
LCEL                equ 8
                    ENDIF
NMI_VAR             equ 0BBE5h              ; 1 = normal; 2 = o NMI.SYS chama o nmi.org
NMI_7FFD            equ 0309Ah              ; ultimo 7FFD guardado pelo NMI.SYS

; atributos
                    IF HIRES
; no hi-res so' ha' normal e invertido: invertido = bits 4-5 diferentes de 0
A_TOPO              equ 10h
A_BARRA             equ 10h
A_BARRASEL          equ 00h
A_LETRA             equ 10h
A_LETRASEL          equ 00h
A_LETRASEL2         equ 00h
A_FICH              equ 00h
A_PASTA             equ 00h
A_SEL               equ 10h
A_ESTADO            equ 10h
                    ELSE
A_TOPO              equ 4Fh
A_BARRA             equ 07h
A_BARRASEL          equ 30h
A_LETRA             equ 0Eh
A_LETRASEL          equ 30h
A_LETRASEL2         equ 4Eh
A_FICH              equ 0Fh
A_PASTA             equ 0Eh
A_SEL               equ 28h
A_ESTADO            equ 38h
                    ENDIF
A_EMBLEMA           equ 47h

                    org 84D0h

Inicio              di
                    ld (SPguardado),sp
                    ld sp,8000h         ; pilha propria abaixo de 8000h, como o browser do Bob Fossil:
                                        ; a do NMI.SYS fica na RAM do DivMMC (2000h-3FFFh), que o
                                        ; esxDOS usa nas rst 08h e que o trampolim troca pela pagina 12
                    ld a,i
                    ld (Iguardado),a
                    call VeTimex        ; se a porta FFh for o registo do Timex e o ecra
                                        ; estiver noutro modo, passa ao ecra normal
                    IF !HIRES
                    call EspOrdem       ; v25: o ESP escolheu um ficheiro: corre-o ja', sem o navegador
                    ELSE
                    call EspHerda       ; v25d: a ordem de maquina que o BROWSE.BIN recebeu do ESP
                    ENDIF
                    IF !HIRES
                    call Desfaz         ; v21: o ecra do jogo desfaz-se aos quadrados (0,3 s)
                    call SomArranque    ; RET em FE00h; 1.o NMI depois de ligar: /BIN/SOMNAV.BIN
                    call VeHR           ; Timex: passa ao /BIN/NAVHR.BIN, se existir (nao volta)
                    ENDIF
                    call LeFiltro       ; a ultima maquina escolhida (guardada na pagina 12)
                    call AcertaMaquina  ; confere com o modo verdadeiro; depois de ligar: /SYS/NAV.CFG
                    IF HIRES
                    call EntraHires     ; F3 sem o bit 5: a FF aceita o modo hi-res
                    call LePastas       ; /_NAV/PASTAS.IDX: as pastas da barra de baixo
                    xor a               ; MsgEstado fica fora do NAVHR.BIN: comeca vazia
                    ld (MsgEstado),a
                    ENDIF
                    call InstalaIM2
                    call EntraPasta
                    ld a,(EspMaq)       ; v25f: mudanca de maquina pedida pelo ESP: sem som nem musica
                    ld b,a
                    ld a,(EspSai)
                    or b
                    ld b,a
                    ld a,(EspFich)
                    or b
                    jr nz,SemSom
                    call 0FE00h         ; som de arranque (SOMNAV), com a pasta ja' no ecra
                    call MusArranca     ; v20: a musica de fundo (PT3), depois do som de arranque
SemSom
                    ld a,(SemPergunta)  ; acabou de ligar e a ultima maquina e' de outra classe
                    or a
                    call nz,Reinicia
                    IF !HIRES
                    xor a               ; (sem o NAVHR: a copia para ele ja' nao serve)
                    ld (5BFEh),a
                    ENDIF
                    ld a,(EspSai)       ; v25d: mudanca de maquina do ESP acabada: para o BASIC
                    or a
                    jp nz,Sai
                    ld a,(EspFich)      ; v25i: ficheiro do ESP: como o ENTER, com o NAV ja' arrancado
                    or a
                    jr z,SemFich
                    IF HIRES
                    call EspRepete
                    ENDIF
                    call SaiNav
                    call EspCorre
                    jp Sai              ; (so' volta se o caminho nao prestar)
SemFich
                    ld a,(EspMaq)       ; v25d: maquina escolhida no ESP: como o ENTER no menu
                    or a
                    jr z,Ciclo
                    dec a
                    ld (MenuSel),a
                    ld a,1
                    ld (SemPergunta),a
                    call VeTang
                    call MNesc
                    jp Sai              ; v25e: feita a mudanca (ou o GS): para o BASIC, como o ESP pede
Ciclo               call LeTecla
                    or a
                    IF HIRES
                    jr nz,CiTecla
                    call Pisca
                    jr Ciclo
CiTecla             push af
                    call PiscaFim       ; a seleccao aparece logo, sem esperar pela fase
                    call GotaAntes      ; v16: a zona antes da tecla
                    pop af
                    call TrataE
                    call GotaDepois     ; v16: se a marca mudou de sitio, faz a gota (e o blop)
                    jr Ciclo
                    ELSE
                    jr z,Ciclo
                    call TrataE
                    jr Ciclo
                    ENDIF
; v17: um ENTER (ou o fogo do joystick) so' vale uma vez: o seguinte so' depois de largar,
; senao, ao entrar numa pasta com o fogo ainda carregado, abria logo o primeiro da lista
TrataE              cp 13
                    push af
                    call Trata
                    pop af
                    ret nz
                    ld a,1
                    ld (Larga),a
                    ret

SaiNMI              ld a,2
                    jr SaiVar
Sai                 ld a,1              ; BBE5h fica dentro de BUF: repor sempre
SaiVar              push af
                    call MusCala        ; v20: o AY calado ao sair
                    call GuardaFiltro
                    call SaiNav         ; o esxDOS guarda a pasta actual: nao a deixar em _NAV
                    pop af
                    ld (NMI_VAR),a
                    di
                    IF HIRES
                    call SaiEcra        ; o F3 da maquina e o modo de ecra antigo
                    ELSE
                    ld a,(MudouFF)      ; repoe o modo de ecra do Timex, se o mudou
                    or a
                    jr z,SaiFF
                    ld a,(PortaFF)
                    out (0FFh),a
                    ENDIF
SaiFF               im 1
                    ld a,(Iguardado)
                    ld i,a
                    ld sp,(SPguardado)
                    ret

InstalaIM2          di
                    ld hl,TABELA
                    ld de,TABELA+1
                    ld bc,256
                    ld (hl),0FDh
                    ldir
                    ld a,0C3h
                    ld (VECTOR),a
                    ld hl,Interrupcao
                    ld (VECTOR+1),hl
                    ld a,TABELA/256
                    ld i,a
                    im 2
                    ei
                    ret

Interrupcao         push af
                    ld a,(Frames)
                    inc a
                    ld (Frames),a
                    ld a,(MusOk)        ; v22: a musica toca aqui, 50 vezes por segundo, mesmo
                    or a                ; enquanto o navegador desenha
                    jr z,INsai
                    ld a,(MusLiga)
                    or a
                    jr z,INsai
                    ld a,(MusPara)
                    or a
                    jr nz,INsai
                    push hl
                    ld hl,4             ; o endereco de volta: dentro do esxDOS ou do ROM (abaixo de
                    add hl,sp           ; 4000h) a pagina 2000h esta' a ser usada: este frame nao
                    inc hl
                    ld a,(hl)
                    cp 40h
                    jr c,INsaiH
                    push bc
                    push de
                    push ix
                    push iy
                    ex af,af'
                    push af
                    call MusPag
                    call 2003h
                    call MusTira
                    pop af
                    ex af,af'
                    pop iy
                    pop ix
                    pop de
                    pop bc
INsaiH              pop hl
INsai               pop af
                    ei
                    reti

; ---------------------------------------------------------------------------
; Teclado

; A = tecla, com repeticao (0 = nada de novo)
LeTecla             halt
                    xor a               ; v22: no ciclo principal a musica pode tocar (interrupcao)
                    ld (MusPara),a
                    call Varre
                    ld hl,Larga         ; v17: depois de um ENTER/fogo, nada ate' largar tudo
                    inc (hl)
                    dec (hl)
                    jr z,LTvai
                    or a
                    jr z,LTsolto
                    xor a               ; ainda carregado (o joystick fica com o valor uns frames)
                    ret
LTsolto             ld (hl),a           ; largou: a partir de agora volta ao normal
LTvai               ld hl,UltTecla
                    cp (hl)
                    jr z,LTigual
                    ld (hl),a
                    ld a,16
                    ld (Repete),a
                    IF HIRES
                    xor a
                    ld (Repetiu),a
                    ENDIF
                    ld a,(hl)
                    ret
LTigual             or a
                    ret z
                    ld hl,Repete
                    dec (hl)
                    jr z,LTrep
                    xor a
                    ret
LTrep               ld (hl),2
                    IF HIRES
                    ld a,1
                    ld (Repetiu),a
                    ENDIF
                    ld a,(UltTecla)
                    ret

; A = codigo da primeira tecla carregada (sem contar CS e SYM), 0 = nenhuma.
; CS+1 = 1 (EDIT), CS+ESPACO = 3 (BREAK), SYM+7/6/5/8 = 'u','d','f','l'
Varre               ld hl,TabTeclas
                    ld c,0FEh
                    ld b,0FEh
VLinha              in a,(c)
                    cpl
                    and 1Fh
                    ld e,a
                    ld d,5
VBit                srl e
                    jr nc,VProx
                    ld a,(hl)
                    or a
                    jr nz,VAchou
VProx               inc hl
                    dec d
                    jr nz,VBit
                    rlc b
                    jr c,VLinha
; sem tecla: joystick Kempston (porta 1Fh, 1 = carregado: 0 dir, 1 esq, 2 baixo, 3 cima, 4 fogo).
; Sem interface a porta flutua (FFh na borda, logo a seguir ao HALT): bits 5-7 a 1 = ignora.
; Num TC2068 o barramento fica com o ultimo byte lido (o 1Fh da propria instrucao): direcoes
; opostas ao mesmo tempo (esq+dir ou cima+baixo) nao existem num Kempston = ignora.
FILTRA_LISTA        equ 0               ; 1 = a lista so' mostra os ficheiros da maquina escolhida
                    IFNDEF KEMPSTON
KEMPSTON            equ 1               ; 1 = le' o joystick Kempston (-DKEMPSTON=0 sem)
                    ENDIF
; Contra as teclas fantasma: tres leituras seguidas iguais, e o mesmo valor em 3 frames
; seguidos antes de valer (o barramento solto muda de leitura para leitura e de frame para frame).
                    IF KEMPSTON
Joystick            in a,(1Fh)
                    ld e,a
                    in a,(1Fh)
                    cp e
                    jr nz,JZero
                    in a,(1Fh)
                    cp e
                    jr nz,JZero
                    and 0E0h
                    jr nz,JZero
                    ld a,e
                    rrca
                    and e
                    and 5
                    jr nz,JZero
                    ld a,e
                    and 1Fh
                    jr z,JZero
                    ld hl,JoyAnt        ; igual ao frame anterior?
                    cp (hl)
                    ld (hl),a
                    jr nz,JConta0
                    ld hl,JoyConta
                    ld a,(hl)
                    cp 2
                    jr nc,JVale
                    inc (hl)
                    jr JNada
JConta0             xor a
                    ld (JoyConta),a
                    jr JNada
JZero               xor a
                    ld (JoyAnt),a
                    ld (JoyConta),a
                    jr JNada
JVale               ld a,13
                    bit 4,e
                    ret nz
                    ld a,'7'
                    bit 3,e
                    ret nz
                    ld a,'6'
                    bit 2,e
                    ret nz
                    ld a,'5'
                    bit 1,e
                    ret nz
                    ld a,'8'
                    bit 0,e
                    ret nz
                    ENDIF
JNada               xor a
                    ret
VAchou              ld e,a              ; e = tecla
                    ld a,0FEh           ; CS?
                    in a,(0FEh)
                    rra
                    jr c,VSemCS
                    ld a,e
                    cp '1'
                    jr nz,VCS2
                    ld a,1
                    ret
VCS2                cp ' '
                    jr nz,VSemCS2
                    ld a,3
                    ret
VSemCS              ld a,7Fh            ; SYM?
                    in a,(0FEh)
                    and 2
                    ld a,e
                    ret nz
                    cp '7'
                    jr nz,VS6
                    ld a,'u'
                    ret
VS6                 cp '6'
                    jr nz,VS5
                    ld a,'d'
                    ret
VS5                 cp '5'
                    jr nz,VS8
                    ld a,'f'
                    ret
VS8                 cp '8'
                    ld a,e
                    ret nz
                    ld a,'l'
                    ret
VSemCS2             ld a,e
                    ret

TabTeclas           db 0,"ZXCV"
                    db "ASDFG"
                    db "QWERT"
                    db "12345"
                    db "09876"
                    db "POIUY"
                    db 13,"LKJH"
                    db " ",0,"MNB"

; ---------------------------------------------------------------------------
; Accoes

Trata               ld hl,MsgEstado     ; qualquer tecla apaga a mensagem
                    ld b,a
                    ld a,(hl)
                    or a
                    jr z,TrSemMsg
                    ld (hl),0
                    push bc
                    call DesenhaEstado
                    pop bc
TrSemMsg            ld a,b
                    cp 3
                    jp z,Sai
                    cp 1
                    jp z,SaiNMI
                    cp '7'
                    jp z,Cima
                    cp '6'
                    jp z,Baixo
                    cp 'u'
                    jp z,PagCima
                    cp 'd'
                    jp z,PagBaixo
                    cp 'f'
                    jp z,Primeiro
                    cp 'l'
                    jp z,Ultimo
                    cp '5'
                    jp z,Esquerda
                    cp '8'
                    jp z,Direita
                    cp 13
                    jp z,Enter
                    cp ' '
                    jp z,Volta
                    cp '0'
                    jp z,MusTecla       ; v20: 0 = num .PT3: musica de fundo; noutro: liga/desliga
                    cp '1'
                    ret c
                    cp '5'
                    jr c,TrFiltro
                    IF HIRES
                    cp '9'
                    jp z,ParaPastas
                    ENDIF
                    cp 'A'
                    ret c
                    cp 'Z'+1
                    jp c,SaltaLetra
                    ret
TrFiltro            sub '1'             ; 1-4: abre o menu das maquinas ja' nessa (v14b: so'
                    ld (MenuSel),a      ; muda com ENTER; ESPACO volta sem mudar)
                    IF HIRES
                    call FocoBase
                    ELSE
                    xor a
                    ld (Foco),a
                    ENDIF
                    jp MNdesenha
AplicaFiltro        ld (Filtro),a
                    IF !FILTRA_LISTA
                    jp DesenhaFiltro    ; a lista e' sempre a mesma: so' a barra da maquina
                    ELSE
                    ld a,(Modo)         ; pasta sem indice: a lista e' a mesma
                    or a
                    jp nz,DesenhaTudo
                    ld a,(GSel)         ; tenta ficar no mesmo grupo
                    call GrupoVis
                    ld (GrupoAnt),a
                    call ConstroiVis
                    ld a,(GrupoAnt)
                    call ProcuraGrupo
                    jr nc,TrFok
                    xor a
TrFok               ld (GSel),a
                    call AjustaGTopo
                    call CarregaGrupo
                    jp DesenhaTudo
                    ENDIF

; --- coluna das letras
Esquerda            ld a,(Foco)
                    cp 2
                    jp z,FiltroAnt
                    IF HIRES
                    cp 3
                    jp z,PastaAnt
                    ENDIF
                    or a                ; nas letras: esquerda sobe uma pasta (joystick)
                    jr z,ESsobe
                    ld hl,(Sel)         ; nos ficheiros: sobe uma pagina; ja' no primeiro:
                    ld a,h              ; volta as letras (ou sobe, sem coluna das letras)
                    or l
                    jp nz,PagCima
                    IF HIRES
                    ld a,(Ocultas)
                    or a
                    jr nz,ESsobe
                    ENDIF
                    xor a
                    ld (Foco),a
                    jp DesenhaPaineis
ESsobe              ld a,(Cwd+1)        ; na raiz nao faz nada (para sair: ESPACO ou BREAK)
                    or a
                    ret z
                    jp VOpai

Direita             ld a,(Foco)
                    cp 2
                    jp z,FiltroSeg
                    IF HIRES
                    cp 3
                    jp z,PastaSeg
                    ENDIF
                    or a
                    jr nz,DIpasta
                    ld hl,(Total)
                    ld a,h
                    or l
                    ret z
                    ld a,1
                    ld (Foco),a
                    jp DesenhaPaineis
DIpasta             jp PagBaixo         ; nos ficheiros: direita desce uma pagina (joystick)

Cima                ld a,(Foco)
                    cp 2
                    ret z
                    IF HIRES
                    cp 3
                    jp z,PastasCima     ; v15: das pastas (em cima) sobe para a maquina
                    ENDIF
                    or a
                    jr nz,FCima
                    ld a,(GSel)
                    or a
                    IF HIRES
                    jp z,AcimaLista     ; acima da primeira letra: as pastas (ou a maquina)
                    ELSE
                    jp z,ParaFiltro     ; acima da primeira letra: a barra do filtro
                    ENDIF
                    dec a
MudaGrupo           ld (GSel),a
                    call AjustaGTopo
                    call CarregaGrupo
                    jp DesenhaPaineis

Baixo               ld a,(Foco)
                    cp 2
                    IF HIRES
                    jp z,FiltroBaixo    ; v15: da maquina desce para as pastas
                    cp 3
                    jp z,SaiPastas      ; das pastas desce para a lista
                    ELSE
                    jp z,SaiFiltro
                    ENDIF
                    or a
                    jr nz,FBaixo
                    ld a,(NVis)
                    ld b,a
                    ld a,(GSel)
                    inc a
                    cp b
                    ret nc              ; v15: abaixo da ultima letra nao ha' nada
                    jr MudaGrupo

; --- coluna dos ficheiros
FCima               ld hl,(Sel)
                    ld a,h
                    or l
                    IF HIRES
                    jr z,FCtopo
                    ELSE
                    ret z
                    ENDIF
                    dec hl
NovoSel             ld de,(Sel)         ; so' redesenha o que mudou
                    ld (SelAnt),de
                    ld de,(Topo)
                    ld (TopoAnt),de
                    ld (Sel),hl
                    call AjustaTopo
                    ld hl,(Topo)
                    ld de,(TopoAnt)
                    or a
                    sbc hl,de
                    jr nz,NSrola
                    ld hl,(SelAnt)      ; mesma pagina: linha antiga e linha nova
                    call DesenhaLinhaN
                    ld hl,(Sel)
                    call DesenhaLinhaN
                    jr NSfim
NSrola              call DesenhaFicheiros
NSfim               call DesenhaEmblema
                    jp DesenhaEstado
DesenhaLinhaN       ld de,(Topo)        ; HL = numero absoluto (esta' no ecra)
                    or a
                    sbc hl,de
                    ld c,l
                    jp DFILinha

FBaixo              ld hl,(Sel)
                    inc hl
                    ld de,(Total)
                    or a
                    sbc hl,de
                    IF HIRES
                    jr nc,FBfim
                    ELSE
                    ret nc
                    ENDIF
                    add hl,de
                    jr NovoSel
                    IF HIRES
FCtopo              ld a,(Ocultas)      ; sem letras: acima do primeiro, as pastas (ou a maquina)
                    or a
                    ret z
                    jp AcimaLista
FBfim               ret                 ; v15: abaixo do ultimo nao ha' nada
                    ENDIF

PagCima             ld a,(Foco)
                    cp 1
                    ret nz
                    ld hl,(Sel)
                    ld de,NLIN
                    or a
                    sbc hl,de
                    jr nc,NovoSel
                    ld hl,0
                    jr NovoSel

PagBaixo            ld a,(Foco)
                    cp 1
                    ret nz
                    ld hl,(Sel)
                    ld de,NLIN
                    add hl,de
                    ld de,(Total)
                    or a
                    sbc hl,de
                    jr c,PBok
                    ld hl,(Total)
                    dec hl
                    jp NovoSel
PBok                add hl,de
                    jp NovoSel

Primeiro            ld a,(Foco)
                    cp 1
                    ret nz
                    ld hl,0
                    jp NovoSel

Ultimo              ld a,(Foco)
                    cp 1
                    ret nz
                    ld hl,(Total)
                    dec hl
                    jp NovoSel

; salta para a letra A (em A)
SaltaLetra          sub 'A'-2
                    IF HIRES
                    ld b,a
                    ld a,(Ocultas)
                    or a
                    ret nz
                    ld a,b
                    ENDIF
                    call ProcuraGrupo
                    ret c
                    ld (GSel),a
                    xor a
                    ld (Foco),a
                    call AjustaGTopo
                    call CarregaGrupo
                    jp DesenhaPaineis

Enter               ld a,(Foco)
                    cp 2
                    jp z,Menu
                    IF HIRES
                    cp 3
                    jp z,EntraAtalho
                    ENDIF
                    or a
                    jp z,Direita
                    call RegSel
                    ret c
                    inc hl
                    ld a,(hl)           ; pasta?
                    inc hl
                    inc hl
                    inc hl              ; hl = nome 8.3
                    or a
                    jp z,Corre
                    push hl
                    call SaiNav
                    pop hl
                    ld a,'*'            ; A = unidade (sem isto o esxDOS recusa)
                    rst 08h
                    db F_CHDIR
                    jp c,ErroPasta
                    jp EntraPasta

Volta               ld a,(Foco)
                    cp 2
                    jp z,SaiFiltro
                    IF HIRES
                    cp 3
                    jp z,SaiPastas
                    or a
                    jr z,VOsobe
                    ld a,(Ocultas)      ; sem letras: ESPACO sobe logo
                    or a
                    jp z,Esquerda
VOsobe
                    ELSE
                    or a
                    jp nz,Esquerda
                    ENDIF
                    ld a,(Cwd+1)        ; "/" e' a raiz: sai
                    or a
                    jp z,Sai
VOpai               call SaiNav
                    ld hl,TxtPai
                    ld a,'*'
                    rst 08h
                    db F_CHDIR
                    jp c,ErroPasta
                    jp EntraPasta

; O filtro fica nos ultimos 4 bytes da pagina 12 do DivMMC ("NV",0,filtro), para o
; proximo NMI. A pagina 12 e' a copia de 8000h-9FFFh durante os plugins; esses
; bytes (9FFCh-9FFFh) estao fora do codigo do NAV e o NMI.SYS repoe a RAM no fim.
LeFiltro            di
                    xor a
                    ld (Guardada),a
                    ld (Pendente),a
                    ld a,1              ; sem nada guardado: Timex 48
                    ld (Filtro),a
                    ld a,80h+12
                    out (0E3h),a
                    ld hl,(3FFCh)
                    ld de,"MN"
                    or a
                    sbc hl,de
                    jr nz,LFfim
                    ld a,(3FFEh)        ; bits 6-7 do F3 (sombra, Pentagon), do .go128 -penta
                    push af             ; v23: bit 0 = a seguir ao RESET+NMI arrancar a maquina
                    and 1               ; guardada (v24: qualquer maquina)
                    ld (Pendente),a
                    pop af
                    push af             ; v24: bits do Pentagon (7, 3) da maquina pendente
                    and 88h
                    ld (PendPenta),a
                    pop af
                    and 0C8h            ; + bit 3 (Pentagon 256 do .go256)
                    jp m,LFpenta        ; o bit 3 so' com o Pentagon (bit 7)
                    and 0C0h
LFpenta             ld (F3extra),a
                    ld a,(3FFFh)
                    or a
                    jr z,LFfim
                    cp 6
                    jr nc,LFfim
                    ld (Filtro),a
                    ld a,1
                    ld (Guardada),a
LFfim               xor a
                    out (0E3h),a
                    ret
GuardaFiltro        di
                    ld a,80h+12
                    out (0E3h),a
                    call GFescreve
                    xor a
                    out (0E3h),a
                    ret
; v23: Pentagon 1024 (F3extra bit 3 com o bit 7) -> ZXUNO DDh bit 2 = 1 e EFF7 = 0; senao
; DDh bit 2 = 0 e EFF7 bit 2 = 1 (paginacao do 128). No clone o DDh bit 2 e o EFF7 nao existem.
Poe1024             ld a,(Esta128)      ; so' na familia 128 (o DDh tambem tem o bit 0 do TC2068)
                    cp 1
                    ret nz
                    call ValorDD        ; DDh: bit 2 (1024K) e bit 1 (copia da sombra)
                    ld bc,0FC3Bh
                    push af
                    ld a,0DDh
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    and 4               ; EFF7: 0 com o 1024K, bit 2 = 1 sem
                    xor 4
                    ld bc,0EFF7h
                    out (c),a
                    ret
; v23j: valor do DDh para a familia 128: bit 1 = copia para a SRAM (sombra, F3 bit 6), como o
; PENTA.BIN e o .go128 -penta; bit 2 = 1024K (F3 bits 7 e 3). Sem o bit 1 o Pentagon com sombra
; ficava com buracos no ecra.
ValorDD             ld a,(F3extra)
                    ld c,0
                    bit 6,a
                    jr z,VDsc
                    ld c,2
VDsc                and 88h
                    cp 88h
                    ld a,c
                    ret nz
                    or 4
                    ret
AMmeio              ld (Esta128),a
                    ld a,1              ; vai para o TIMEX 2048
                    ld (Filtro),a
                    ld (NovaMaq),a
                    xor a
                    ld (F3extra),a
                    call GuardaFiltro
                    xor a
                    ld (CRf3+1),a
                    ld hl,CodigoReset
                    ld bc,LCodigoReset
                    jp RIcorre
; v24: IX = linha do comando (sem o ponto). Corre o .go pelo esxDOS (M_EXECCMD, como o menu do
; NMI do esxDOS faz com o .snapload). O .go nao volta (arranca a maquina); se voltar foi erro:
; sai do navegador e fica a mensagem do .go no ecra.
ExecGo              push ix
                    call MusCala
                    call SaiNav
                    di
                    im 1
                    ld a,(Iguardado)
                    ld i,a
                    IF HIRES
                    call EcraPlugin     ; ecra normal (o .go escreve com a ROM) e o F3 da maquina
                    ELSE
                    call LimpaEcra
                    ENDIF
                    pop ix
                    ld iy,5C3Ah         ; o .go escreve com a ROM (RST 10h)
                    rst 08h
                    db 8Fh              ; M_EXECCMD
                    jp RIantigo         ; v24c: voltou (o esxDOS nao correu o .go, ou o .go deu erro):
                                        ; faz como o v23 (o NAV carrega a ROM e reinicia ele proprio)
; NovaMaq / NovaPenta -> IX = comando
ComandoGo           ld a,(NovaMaq)
                    ld ix,TxtGo2068
                    cp 5
                    ret z
                    ld ix,TxtGoTimex
                    cp 4
                    ret z
                    ld a,(NovaPenta)
                    ld ix,TxtGo1024
                    cp 88h
                    ret z
                    ld ix,TxtGoPenta
                    cp 80h
                    ret z
                    ld ix,TxtGo128
                    ret
TxtGo128            db "go128",0
TxtGoTimex          db "go128 -timex",0
TxtGoPenta          db "go128 -penta",0
TxtGo1024           db "go1024",0
TxtGo2068           db "go2068",0
TxtGoReset          db "go128 -reset",0
; v24d: como o .gs: /BIN/GS105B.ROM (32K) para o GS pelos registos ZXUNO A0h (1 = parado e
; ponteiro a 0, 0 = arranca) e A1h (byte seguinte). No clone nao ha' GS (os registos nao existem).
CarregaGS           ld hl,TxtGSrom
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jr c,GSmau
                    ld (Handle),a
                    ld a,1
                    call GSa0
                    ld bc,0FC3Bh
                    ld a,0A1h
                    out (c),a
                    ld a,32             ; 32 blocos de 1K
                    ld (GSbl),a
GSbloco             ld a,(Handle)
                    ld hl,TMP
                    ld bc,1024
                    rst 08h
                    db F_READ
                    jr c,GSfecha
                    ld a,b
                    cp 4                ; 1024 bytes lidos? (B = 4)
                    jr nz,GSfecha
                    ld hl,TMP
                    ld de,1024
                    ld bc,0FD3Bh
GSbyte              ld a,(hl)
                    out (c),a
                    inc hl
                    dec de
                    ld a,d
                    or e
                    jr nz,GSbyte
                    ld hl,GSbl
                    dec (hl)
                    jr nz,GSbloco
                    ld a,(Handle)
                    rst 08h
                    db F_CLOSE
                    xor a               ; arranca o GS
                    call GSa0
                    ld hl,TxtGSok
                    jp Mensagem
GSfecha             ld a,(Handle)
                    rst 08h
                    db F_CLOSE
GSmau               ld hl,TxtGSmau
                    jp Mensagem
GSa0                push af
                    ld bc,0FC3Bh
                    ld a,0A0h
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    ret
TxtGSrom            db "/BIN/GS105B.ROM",0
TxtGSok             db "GS: ROM carregada, a correr",0
TxtGSmau            db "GS: falta /BIN/GS105B.ROM (32K)",0
GSbl                db 0
; v24g/h: NZ e EhTang = 1 se for o Timmy da Tang (A3h = 54h, ou os bits 5-0 do DFh a 0);
; no clone o registo nao existe (le-se o barramento): duas leituras iguais a 54h
VeTang              ld bc,0FC3Bh
                    ld a,0A3h
                    out (c),a
                    inc b
                    ld e,16             ; 16 leituras seguidas (o barramento solto nao da' sempre 54h)
VTl                 in a,(c)
                    cp 54h
                    jr nz,VTn
                    dec e
                    jr nz,VTl
                    ld a,1
                    ld (EhTang),a
                    or a
                    ret
VTn                 ld bc,0FC3Bh        ; v24h: core da Tang sem o A3h: o registo DFh tem os bits 5-0
                    ld a,0DFh           ; sempre a 0 na Tang (modo.v); no clone vem o barramento (3Fh)
                    out (c),a
                    inc b
                    ld e,16
VTd                 in a,(c)
                    and 3Fh
                    jr nz,VTc
                    dec e
                    jr nz,VTd
                    ld a,1
                    ld (EhTang),a
                    or a
                    ret
VTc                 xor a
                    ld (EhTang),a
                    ret
TxtP128             db "PENTAGON 128 ",0
TxtP1024            db "PENTAGON 1024",0
EhTang              db 0
MarcaPend           di
                    ld a,80h+12
                    out (0E3h),a
                    ld hl,3FFEh
                    set 0,(hl)
                    xor a
                    out (0E3h),a
                    ret
ApagaPag12          di
                    ld a,80h+12
                    out (0E3h),a
                    xor a
                    ld (3FFCh),a
                    out (0E3h),a
                    ret
GFescreve           ld hl,"MN"          ; (com a pagina 12 em 2000h)
                    ld (3FFCh),hl
                    ld a,(F3extra)
                    ld (3FFEh),a
                    ld a,(Filtro)
                    ld (3FFFh),a
                    ret

; ---------------------------------------------------------------------------
; Maquinas: 1 Timex 48, 2 ZX 48K, 3 ZX 128K, 4 Timex 128.
; Entre 1 e 2 (ou entre 3 e 4) muda-se so' o F3 do SCLD. Entre 48 e 128 reinicia-se:
; para 128 carrega /BIN/128.rom nas paginas 32-35 (como o .go128); para 48 desliga o
; modo ROM em RAM (como o .go128 -reset).

; modo 128K ligado? (registo MODE do DivTIESUS, bit 7 = ROM em RAM) -> A = 1/0
; A = 2: a correr o ROM do TC2068 (o CHANS do 2068 e' 6840h; no Spectrum 5CB6h)
Ve128               ld a,(5C50h)
                    cp 68h
                    ld a,2
                    ret z
                    ld bc,0FC3Bh
                    ld a,0DFh
                    out (c),a
                    inc b
                    in a,(c)
                    rlca
                    and 1
                    ret

; A = maquina -> A = classe: 0 (48: 1, 2), 1 (128: 3, 4), 2 (TC2068: 5)
Classe              cp 5
                    jr z,CL2
                    cp 3
                    ld a,0
                    ret c
                    inc a
                    ret
CL2                 ld a,2
                    ret


; ao entrar: a maquina e' sempre a que o hardware diz (classe pelo registo MODE e pelo
; CHANS, Timex/ZX pela porta FF). Depois de ligar e' o Timex 2048: o NAV nao muda de
; maquina sozinho. O /SYS/NAV.CFG fica com a ultima maquina que arrancou com sucesso
; (so' se escreve quando muda).
AcertaMaquina       call Ve128
                    cp 1                ; v23k: ROM em RAM ligado mas o F4 sem o F0 (nem 128 nem 2068):
                    jr nz,AMok          ; ficou "a meio" (um RESET sem o NMI). Volta ao TC2048: a espera
                    ld bc,00F4h         ; do RESET+NMI (na Tang faz-se sozinho)
                    in a,(c)
                    cp 0F0h
                    ld a,1
                    jp nz,AMmeio
AMok                ld (Esta128),a
                    cp 1                ; os bits do Pentagon/sombra so' no modo 128K
                    jr z,AM128
                    xor a
                    ld (F3extra),a
                    ld a,(Esta128)
AM128
                    or a                ; v23: 128 -> TC2068 pelo RESET+NMI: arranca-o ja'
                    jr nz,AMsemp
                    ld a,(Pendente)
                    or a
                    jr z,AMsemp
                    ld a,(Filtro)       ; v24: qualquer maquina: no 48 so' o F3; o resto pelo .go
                    ld (NovaMaq),a
                    call Classe
                    or a
                    ld a,0
                    ld (F3extra),a
                    jr z,AMf3           ; TIMEX 2048 / ZX 48K: o F3 dela (o GuardaFiltro apaga o pendente)
                    ld a,(PendPenta)
                    ld (NovaPenta),a
                    ld a,1
                    ld (SemPergunta),a
                    jr AMf3
AMsemp              ld a,(Esta128)
                    cp 2                ; no TC2068: e' essa a maquina (para sair dela: RESET+NMI)
                    ld a,5
                    jr z,AM2068
                    ld a,(Guardada)
                    or a
                    jr z,AMpadrao       ; acabou de ligar: a verdadeira, sem gravar
                    call MaqHw          ; ja' corria: a verdadeira, e fica no cartao
                    ld (Filtro),a
                    call GravaSeMudou
                    jr AMf3
AM2068              ld (Filtro),a
                    call GravaSeMudou
                    jr AMf3
AMpadrao            call MaqHw
                    ld (Filtro),a
AMf3                ld a,(Filtro)       ; o F3 da maquina (o RESET nao o muda; a FF fica)
                    call ValorF3
                    ld bc,00F3h
                    out (c),a
                    jp GuardaFiltro

; maquina verdadeira -> A: 48 = 1 Timex / 2 ZX, 128 = 4 Timex / 3 ZX (MudouFF = 1: FF e' do Timex)
MaqHw               ld a,(Esta128)
                    or a
                    ld a,(MudouFF)
                    jr nz,MH128
                    xor 1
                    inc a
                    ret
MH128               add a,3
                    ret

; A = maquina -> A = valor do F3
ValorF3             ld e,a
                    ld d,0
                    ld hl,TabF3-1
                    add hl,de
                    ld a,(hl)
                    ld hl,F3extra       ; + os bits 6-7 (Pentagon e sombra) se os houver
                    or (hl)
                    ret

; A = maquina: escreve o F3 (e a FF a 0 se a FF passar a ser do Timex)
PoeF3               call ValorF3
                    ld bc,00F3h
                    out (c),a
                    and 20h
                    ret nz
                    xor a               ; modos do Timex ligados: ecra normal (a' saida)
                    IF !HIRES
                    out (0FFh),a        ; (no hi-res nao: o ecra do navegador e' o da FF)
                    ENDIF
                    ld (PortaFF),a
                    ld (MudouFF),a
                    ret

; A = nova maquina (vem das teclas 1-4 ou do joystick)
TrocaMaquina        push af             ; v23: o MusCala estraga o A (a maquina nova)
                    call MusCala        ; v22: a mudar de maquina, sem musica
                    pop af
                    ld hl,NovaPenta     ; as outras maquinas: sem Pentagon nem sombra
                    ld (hl),0
TMcomum             ld (NovaMaq),a
                    ld hl,Filtro
                    cp (hl)
                    jr nz,TMoutra
                    ld a,(F3extra)      ; a mesma: so' se o Pentagon mudar
                    and 80h
                    ld hl,NovaPenta
                    cp (hl)
                    jp z,DesenhaFiltro
TMoutra             ld a,(NovaPenta)    ; v24: as mudancas fazem-se pelos .go (GO128, GO1024, GO2068):
                    ld (F3extra),a      ; sempre o mesmo arranque limpo. So' entre o TIMEX 2048 e o
                    ld a,(NovaMaq)      ; ZX 48K (a mesma ROM) muda so' o F3.
                    call Classe
                    ld c,a              ; classe nova
                    ld a,(Esta128)
                    or a
                    jr nz,TMemRAM
                    ld a,c              ; estamos no 48: para o 48 o F3, para o resto o .go
                    or a
                    jr z,TMmesma
                    jp Reinicia
TMemRAM             cp 2                ; no 128 ou no 2068 (ROM em RAM ligado)
                    jr z,TMde2068
                    ld a,c              ; no 128: para o 128 (outra variante) o .go; para o 48 ou o
                    cp 1                ; 2068 primeiro o .go128 -reset (RESET+NMI) e depois a maquina
                    jp z,Reinicia
                    jr TMreset
TMde2068            ld a,c              ; no 2068: para o 128 o .go128 (o DDh vai a 0); para o 48 o reset
                    cp 1
                    jp z,Reinicia
TMreset             ld a,(NovaMaq)      ; v24: sair do ROM em RAM. Na pagina 12 a maquina nova +
                    ld (Filtro),a       ; pendente (3FFEh bit 0): depois do RESET+NMI o NAV arranca-a.
                    call GuardaFiltro
                    call MarcaPend
                    ld a,(NovaMaq)
                    call Classe
                    cp 2
                    jr nz,TMr48
                    call SoftMrst       ; para o TC2068: com a DivTIESUS nova o A2h = 52h desliga ja'
                    jr nz,TMr48         ; o ROM em RAM: corre logo o .go2068, sem reset
                    xor a
                    ld (Esta128),a
                    ld ix,TxtGo2068
                    jp ExecGo
TMr48               call SaiNav         ; TIMEX 2048 / ZX 48K (ou sem o master reset por software): o
                    ld a,(NovaMaq)      ; codigo de reset com o F3 da maquina (aviso; com a DivTIESUS
                    call ValorF3        ; nova arranca sozinho, na Tang faz o RESET+NMI, no clone antigo
                    ld (CRf3+1),a       ; espera pelo botao)
                    ld hl,CodigoReset
                    ld bc,LCodigoReset
                    jp RIcorre
; ZXUNO A2h = 52h e le' o DFh: Z = o modo ROM em RAM desligou-se (master reset por software)
SoftMrst            ld bc,0FC3Bh
                    ld a,0A2h
                    out (c),a
                    inc b
                    ld a,52h
                    out (c),a
                    dec b
                    ld a,0DFh
                    out (c),a
                    inc b
                    in a,(c)
                    and 80h
                    ret
TMmesma             ld a,(NovaMaq)      ; mesma classe: so' o F3
                    call PoeF3
                    call Poe1024
                    IF HIRES
                    ld a,(NovaMaq)
                    ld (Filtro),a
                    call EntraHires
                    ENDIF
                    ld a,(NovaMaq)
                    ld (Filtro),a
                    call GravaCfg
                    ld a,(NovaMaq)
                    jp AplicaFiltro

; reinicia na maquina NovaMaq (pergunta antes, menos no arranque automatico)
Reinicia            call MusCala        ; v23e: calada (no arranque pelo pendente a musica ja' tocava e a
                                        ; interrupcao chamava o leitor com a pagina da ROM em 2000h)
                    ld a,(SemPergunta)
                    or a
                    jr nz,RIsim
                    ld hl,TxtReinicia
                    call MensagemSoEcra
RIsolta             halt                ; primeiro larga a tecla que escolheu a maquina
                    call Varre
                    or a
                    jr nz,RIsolta
                    ld (UltTecla),a
RIesp               call LeTecla
                    or a
                    jr z,RIesp
                    cp 13
                    jr z,RIsim
                    xor a
                    ld (F3extra),a
                    ld (MsgEstado),a
                    call DesenhaFiltro
                    jp DesenhaEstado
RIsim               call MusCala        ; v23e: a musica parada enquanto se carrega a ROM (o LeTecla da
                                        ; pergunta volta a liga'-la)
                    ld hl,TxtAMudar
                    call MensagemSoEcra
                    ld a,(NovaMaq)
                    ld (Filtro),a
                    call GuardaFiltro
                    call GravaCfg
                    call ComandoGo      ; v24: IX = "go128 ...", "go1024" ou "go2068"
                    jp ExecGo
RIantigo            call SaiNav         ; (v23: carregava a ROM e reiniciava ele proprio; ja' nao se usa)
                    ld a,(NovaMaq)
                    cp 5
                    jr z,RI2068
                    ld hl,TxtRom
                    call CarregaRom
                    jp c,RIerro
                    call GravaCfg       ; a ROM carregou: esta maquina fica no cartao
                    ld a,(F3extra)      ; Pentagon: /BIN/PENTA.BIN testa os CPLDs e liga a sombra
                    or a
                    jr z,RInp
                    ld hl,TxtPentaBin
                    ld de,TMP
                    ld bc,100h
                    call LeFich
                    jr c,RInp           ; sem o ficheiro: so' os tempos
                    ld a,(NovaMaq)
                    call ValorF3        ; A = F3 com o bit 7
                    call TMP            ; -> A = 80h ou C0h (com sombra)
                    ld b,a              ; v23: + o bit 3 (Pentagon 1024)
                    ld a,(NovaPenta)
                    and 8
                    or b
                    ld (F3extra),a
                    call GuardaFiltro   ; pagina 12: o NAV mantem-nos nos NMIs
RInp                ld a,(NovaMaq)      ; F3 da maquina nova no codigo que reinicia
                    call ValorF3
                    ld (C128f3+1),a
                    call ValorDD        ; v23j: DDh (copia da sombra, 1024K) no codigo que reinicia
                    ld (C128dd+1),a
                    ld hl,Codigo128
                    ld bc,LCodigo128
                    jr RIcorre
RI2068              ld hl,TxtRom2068
                    call CarregaRom
                    jr c,RIerro
                    ld a,(CRtam)
                    cp 40h              ; tem de ter a EXROM (24K, ou 32K com o esxDOS)
                    scf
                    jr z,RIerro
                    cp 80h              ; 32K: o firmware do esxDOS do 2068 vai para a pagina 37
                    ld a,80h            ; DF: ROM em RAM, sem o DivMMC
                    jr z,RI68esx
                    ld a,(Esta128)      ; v23i: 24K vindo do 128: o DivMMC (DF bit 6) so' se desliga
                    cp 1                ; com o RESET+NMI -> espera do reset (depois arranca sozinho)
                    jp z,TMreset
                    ld a,80h
                    jr RI68df
RI68esx             ld a,0C0h           ; DF: ROM em RAM, com o DivMMC (firmware da pagina 37)
RI68df              ld (C68df+1),a
                    call GravaCfg       ; a ROM carregou: esta maquina fica no cartao
                    ld hl,Codigo2068
                    ld bc,LCodigo2068
RIcorre             di
                    push hl
                    push bc
                    ld hl,F3Seguro      ; v23l: o OUT do F3 corre em F000h (fora da RAM de video)
                    ld de,0F000h
                    ld bc,LF3Seguro
                    ldir
                    pop bc
                    pop hl
                    ld de,5B00h         ; corre no buffer da impressora (o F4 muda o resto)
                    ldir
                    jp 5B00h
; F3 = A, a correr em F000h; espera ~1 ms antes de voltar (a pilha e o codigo em 5B00h estao na
; RAM de video: os dois CPLDs tem de ja' estar no modo novo da sombra), como o PENTA.BIN/.go128
F3Seguro            ld bc,00F3h
                    out (c),a
                    ld b,0
F3S1                djnz F3S1
                    ret
LF3Seguro           equ $-F3Seguro
RIerro              xor a
                    ld (SemPergunta),a
                    ld (F3extra),a
                    ld a,(Esta128)      ; ficou na mesma maquina
                    or a
                    ld a,1
                    jr z,RIe1
                    ld a,3
RIe1                ld (Filtro),a       ; o NAV.CFG fica com a ultima que deu
                    call GuardaFiltro
                    ei                  ; (GuardaFiltro deixa-as desligadas)
                    ld a,(Filtro)
                    call AplicaFiltro   ; volta a mostrar a lista desta maquina
                    ld hl,TxtSemRom
                    jp Mensagem


; HL = ROM: 32K (ROM0+ROM1 -> paginas 32-35), 16K (-> 32,33 e 34,35) ou, no TC2068, 24K
; (16K -> 32,33 e 34,35, a EXROM de 8K -> 36) ou 32K (mais o ESX2068.BIN -> 37).
; Carry = erro. CRtam = 80h, 40h ou 60h.
CarregaRom          ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (Handle),a
                    ld hl,TMP
                    rst 08h
                    db F_FSTAT
                    jr c,CRfecha
                    ld hl,(TMP+9)
                    ld a,(TMP+7)
                    or h
                    or l
                    scf
                    jr nz,CRfecha
                    ld a,(TMP+8)
                    ld (CRtam),a
                    cp 80h
                    jr z,CRok
                    cp 40h
                    jr z,CRok
                    cp 60h
                    scf
                    jr nz,CRfecha
CRok                xor a
                    ld (CRk),a
CRbloco             ld a,(Handle)
                    ld hl,0C000h
                    ld bc,2000h
                    rst 08h
                    db F_READ
                    jr c,CRfecha
                    ld a,b
                    cp 20h
                    scf
                    jr nz,CRfecha
                    di
                    ld a,(NovaMaq)      ; pagina: 32+k; no TC2068 a EXROM vai para 36
                    cp 5                ; e o firmware do esxDOS para 37
                    ld a,(CRk)
                    jr nz,CRpag
                    cp 2
                    jr c,CRpag
                    add a,2
CRpag               add a,80h+32
                    call CRcopia
                    ld a,(CRk)          ; 16K e TC2068: os dois primeiros tambem em 34,35
                    cp 2
                    jr nc,CRprox
                    ld a,(CRtam)
                    cp 80h
                    jr nz,CRdup
                    ld a,(NovaMaq)
                    cp 5
                    jr nz,CRprox
CRdup               ld a,(CRk)
                    add a,80h+34
                    call CRcopia
CRprox              ld hl,CRk
                    inc (hl)
                    ld a,(CRtam)        ; blocos: 80h -> 4, 40h -> 2, 60h -> 3
                    rlca
                    rlca
                    rlca
                    and 7
                    cp (hl)
                    jr nz,CRbloco
                    or a
CRfecha             push af
                    ld a,(Handle)
                    rst 08h
                    db F_CLOSE
                    pop af
                    ret
CRcopia             out (0E3h),a
                    ld hl,0C000h
                    ld de,2000h
                    ld bc,2000h
                    ldir
                    xor a
                    out (0E3h),a
                    ret

; /SYS/NAV.CFG: "NM",0,maquina
GravaCfg            ld a,'*'
                    ld b,FA_WRITE+FA_CREATE_AL
                    ld hl,TxtCfg
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (Handle),a
                    ld hl,"MN"
                    ld (CfgBuf),hl
                    xor a
                    ld (CfgBuf+2),a
                    ld a,(Filtro)
                    ld (CfgBuf+3),a
                    ld a,(Handle)
                    ld hl,CfgBuf
                    ld bc,4
                    rst 08h
                    db F_WRITE
                    ld a,(Handle)
                    rst 08h
                    db F_CLOSE
                    ret
; grava o NAV.CFG so' se a maquina (Filtro) for outra
GravaSeMudou        call LeCfg
                    ld hl,Filtro
                    cp (hl)
                    ret z
                    jp GravaCfg
; HL = ficheiro, DE = destino, BC = maximo: le'. Carry = erro, BC = bytes lidos
LeFich              push de
                    push bc
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    pop bc
                    pop hl
                    ret c
                    ld (Handle),a
                    rst 08h
                    db F_READ
                    push af
                    push bc
                    ld a,(Handle)
                    rst 08h
                    db F_CLOSE
                    pop bc
                    pop af
                    ret
LeCfg               ld hl,TxtCfg
                    ld de,CfgBuf
                    ld bc,4
                    call LeFich
                    jr c,LCnada
                    ld hl,(CfgBuf)
                    ld de,"MN"
                    or a
                    sbc hl,de
                    jr nz,LCnada
                    ld a,(CfgBuf+2)
                    or a
                    jr nz,LCnada
                    ld a,(CfgBuf+3)
                    or a
                    jr z,LCnada
                    cp 6
                    ret c
LCnada              xor a
                    ret

; Codigo que reinicia (copiado para 5B00h): o F4 muda o que ha' em 8000h-FFFFh.
; Para 128: como o .go128 (as paginas 32-35 ja' tem a ROM).
Codigo128           di
                    ld sp,6000h
                    ld a,128+0          ; apaga a pagina 0: o esxDOS reinicia-se
                    out (0E3h),a
                    ld hl,2000h
                    ld de,2001h
                    ld (hl),l
                    ld bc,1FFFh
                    ldir
                    xor a
                    ld bc,7FFDh
                    out (c),a
                    ld b,1Fh
                    out (c),a
                    out (0FFh),a
C128f3              ld a,23h
                    ld bc,00F3h
                    out (c),a
                    ld a,0F0h
                    ld bc,0FFF4h
                    out (c),a
                    ld bc,0FC3Bh        ; modo ROM em RAM, com as traps do DivMMC
                    ld a,0DFh
                    out (c),a
                    inc b
                    in l,(c)
                    ld a,40h
                    set 7,l
                    or l
                    out (c),a
                    ld bc,0FC3Bh        ; v23g: DDh sempre escrito (0, ou 4 no Pentagon 1024)
                    ld a,0DDh
                    out (c),a
                    inc b
C128dd              ld a,0              ; v23: bit 2 = Pentagon 1024 (EFF7 = 0), bit 1 = copia da sombra
                    out (c),a
                    and 4
                    jr z,C128n
                    xor a
                    ld bc,0EFF7h
                    out (c),a
C128n               xor a
                    out (0E3h),a
                    ld a,3Fh
                    ld i,a
                    im 1
                    jp 0
LCodigo128          equ $-Codigo128
; De 128 para 48: 7FFD = 0, F4 = 0, F3 da maquina, FF = 0, pagina 0 a zeros e parado:
; o RESET+NMI desliga o modo ROM em RAM e arranca o TC2048.
CodigoReset         di
                    ld sp,6000h
                    ld hl,4000h         ; v23d/v23n: ecra normal limpo (preto) e o aviso em letras
                    ld de,4001h         ; (no clone o RESET nao limpa a FF: ficava preto/lixo depois)
                    ld (hl),l
                    ld bc,1AFFh
                    ldir
                    ld hl,5800h+10*32   ; linhas 10 e 12 a branco brilhante
                    ld b,32
CRa1                ld (hl),47h
                    inc hl
                    djnz CRa1
                    ld hl,5800h+12*32
                    ld b,32
CRa2                ld (hl),47h
                    inc hl
                    djnz CRa2
                    ld hl,CRmsg1-CodigoReset+5B00h
                    ld de,4840h+8       ; linha 10, coluna 8
                    call CRpr-CodigoReset+5B00h
                    ld hl,CRmsg2-CodigoReset+5B00h
                    ld de,4880h+6       ; linha 12, coluna 6
                    call CRpr-CodigoReset+5B00h
                    xor a               ; v23m: a FF a 0 ANTES do F3: o F3 do ZX 48K tem o bit 5 e com
                    out (0FFh),a        ; ele a FF e' ignorada (ficava em hi-res: 128 -> ZX 48K bugava)
CRf3                ld a,0              ; v23l: o F3 de fora da RAM de video (F000h): com a sombra do
                    call 0F000h         ; Pentagon desligar o F3 bit 6 a correr em 5B00h estragava o codigo
                    xor a
                    ld bc,7FFDh
                    out (c),a
                    ld bc,0FFF4h
                    out (c),a
                    ld a,128+0
                    out (0E3h),a
                    ld hl,2000h
                    ld de,2001h
                    ld (hl),l
                    ld bc,1FFFh
                    ldir
                    xor a
                    out (0E3h),a
                    ld bc,0FC3Bh        ; v23g: DDh = 0 (sem o modo TC2068): se o reset mestre nao o
                    ld a,0DDh           ; limpar, a maquina arrancava outra vez no 2068
                    out (c),a
                    inc b
                    xor a
                    out (c),a
                    ld bc,0FC3Bh        ; v23b: no Timmy da Tang o registo ZXUNO A2h = 52h faz o
                    ld a,0A2h           ; RESET+NMI sozinho (no clone nao existe: fica a' espera)
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
CRpara              ld a,2              ; borda a piscar: carregar em RESET com NMI
                    out (0FEh),a
                    ld b,0
CRp1                djnz CRp1
                    xor a
                    out (0FEh),a
CRp2                djnz CRp2
                    jr CRpara
; texto HL na linha do ecra DE (letra do NAV: Fonte, 32..127)
CRpr                ld a,(hl)
                    or a
                    ret z
                    push hl
                    push de
                    sub 32
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld bc,Fonte
                    add hl,bc
                    ld b,8
CRpl                ld a,(hl)
                    ld (de),a
                    inc hl
                    inc d
                    djnz CRpl
                    pop de
                    pop hl
                    inc hl
                    inc e
                    jr CRpr
CRmsg1              db "MUDAR DE MAQUINA",0
CRmsg2              db "CARREGA NMI + RESET",0
LCodigoReset        equ $-CodigoReset

; Para TC2068: ROM do 2068 (paginas 32-35) e EXROM (36) pela DivTIESUS (registo DDh = 1),
; sem esxDOS nem NMI. Sai-se com RESET+NMI (volta o TC2048).
Codigo2068          di
                    ld sp,6000h
                    ld a,128+0          ; apaga a pagina 0: o esxDOS reinicia-se depois do RESET+NMI
                    out (0E3h),a
                    ld hl,2000h
                    ld de,2001h
                    ld (hl),l
                    ld bc,1FFFh
                    ldir
                    xor a               ; F3 = 0 (antes da FF: com o bit 5 a FF e' ignorada)
                    call 0F000h         ; v23l: de fora da RAM de video (sombra do Pentagon)
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
                    ld a,0DFh           ; modo ROM em RAM; com o firmware na pagina 37 tambem o DivMMC
                    out (c),a
                    inc b
C68df               ld a,80h
                    out (c),a
                    xor a
                    out (0E3h),a
                    ld a,3Fh
                    ld i,a
                    im 1
                    jp 0
LCodigo2068         equ $-Codigo2068

; entra em _NAV (carry = nao ha') / volta a' pasta de cima se estiver la'
EntraNav            ld hl,TxtNavDir
                    ld a,'*'
                    rst 08h
                    db F_CHDIR
                    ret c
                    ld a,1
                    ld (NaNav),a
                    ret
SaiNav              ld a,(NaNav)
                    or a
                    ret z
                    xor a
                    ld (NaNav),a
                    ld hl,TxtPai
                    ld a,'*'
                    rst 08h
                    db F_CHDIR
                    ret

ErroPasta           ld hl,TxtErroPasta
                    jp Mensagem

; ---------------------------------------------------------------------------
; Pastas e indices

EntraPasta          ld a,1              ; v19: mudou de pasta (entrar, voltar, atalho): a tecla
                    ld (Larga),a        ; (ou o joystick) tem de ser largada antes da seguinte
                    ld a,'*'
                    ld hl,Cwd
                    rst 08h
                    db F_GETCWD
                    jr nc,EPcwd
                    ld hl,TxtBarra
                    ld de,Cwd
                    ld bc,2
                    ldir
EPcwd               xor a
                    ld (Foco),a
                    ld (GSel),a
                    ld (GTopo),a
                    call EntraNav       ; numa pasta grande, cada F_OPEN "_NAV/X.IDX" procura o
                    jr c,EPsem          ; _NAV entre milhares de entradas: entra-se la' uma vez so'
                    ld hl,TxtNavIdx
                    ld de,NavIdx
                    ld bc,LNavIdx
                    call LeFich
                    jr c,EPsemNav
                    ld hl,LNavIdx
                    or a
                    sbc hl,bc
                    jr nz,EPsemNav
                    ld hl,(NavIdx)
                    ld de,"AN"          ; "NA" little-endian
                    or a
                    sbc hl,de
                    jr nz,EPsemNav
                    xor a
                    ld (Modo),a
                    call ConstroiVis
                    call CarregaGrupo
                    IF HIRES
                    call VeLetras
                    ENDIF
                    jp DesenhaTudo
EPsemNav            call SaiNav
EPsem               ld a,1
                    ld (Modo),a
                    ld (NVis),a
                    ld a,29
                    ld (Vis),a
                    call LePasta
                    IF HIRES
                    call VeLetras
                    ENDIF
                    jp DesenhaTudo

; numero de entradas do grupo A, com o filtro -> HL
ContaGrupo          ld e,a
                    ld d,0
                    ld hl,NavIdx+8
                    add hl,de
                    add hl,de           ; hl = total do grupo
                    or a
                    jr z,CGtotal        ; pastas: sempre todas
                    IF FILTRA_LISTA
                    ld a,(Filtro)
                    ELSE
                    xor a               ; a lista mostra sempre tudo (a maquina so' escolhe onde corre)
                    ENDIF
                    or a
                    jr z,CGtotal
                    cp 5
                    jr z,CGoutras
                    call CGmaq
CGtotal             ld a,(hl)
                    inc hl
                    ld h,(hl)
                    ld l,a
                    ret
CGoutras            push hl
                    xor a
                    call CGmaq
                    ld c,(hl)
                    inc hl
                    ld b,(hl)
                    pop hl
                    ld a,5
                    call CGmaq
                    ld a,(hl)
                    inc hl
                    ld h,(hl)
                    ld l,a
                    add hl,bc
                    ret
; hl (total do grupo) -> contagem da maquina A: +58*(A+1)
CGmaq               inc a
                    ld de,58
CGm1                add hl,de
                    dec a
                    jr nz,CGm1
                    ret

; Vis = grupos com entradas
ConstroiVis         ld hl,Vis
                    ld c,0              ; grupo
                    ld b,0              ; quantos
CVciclo             push hl
                    push bc
                    ld a,c
                    call ContaGrupo
                    ld a,h
                    or l
                    pop bc
                    pop hl
                    jr z,CVprox
                    ld (hl),c
                    inc hl
                    inc b
CVprox              inc c
                    ld a,c
                    cp 29
                    jr c,CVciclo
                    ld a,b
                    ld (NVis),a
                    ret

; A = grupo; procura-o em Vis -> A = posicao (carry = nao esta)
ProcuraGrupo        ld c,a
                    ld a,(NVis)
                    or a
                    scf
                    ret z
                    ld b,a
                    ld hl,Vis
                    ld e,0
PGciclo             ld a,(hl)
                    cp c
                    ld a,e
                    ret z               ; carry a 0 (cp deu igual)
                    inc hl
                    inc e
                    djnz PGciclo
                    scf
                    ret

; A = posicao em Vis -> A = grupo
GrupoVis            ld e,a
                    ld d,0
                    ld hl,Vis
                    add hl,de
                    ld a,(hl)
                    ret

AjustaGTopo         ld a,(GTopo)
                    ld b,a
                    ld a,(GSel)
                    cp b
                    jr nc,AGT1
                    ld (GTopo),a
                    ret
AGT1                sub NLIN-1
                    ret c
                    jr z,AGT2
                    cp b
                    ret c
AGT2                ld (GTopo),a
                    ret

; grupo seleccionado: total e primeiro bloco
CarregaGrupo        ld hl,0
                    ld (Sel),hl
                    ld (Topo),hl
                    ld (Base),hl
                    ld (NReg),hl
                    ld a,(Modo)
                    or a
                    ret nz
                    ld a,(NVis)
                    or a
                    jr z,CGvazio
                    ld a,(GSel)
                    call GrupoVis
                    ld (GrupoAct),a
                    call ContaGrupo
                    ld (Total),hl
                    jp CarregaBloco
CGvazio             ld (Total),hl
                    ret

; le o ficheiro do grupo e guarda em BUF os registos que passam o filtro,
; a partir do numero (Base) dessa lista
CarregaBloco        ld hl,0
                    ld (NReg),hl
                    ld (Indice),hl
                    ld a,(GrupoAct)     ; "X.IDX" (ja' estamos em _NAV)
                    ld hl,TxtGrupoNome
                    ld de,NomeIdx
                    or a
                    jr z,CBnome         ; 0 = "DIR"
                    inc hl
                    inc hl
                    inc hl
                    inc hl
                    dec a
                    jr z,CBnome         ; 1 = "0"
                    inc hl
                    inc hl
                    dec a
                    cp 26
                    jr nc,CBnome        ; 28 = "_"
                    add a,'A'
                    ld (de),a
                    inc de
                    jr CBext
CBnome              ld a,(hl)
                    or a
                    jr z,CBext
                    ld (de),a
                    inc hl
                    inc de
                    jr CBnome
CBext               xor a
                    ld (SoMaq),a
                    IF FILTRA_LISTA
                    ld a,(Filtro)       ; com filtro: "X3.IDX" so' tem os dessa maquina
                    ELSE
                    xor a               ; a lista mostra sempre tudo (a maquina so' escolhe onde corre)
                    ENDIF
                    or a
                    jr z,CBext2
                    ld a,(GrupoAct)
                    or a
                    jr z,CBext2         ; pastas: sempre DIR.IDX
                    push de
                    ld a,(Filtro)
                    add a,'0'
                    ld (de),a
                    inc de
                    ld hl,TxtIdx
                    ld bc,5
                    ldir
                    ld a,'*'
                    ld b,FA_READ
                    ld hl,NomeIdx
                    rst 08h
                    db F_OPEN
                    pop de
                    jr c,CBext2         ; indice antigo, sem ficheiros por maquina: le o X.IDX
                    ld (Handle),a
                    ld a,1
                    ld (SoMaq),a
                    jr CBaberto
CBext2              ld hl,TxtIdx
                    ld bc,5
                    ldir
                    ld a,'*'
                    ld b,FA_READ
                    ld hl,NomeIdx
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (Handle),a
                    IF FILTRA_LISTA
                    ld a,(Filtro)       ; sem filtro (ou ja' filtrado) e do principio: le direito para BUF
                    ELSE
                    xor a               ; a lista mostra sempre tudo (a maquina so' escolhe onde corre)
                    ENDIF
                    or a
                    jr z,CBdir
                    ld a,(SoMaq)
                    or a
                    jr z,CBler
CBaberto
CBdir
                    ld hl,(Base)
                    ld a,h
                    or l
                    jr nz,CBler
                    ld a,(Handle)
                    ld hl,BUF
                    ld bc,MAXREC*64
                    rst 08h
                    db F_READ
                    jp c,CBfim
                    ld a,c              ; NReg = bc / 64
                    rlca
                    rlca
                    and 3
                    ld l,a
                    ld a,b
                    add a,a
                    add a,a
                    or l
                    ld l,a
                    ld a,b
                    rlca
                    rlca
                    and 3
                    ld h,a
                    ld (NReg),hl
                    ld (Indice),hl
                    jr CBfim
CBler               ld a,(Handle)
                    ld hl,TMP
                    ld bc,1024
                    rst 08h
                    db F_READ
                    jr c,CBfim
                    ld a,b              ; registos lidos = bc / 64
                    or c
                    jr z,CBfim
                    ld a,c
                    rlca
                    rlca
                    and 3
                    ld c,a
                    ld a,b
                    add a,a
                    add a,a
                    or c
                    ld b,a              ; b = registos neste bloco (ate' 16)
                    ld ix,TMP
CBreg               push bc
                    call Passa
                    jr nz,CBnao
                    ld hl,(Indice)
                    ld de,(Base)
                    or a
                    sbc hl,de
                    jr c,CBconta        ; antes da base
                    ld hl,(NReg)        ; destino BUF + NReg*64
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,BUF
                    add hl,de
                    ex de,hl
                    push ix
                    pop hl
                    ld bc,64
                    ldir
                    ld hl,(NReg)
                    inc hl
                    ld (NReg),hl
                    ld de,MAXREC
                    or a
                    sbc hl,de
                    jr nz,CBconta
                    pop bc
                    jr CBfim            ; buffer cheio
CBconta             ld hl,(Indice)
                    inc hl
                    ld (Indice),hl
CBnao               ld de,64
                    add ix,de
                    pop bc
                    djnz CBreg
                    jr CBler
CBfim               ld a,(Handle)
                    rst 08h
                    db F_CLOSE
                    ret

; registo em IX passa o filtro? (Z = sim)
Passa               ld a,(ix+1)         ; pasta: sempre
                    or a
                    jr nz,PSsim
                    IF FILTRA_LISTA
                    ld a,(Filtro)
                    ELSE
                    xor a               ; a lista mostra sempre tudo (a maquina so' escolhe onde corre)
                    ENDIF
                    or a
                    ret z
                    ld b,a
                    ld a,(ix+0)
                    and 7Fh
                    ld c,a
                    ld a,b
                    cp 5
                    jr z,PSoutras
                    cp c
                    ret
PSoutras            ld a,c
                    or a
                    ret z
                    cp 5
                    ret
PSsim               xor a
                    ret

; o bloco em memoria tem de cobrir Topo..Topo+NLIN
GaranteBloco        ld hl,(Topo)
                    ld de,(Base)
                    or a
                    sbc hl,de
                    jr c,GBnovo         ; Topo < Base
                    ld de,NLIN
                    add hl,de           ; hl = Topo+NLIN-Base
                    ld de,(NReg)
                    or a
                    sbc hl,de
                    ret c
                    ret z               ; cabe
                    ld hl,(Base)        ; ha' mais no ficheiro?
                    ld de,(NReg)
                    add hl,de
                    ld de,(Total)
                    or a
                    sbc hl,de
                    ret nc
GBnovo              ld hl,(Topo)
                    ld de,150
                    or a
                    sbc hl,de
                    jr nc,GBb
                    ld hl,0
GBb                 ld (Base),hl
                    jp CarregaBloco

; Sel dentro do ecra
AjustaTopo          ld hl,(Sel)
                    ld de,(Topo)
                    or a
                    sbc hl,de
                    jr nc,ATdepois
                    ld hl,(Sel)
                    ld (Topo),hl
                    jr GaranteBloco
ATdepois            ld de,NLIN
                    or a
                    sbc hl,de
                    jr c,GaranteBloco
                    ld hl,(Sel)
                    ld de,NLIN-1
                    or a
                    sbc hl,de
                    ld (Topo),hl
                    jr GaranteBloco

; HL = registo numero HL (absoluto) em BUF; carry = nao esta' carregado
RegNum              ld de,(Base)
                    or a
                    sbc hl,de
                    ret c
                    ld de,(NReg)
                    push hl
                    or a
                    sbc hl,de
                    pop hl
                    ccf
                    ret c
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,BUF
                    add hl,de
                    or a
                    ret

RegSel              ld hl,(Total)
                    ld a,h
                    or l
                    scf
                    ret z
                    ld hl,(Sel)
                    jr RegNum

; pasta sem indice: le-a com F_OPENDIR/F_READDIR (pela ordem do disco)
LePasta             ld hl,0
                    ld (NReg),hl
                    ld (Base),hl
                    ld (Sel),hl
                    ld (Topo),hl
                    ld (Total),hl
                    ld a,'*'
                    ld hl,Cwd
                    rst 08h
                    db F_OPENDIR
                    ret c
                    ld (Handle),a
LPler               ld a,(Handle)
                    ld hl,TMP
                    rst 08h
                    db F_READDIR
                    jr c,LPfim
                    or a
                    jr z,LPfim
                    ld a,(TMP+1)        ; "." e ".."
                    cp '.'
                    jr z,LPler
                    ld hl,(NReg)
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,BUF
                    add hl,de
                    push hl
                    ld d,h
                    ld e,l
                    inc de
                    ld (hl),0
                    ld bc,63
                    ldir
                    pop ix
                    ld a,(TMP)          ; atributos: 10h = pasta
                    and 10h
                    jr z,LPf
                    ld (ix+1),1
LPf                 push ix
                    pop de
                    ld hl,4
                    add hl,de
                    ex de,hl            ; de = registo+4
                    ld hl,TMP+1
                    ld b,12
LPn                 ld a,(hl)
                    or a
                    jr z,LPnf
                    ld (de),a
                    ld (ix+17),a        ; nome grande = 8.3
                    inc ix
                    inc hl
                    inc de
                    djnz LPn
LPnf                ld hl,(NReg)
                    inc hl
                    ld (NReg),hl
                    ld (Total),hl
                    ld de,MAXREC
                    or a
                    sbc hl,de
                    jr nz,LPler
LPfim               ld a,(Handle)
                    rst 08h
                    db F_CLOSE
                    ret

; ---------------------------------------------------------------------------
; Correr um ficheiro com o plugin da extensao

Corre               ld de,TNome         ; copia o nome 8.3 para o trampolim
                    ld bc,13
                    push hl
                    ldir
                    pop hl
                    ld b,9              ; procura o ponto
COponto             ld a,(hl)
                    or a
                    jr z,COsemext
                    inc hl
                    cp '.'
                    jr z,COext
                    djnz COponto
COsemext            ld hl,TxtSemExt
                    jp Mensagem
COext               ld de,TPlugin+14    ; "/BIN/BPLUGINS/" + EXT
                    ld ix,TCfgNome+18   ; "/BIN/BPLUGINS/CFG/" + EXT + ".CFG"
                    ld b,3
COe                 ld a,(hl)
                    or a
                    jr z,COefim
                    cp 'a'
                    jr c,COeM
                    sub 20h
COeM                ld (de),a
                    ld (ix+0),a
                    ld (Ext),a          ; (so' para a mensagem)
                    inc hl
                    inc de
                    inc ix
                    djnz COe
COefim              xor a
                    ld (de),a
                    ld (ix+0),'.'
                    ld (ix+1),'C'
                    ld (ix+2),'F'
                    ld (ix+3),'G'
                    ld (ix+4),a
                    ld a,(Esta128)      ; no TC2068: /BIN/PLUG2068/EXT se existir (plugins so' do 2068)
                    cp 2
                    jr nz,COplug
                    ld hl,TxtP68
                    call COcopia
                    ld hl,TPlugin
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jr c,COsem68
                    rst 08h
                    db F_CLOSE
                    jr COplug
COsem68             ld hl,TCfgNome+5    ; nao ha': o de /BIN/BPLUGINS/
                    call COcopia
                    jr COplug
COcopia             ld de,TPlugin+5
                    ld bc,8
                    ldir
                    ret
COplug              call MusCala        ; v20: o plugin fica com o AY (a musica volta depois)
                    ld a,(NMI_7FFD)     ; bloco de parametros
                    ld (TParam),a
                    ld a,1
                    ld (TParam+1),a
                    ld a,(EspModo)      ; v25: pedido pelo ESP: nada no ecra
                    or a
                    jr nz,COsemmsg
                    ld hl,TxtACorrer
                    call MensagemSoEcra
COsemmsg            call SaiNav         ; o plugin abre o ficheiro pelo nome: pasta verdadeira
                    di
                    im 1
                    ld a,(Iguardado)
                    ld i,a
                    IF HIRES
                    call EcraPlugin     ; ecra normal e o F3 da maquina para o plugin
                    ENDIF
                    call TLanca
                    ld (RetPlugin),a
                    ld a,(EspModo)      ; v25: pedido pelo ESP: volta logo ao programa
                    or a
                    jp nz,EspFeito
                    ld a,(RetPlugin)
                    and 20h             ; o plugin pede para sair do navegador (TAP no TC2068)
                    jp nz,Sai
                    xor a               ; apaga o "A carregar..."
                    ld (MsgEstado),a
                    IF HIRES
                    call EntraHires
                    ld a,'*'            ; a pasta actual de novo (Cwd fica em F800h)
                    ld hl,Cwd
                    rst 08h
                    db F_GETCWD
                    ENDIF
                    call InstalaIM2
                    ld a,(Modo)         ; o plugin pode ter usado A3E0h-FFFFh
                    or a
                    jr nz,COlista
                    IF HIRES
                    call Recarrega      ; hi-res: tambem NAV.IDX, as pastas e a coluna das letras
                    ELSE
                    call EntraNav
                    call CarregaBloco
                    ENDIF
                    jr COdes
COlista             ld hl,(Sel)         ; a lista sem indice e' lida de novo: manter a posicao
                    push hl
                    call LePasta
                    pop hl
                    ld (Sel),hl
                    call AjustaTopo
COdes
                    call DesenhaTudo
                    ld a,(RetPlugin)
                    cp 0FFh
                    jr z,COsemplug
                    and 8               ; o plugin pediu o ficheiro seguinte/anterior?
                    jr z,COtem
                    call Navega
                    jr c,COtem          ; nao ha mais: fica
                    call RegSel
                    jr c,COtem
                    inc hl
                    inc hl
                    inc hl
                    inc hl
                    jp Corre
COsemplug           ld a,0FFh
                    cp 0FFh
                    jr nz,COtem
                    ld hl,TxtSemPlugin
                    jp Mensagem
COtem               ld a,(RetPlugin)
                    and 128+16          ; erro ou mensagem?
                    ret z
                    ld hl,TMsg
                    ld a,(hl)
                    or a
                    jp nz,Mensagem
                    ld a,(RetPlugin)
                    and 128
                    ret z
                    ld hl,TxtErroPlugin
                    jp Mensagem

; PLUGIN_NAVIGATE: procura no bloco carregado o ficheiro com a mesma extensao
; (TPlugin+14) na direccao de TNav (1 seguinte, 2 anterior, 3 primeiro, 4 ultimo).
; Muda Sel e redesenha. Carry = nao encontrou.
Navega              ld a,(TNav)
                    cp 3
                    jr nz,NV1
                    ld hl,0FFFFh        ; primeiro: comeca antes do 0 e anda para a frente
                    ld a,1
                    jr NVini
NV1                 cp 4
                    jr nz,NV2
                    ld hl,(Total)       ; ultimo: comeca depois do fim e anda para tras
                    ld a,2
                    jr NVini
NV2                 ld hl,(Sel)
NVini               ld (NavDir),a
NVciclo             ld a,(NavDir)
                    cp 2
                    jr z,NVtras
                    cp 1
                    scf
                    ret nz
                    inc hl
                    ld de,(Total)
                    or a
                    sbc hl,de
                    add hl,de
                    ccf
                    ret c               ; passou do fim
                    jr NVtesta
NVtras              ld a,h
                    or l
                    scf
                    ret z               ; ja' no 0
                    dec hl
NVtesta             ld (NumTmp),hl
                    call RegNum
                    jr c,NVprox         ; fora do bloco carregado
                    push hl
                    pop ix
                    ld a,(ix+1)         ; pastas nao
                    or a
                    jr nz,NVprox
                    ld de,4             ; extensao do 8.3
                    add hl,de
                    ld b,9
NVp                 ld a,(hl)
                    or a
                    jr z,NVprox
                    inc hl
                    cp '.'
                    jr z,NVext
                    djnz NVp
                    jr NVprox
NVext               ld de,TPlugin+14
                    ld b,4              ; 3 letras e o 0
NVc                 ld a,(hl)
                    cp 'a'
                    jr c,NVm
                    sub 20h
NVm                 ex de,hl
                    cp (hl)
                    ex de,hl
                    jr nz,NVprox
                    or a
                    jr z,NVachou
                    inc hl
                    inc de
                    djnz NVc
NVachou             ld hl,(NumTmp)
                    ld (Sel),hl
                    call AjustaTopo
                    call DesenhaPaineis
                    or a
                    ret
NVprox              ld hl,(NumTmp)
                    jr NVciclo

; ---------------------------------------------------------------------------
; Ecra

DesenhaTudo         call LimpaEcra
                    call DesenhaTopo
                    call DesenhaFiltro
                    IF HIRES
                    call DesenhaPastas
                    ENDIF
                    jr DesenhaPaineis
                    IF HIRES
LimpaEcra           ld hl,4000h         ; limpa 4000h-5AFFh (com as marcas de invertido) e 6000h-77FFh
                    ld de,4001h
                    ld bc,1AFFh
                    ld (hl),l
                    ldir
                    ld hl,6000h
                    ld de,6001h
                    ld bc,17FFh
                    ld (hl),l
                    ldir
                    ld a,(MudouFF)      ; bit 7 (DOCK/EXROM) como estava
                    or a
                    jr z,LEff
                    ld a,(PortaFF)
                    and 80h
LEff                or HIRESFF
                    out (0FFh),a
                    ret
                    ELSE
LimpaEcra           di                  ; limpa 4000h-5AFFh com PUSH (4x mais rapido que LDIR)
                    ld (DTsp+1),sp
                    ld sp,5B00h
                    ld hl,0
                    ld b,6912/32
DTl1                rept 16
                    push hl
                    endr
                    djnz DTl1
DTsp                ld sp,0
                    ei
                    ld a,1              ; borda azul
                    out (0FEh),a
                    ret
                    ENDIF
DesenhaPaineis      call DesenhaLetras
                    call DesenhaFicheiros
                    call DesenhaEmblema
                    jp DesenhaEstado

DesenhaTopo         ld d,0
                    ld e,0
                    ld b,32
                    ld a,A_TOPO
                    call Atrib
                    ld hl,Cwd           ; mostra o fim do caminho se for comprido
                    push hl
                    call Comprimento
                    pop hl
                    IF HIRES
                    sub 47              ; hi-res: maquina em 0-15, caminho em 17-63
                    ELSE
                    sub 25
                    ENDIF
                    jr c,DTcabe
                    ld e,a
                    ld d,0
                    add hl,de
DTcabe              ld d,0
                    IF HIRES
                    ld e,17
                    ld b,47
                    ELSE
                    ld e,0
                    ld b,24
                    ENDIF
                    jp Escreve

                    IF HIRES
DesenhaFiltro       ld a,(Filtro)       ; hi-res: a maquina no inicio da linha de cima
                    ld hl,TxtFiltros
                    dec a
                    jr z,DFHn
                    ld b,a
DFHs                ld a,(hl)
                    inc hl
                    or a
                    jr nz,DFHs
                    djnz DFHs
DFHn                ld a,(F3extra)      ; Pentagon (F3 bit 7)
                    rla
                    jr nc,DFHp
                    ld hl,TxtPentaNome
                    ld a,(F3extra)      ; v23: com o bit 3 e' o Pentagon 1024
                    and 8
                    jr z,DFHp
                    ld hl,TxtP1024Nome
DFHp                ld d,0
                    ld e,0
                    ld b,16
                    call Escreve
                    ld d,0
                    ld e,0
                    ld b,8
                    ld a,(Foco)
                    cp 2
                    ld a,A_TOPO
                    jp nz,Atrib
                    ld a,A_BARRASEL
                    jp Atrib
                    ELSE
DesenhaFiltro       ld d,1
                    ld e,0
                    ld b,32
                    ld a,A_BARRA
                    call Atrib
                    ld hl,TxtVazio
                    ld d,1
                    ld e,0
                    ld b,32
                    call Escreve
                    ld a,(Filtro)       ; nome da maquina
                    ld hl,TxtFiltros
                    dec a
                    jr z,DFn
                    ld b,a
DFs                 ld a,(hl)
                    inc hl
                    or a
                    jr nz,DFs
                    djnz DFs
DFn                 ld a,(F3extra)      ; Pentagon (F3 bit 7)
                    rla
                    jr nc,DFp
                    ld hl,TxtPentaNome
                    ld a,(F3extra)      ; v23: com o bit 3 e' o Pentagon 1024
                    and 8
                    jr z,DFp
                    ld hl,TxtP1024Nome
DFp                 ld d,1
                    ld e,0
                    ld b,11
                    call Escreve
                    ld a,(Modo)
                    or a
                    jr z,DFattr
                    ld hl,TxtSemIndice
                    ld d,1
                    ld e,12
                    ld b,20
                    call Escreve
DFattr              ld d,1
                    ld e,0
                    ld b,11
                    ld a,(Foco)         ; na barra (joystick): a piscar
                    cp 2
                    ld a,A_BARRASEL
                    jp nz,Atrib
                    or 80h
                    jp Atrib
                    ENDIF

; ---------------------------------------------------------------------------
; Menu das maquinas (ENTER na barra de cima). 7/6 ou joystick, ENTER escolhe, ESPACO volta.
NMENU               equ 7                   ; v24g: 6 maquinas a' esquerda (o Pentagon: 128 no clone,
MNESQ               equ 6                   ; 1024 com os 16 cores na Tang) e o GS a' direita (so' na Tang)
Menu                call VeTang         ; v24g: Tang (registo ZXUNO A3h = 54h) ou clone
                    ld hl,TxtP128
                    jr z,MNpn
                    ld hl,TxtP1024
MNpn                ld de,TabPenta
                    ld bc,14
                    ldir
                    ld a,(Filtro)
                    dec a
                    ld (MenuSel),a
MNdesenha           ld a,1              ; v19: o ENTER/fogo que abriu o menu tem de ser largado,
                    ld (Larga),a        ; senao escolhia logo a maquina e saia
                    call LimpaEcra
                    ld d,0
                    ld e,0
                    ld b,32
                    ld a,A_TOPO
                    call Atrib
                    ld hl,TxtMenuTit
                    ld d,0
                    ld e,0
                    ld b,32
                    call Escreve
                    ld c,0              ; v24d: maquinas a' esquerda (uma por linha), extras a' direita
                    ld hl,TabMenu
MNlinha             push bc
                    ld a,c
                    call MNpos          ; D = linha, E = celula (0 ou 16)
                    push de
                    IF HIRES
                    sla e               ; 64 colunas
                    inc e
                    ld b,28
                    ELSE
                    inc e
                    ld b,14
                    ENDIF
                    call Escreve        ; nome
                    call SaltaTxt       ; (a descricao ja' nao aparece)
                    pop de
                    pop bc
                    push hl
                    push bc
                    ld a,(MenuSel)
                    cp c
                    ld a,A_FICH
                    jr nz,MNcor
                    ld a,A_SEL
MNcor               ld b,16
                    call Atrib
                    pop bc
                    pop hl
                    inc c
                    ld a,c
                    cp MNESQ            ; v24g: o GS so' na Tang
                    jr nz,MNnx
                    ld a,(EhTang)
                    or a
                    jr z,MNfim
                    ld a,c
MNnx                cp NMENU
                    jr c,MNlinha
MNfim
                    ld d,23
                    ld e,0
                    ld b,32
                    ld a,A_ESTADO
                    call Atrib
                    ld hl,TxtMenuAj
                    ld d,23
                    ld e,0
                    ld b,32
                    call Escreve
MNtecla             call LeTecla
                    or a
                    IF HIRES
                    jr nz,MNtk
                    ld a,1
                    ld (NoMenu),a
                    call Pisca
                    jr MNtecla
MNtk                push af
                    call PiscaFim
                    pop af
                    ELSE
                    jr z,MNtecla
                    ENDIF
                    cp '7'
                    jr z,MNcima
                    cp '6'
                    jr z,MNbaixo
                    cp '8'
                    jr z,MNdir
                    cp '5'
                    jr z,MNesqk
                    cp 13
                    jr z,MNesc
                    cp ' '
                    jp z,MNsai
                    cp 3
                    jp z,MNsai
                    jr MNtecla
MNdir               ld a,(EhTang)       ; v24d: para a coluna da direita (o GS, so' na Tang)
                    or a
                    jr z,MNtecla
                    ld a,(MenuSel)
                    cp MNESQ
                    jr nc,MNtecla
                    ld (MNultesq),a
                    ld a,MNESQ
                    jr MNmuda
MNesqk              ld a,(MenuSel)      ; de volta a' maquina onde estava
                    cp MNESQ
                    jr c,MNtecla
                    ld a,(MNultesq)
                    jr MNmuda
MNcima              ld a,(MenuSel)
                    or a
                    jr z,MNtecla
                    cp MNESQ            ; a direita so' tem uma linha
                    jr z,MNtecla
                    dec a
                    jr MNmuda
MNbaixo             ld a,(MenuSel)
                    inc a
                    cp MNESQ
                    jr nc,MNtecla
; so' a cor das duas linhas que mudam (sem redesenhar o menu todo)
MNmuda              push af
                    ld a,(MenuSel)
                    ld c,A_FICH
                    call MNcorLinha
                    pop af
                    ld (MenuSel),a
                    ld c,A_SEL
                    call MNcorLinha
                    jp MNtecla
MNcorLinha          call MNpos          ; A = item do menu, C = cor
                    ld b,16
                    ld a,c
                    jp Atrib
; A = item -> D = linha, E = celula: maquinas (0..MNESQ-1) a' esquerda, o resto a' direita
MNpos               cp MNESQ
                    jr nc,MNpd
                    add a,3
                    ld d,a
                    ld e,0
                    ret
MNpd                sub MNESQ
                    add a,3
                    ld d,a
                    ld e,16
                    ret
SaltaTxt            ld a,(hl)
                    inc hl
                    or a
                    jr nz,SaltaTxt
                    ret
MNesc
MNmaq               xor a
                    ld (Foco),a
                    IF HIRES
                    ld (NoMenu),a
                    ENDIF
                    IF HIRES
                    call FocoBase
                    ENDIF
                    call DesenhaTudo    ; volta ao navegador e muda
                    ld a,(MenuSel)
                    inc a
                    cp 6
                    jr c,MNtroca
                    cp MNESQ+1          ; v24d: General Sound (nao e' maquina: carrega a ROM do GS)
                    jp z,CarregaGS
                    push af
                    call MusCala        ; v23: tambem calada ao mudar para o Pentagon
                    pop af
                    ld a,(EhTang)       ; clone: o Pentagon 128 (ZX 128K com o F3 bit 7)
                    or a                ; Tang: o Pentagon 1024 (+ F3 bit 3; o 1024K vem do DDh)
                    ld a,80h
                    jr z,MNp128
                    ld a,88h
MNp128              ld (NovaPenta),a
                    ld a,3
                    jp TMcomum
MNtroca             jp TrocaMaquina
MNsai
                    IF HIRES
                    xor a
                    ld (NoMenu),a
                    ENDIF
                    jp DesenhaTudo

; barra do filtro: esquerda/direita mudam, baixo/ENTER/ESPACO voltam as letras
ParaFiltro          ld a,2
                    ld (Foco),a
                    call DesenhaFiltro
                    jp DesenhaPaineis
SaiFiltro           xor a
                    ld (Foco),a
                    IF HIRES
                    call FocoBase
                    ENDIF
                    call DesenhaFiltro
                    jp DesenhaPaineis
; v14b: na barra, esquerda/direita ja' nao mudam a maquina (mudava-se sem querer e, de
; 128K para 48K, ficava logo a' espera do RESET+NMI). A maquina so' muda pelo menu (ENTER).
FiltroAnt
FiltroSeg           ret

DesenhaLetras
                    IF HIRES
                    ld a,(Ocultas)      ; pasta so' com um grupo: sem coluna das letras
                    or a
                    ret nz
                    ENDIF
                    ld c,0              ; linha 0..NLIN-1
DLciclo             push bc
                    ld a,(GTopo)
                    add a,c
                    ld b,a              ; b = posicao em Vis
                    ld a,c
                    add a,LIN0
                    ld d,a              ; d = linha do ecra
                    ld a,(NVis)
                    dec a
                    cp b
                    jr c,DLvazia
                    ld a,b
                    push de
                    push bc
                    call GrupoVis
                    ld (GrupoTmp),a
                    cp 2                ; grupos 2..27: " A".." Z" (feitos aqui)
                    jr c,GTtab
                    cp 28
                    jr nc,GTfim
                    add a,'A'-2
                    ld hl,GrTxt+2
                    ld (hl),0
                    dec hl
                    ld (hl),a
                    dec hl
                    ld (hl),' '
                    jr GTok
GTfim               sub 26              ; 28, 29 -> 2, 3 na tabela
GTtab               ld hl,TxtGrupos     ; 4 letras por grupo
                    add a,a
                    add a,a
                    ld e,a
                    ld d,0
                    add hl,de
GTok
                    pop bc
                    pop de
                    push bc
                    push de
                    ld e,0
                    ld b,3
                    call Escreve
                    pop de
                    push de
                    ld a,(Modo)         ; contagem
                    or a
                    jr nz,DLsemconta
                    ld a,(GrupoTmp)
                    call ContaGrupo
                    jr DLnum
DLsemconta          ld hl,(Total)
DLnum               pop de
                    push de
                    ld e,3
                    ld b,4
                    call EscreveNum
                    pop de
                    pop bc
                    ld a,(GSel)         ; cor
                    cp b
                    ld a,A_LETRA
                    jr nz,DLcor
                    ld a,(Foco)
                    or a
                    ld a,A_LETRASEL
                    jr z,DLcor
                    ld a,A_LETRASEL2
DLcor               ld e,0
                    ld b,LCEL
                    call Atrib
                    jr DLprox
DLvazia             ld hl,TxtVazio
                    ld e,0
                    ld b,8
                    call Escreve
                    ld e,0
                    ld b,LCEL
                    ld a,A_LETRA
                    call Atrib
DLprox              pop bc
                    inc c
                    ld a,c
                    cp NLIN
                    jp c,DLciclo
                    ret

DesenhaFicheiros    ld c,0
DFIciclo            call DFILinha
                    inc c
                    ld a,c
                    cp NLIN
                    jr c,DFIciclo
                    ret
; C = linha da lista (0..NLIN-1)
                    IF HIRES
DFILinha            push bc             ; hi-res: ">" nas pastas e o nome; a maquina vai para baixo
                    ld a,c
                    add a,LIN0
                    ld (LinhaTmp),a
                    ld hl,(Topo)
                    ld b,0
                    add hl,bc
                    ld (NumTmp),hl
                    ld de,(Total)
                    or a
                    sbc hl,de
                    jr nc,DFHvazia
                    ld hl,(NumTmp)
                    call RegNum
                    jr c,DFHvazia
                    push hl
                    pop ix
                    ld de,17            ; nome grande
                    add hl,de
                    push hl
                    ld a,(LinhaTmp)
                    ld d,a
                    ld a,(ColF)
                    ld e,a
                    ld a,(ix+1)
                    or a
                    ld a,' '
                    jr z,DFHm
                    ld a,'>'
DFHm                push de
                    call Letra
                    pop de
                    inc e
                    pop hl
                    ld a,64
                    sub e
                    ld b,a
                    call Escreve
                    ld b,A_FICH
                    ld hl,(NumTmp)      ; seleccionado: invertido
                    ld de,(Sel)
                    or a
                    sbc hl,de
                    jr nz,DFHc
                    ld a,(Foco)
                    cp 1
                    jr nz,DFHc
                    ld b,A_SEL
DFHc                ld a,b
                    jr DFHatr
DFHvazia            ld a,(LinhaTmp)
                    ld d,a
                    ld a,(ColF)
                    ld e,a
                    ld a,64
                    sub e
                    ld b,a
                    ld hl,TxtVazio
                    call Escreve
                    ld a,A_FICH
DFHatr              ld c,a
                    ld a,(LinhaTmp)
                    ld d,a
                    ld a,(ColF)
                    srl a
                    ld e,a
                    ld a,32
                    sub e
                    ld b,a
                    ld a,c
                    call Atrib
                    pop bc
                    ret
                    ELSE
DFILinha            push bc
                    ld a,c
                    add a,2
                    ld (LinhaTmp),a
                    ld hl,(Topo)
                    ld b,0
                    add hl,bc
                    ld (NumTmp),hl
                    ld de,(Total)
                    or a
                    sbc hl,de
                    jp nc,DFIvazia
                    ld hl,(NumTmp)
                    call RegNum
                    jp c,DFIvazia
                    push hl
                    pop ix
                    ld de,17            ; nome grande
                    add hl,de
                    ld a,(LinhaTmp)
                    ld d,a
                    ld e,8
                    ld b,17
                    call Escreve
                    ld a,(ix+1)
                    or a
                    jr z,DFItag
                    ld hl,TxtPastaTag
                    ld a,A_PASTA
                    ld (CorTmp),a
                    jr DFIescreve
DFItag              ld a,(ix+0)         ; etiqueta da maquina
                    and 7Fh
                    cp 6
                    jr c,DFIm
                    xor a
DFIm                ld e,a
                    ld d,0
                    ld hl,TabCorMaq
                    add hl,de
                    ld a,(hl)
                    ld (CorTmp),a
                    ld a,e
                    add a,a
                    add a,a
                    add a,a
                    ld e,a
                    ld hl,TxtMaq        ; 8 letras por maquina
                    add hl,de
DFIescreve          ld a,(LinhaTmp)
                    ld d,a
                    ld e,27
                    ld b,5
                    call Escreve
                    ld a,(ix+0)         ; palpite: "?"
                    and 80h
                    jr z,DFIcor
                    ld a,(ix+1)
                    or a
                    jr nz,DFIcor
                    ld a,(LinhaTmp)
                    ld d,a
                    ld e,26
                    ld a,'?'
                    call Letra
DFIcor              ld a,(ix+1)
                    or a
                    ld a,A_FICH
                    jr z,DFIc1
                    ld a,A_PASTA
DFIc1               ld b,a
                    ld hl,(NumTmp)      ; seleccionado?
                    ld de,(Sel)
                    or a
                    sbc hl,de
                    jr nz,DFIc2
                    ld a,(Foco)
                    cp 1
                    jr nz,DFIc2
                    ld b,A_SEL
                    ld a,b
                    ld (CorTmp),a
DFIc2               ld a,(LinhaTmp)
                    ld d,a
                    ld e,8
                    ld a,b
                    ld b,19
                    call Atrib
                    ld a,(LinhaTmp)
                    ld d,a
                    ld e,27
                    ld b,5
                    ld a,(CorTmp)
                    call Atrib
                    jr DFIprox
DFIvazia            ld a,(LinhaTmp)
                    ld d,a
                    ld e,8
                    ld b,24
                    ld hl,TxtVazio
                    call Escreve
                    ld a,(LinhaTmp)
                    ld d,a
                    ld e,8
                    ld b,24
                    ld a,A_FICH
                    call Atrib
DFIprox             pop bc
                    ret
                    ENDIF

; emblema da maquina do ficheiro seleccionado (canto de cima)
                    IF HIRES
DesenhaEmblema      ret                 ; hi-res: a maquina esta' na linha de baixo
                    ELSE
DesenhaEmblema      ld d,0
                    ld e,24
                    ld b,8
                    ld a,A_TOPO
                    call Atrib
                    ld hl,TxtVazio
                    ld d,0
                    ld e,24
                    ld b,8
                    call Escreve
                    ld a,(Foco)
                    cp 1
                    ret nz
                    call RegSel
                    ret c
                    push hl
                    pop ix
                    ld a,(ix+1)
                    or a
                    ret nz
                    ld a,(ix+0)
                    and 7Fh
                    ret z               ; desconhecida: nada
                    cp 6
                    ret nc
                    ld c,a              ; emblema: 4 riscas de cor + "48K" nos ZX, faixa nos outros
                    add a,a
                    add a,a
                    add a,a
                    ld e,a
                    ld d,0
                    ld hl,TxtEmblema
                    add hl,de
                    ld d,0
                    ld e,24
                    ld b,8
                    call Escreve
                    ld b,0
                    ld hl,TabCorEmb-1
                    add hl,bc
                    ld a,(hl)
                    ld d,0
                    ld e,24
                    ld b,8
                    push bc
                    call Atrib
                    pop bc
                    ld a,c
                    cp 4                ; Timex e outra: sem riscas
                    ret nc
                    ld hl,TabArco       ; ZX: vermelho, amarelo, verde, ciano
                    ld de,5800h+24
                    ld bc,4
                    ldir
                    ret
                    ENDIF

                    IF HIRES
DesenhaEstado       ld d,23             ; hi-res: mensagem, ou a maquina e o nome 8.3 do seleccionado
                    ld e,0
                    ld b,32
                    ld a,A_ESTADO
                    call Atrib
                    ld hl,MsgEstado
                    ld a,(hl)
                    or a
                    jr nz,DEHmsg
                    ld hl,TxtAjuda
                    ld a,(Foco)
                    cp 1
                    jr nz,DEHmsg
                    call RegSel
                    jr c,DEHaj
                    push hl
                    pop ix
                    ld hl,TxtPastaTag
                    ld a,(ix+1)
                    or a
                    jr nz,DEHinf
                    ld a,(ix+0)
                    and 7Fh
                    cp 6
                    jr c,DEHm
                    xor a
DEHm                add a,a
                    add a,a
                    add a,a
                    ld e,a
                    ld d,0
                    ld hl,TxtMaq
                    add hl,de
DEHinf              ld d,23
                    ld e,0
                    ld b,8
                    call Escreve
                    ld a,(ix+0)         ; palpite: "?"
                    and 80h
                    ld a,' '
                    jr z,DEHp
                    ld a,'?'
DEHp                ld d,23
                    ld e,8
                    call Letra
                    push ix
                    pop hl
                    inc hl
                    inc hl
                    inc hl
                    inc hl              ; nome 8.3
                    ld d,23
                    ld e,9
                    ld b,43
                    call Escreve
                    jr DEHnum
DEHaj               ld hl,TxtAjuda
DEHmsg              ld d,23
                    ld e,0
                    ld b,52
                    call Escreve
DEHnum              ld hl,(Total)       ; "sel/total"
                    ld a,h
                    or l
                    ret z
                    ld hl,(Sel)
                    inc hl
                    ld d,23
                    ld e,52
                    ld b,5
                    call EscreveNum
                    ld d,23
                    ld e,57
                    ld a,'/'
                    call Letra
                    ld hl,(Total)
                    ld d,23
                    ld e,58
                    ld b,5
                    jp EscreveNum
                    ELSE
DesenhaEstado       ld d,23
                    ld e,0
                    ld b,32
                    ld a,A_ESTADO
                    call Atrib
                    ld hl,MsgEstado
                    ld a,(hl)
                    or a
                    jr nz,DEmsg
                    ld hl,TxtAjuda
DEmsg               ld d,23
                    ld e,0
                    ld b,21
                    call Escreve
                    ld hl,(Total)       ; "sel/total"
                    ld a,h
                    or l
                    jr z,DEsemnum
                    ld hl,(Sel)
                    inc hl
                    ld d,23
                    ld e,21
                    ld b,5
                    call EscreveNum
                    ld d,23
                    ld e,26
                    ld a,'/'
                    call Letra
                    ld hl,(Total)
                    ld d,23
                    ld e,27
                    ld b,5
                    jp EscreveNum
DEsemnum            ld hl,TxtVazio
                    ld d,23
                    ld e,21
                    ld b,11
                    jp Escreve
                    ENDIF

; mensagem na linha de baixo (fica ate' a' tecla seguinte)
Mensagem            call MensagemSoEcra
                    ret
MensagemSoEcra      ld de,MsgEstado
                    ld b,52
MScp                ld a,(hl)
                    ld (de),a
                    or a
                    jr z,MSfim
                    inc hl
                    inc de
                    djnz MScp
                    xor a
                    ld (de),a
MSfim               jp DesenhaEstado

; ---------------------------------------------------------------------------
; Escrita em 64 colunas

; HL = texto (0 no fim), D = linha, E = coluna, B = largura (enche com espacos).
; No fim HL aponta para depois do 0 (ou para a letra seguinte se cortou), E += largura.
Escreve             ld a,b
                    ld (EsLarg),a
                    push hl
                    push bc
                    call PosEcra
                    pop bc
                    pop hl
EsCiclo             ld a,(hl)
                    or a
                    jr z,EsEsp
                    inc hl
                    push hl
                    push de
                    push bc
                    call PoeLetra       ; (mexe em A, C, DE, HL)
                    pop bc
                    pop de
                    pop hl
                    djnz EsCiclo
EsSalta             ld a,(hl)           ; cortou: salta o resto
                    inc hl
                    or a
                    jr nz,EsSalta
                    jr EsFim
EsEsp               inc hl
                    push hl
EsEsp2              call PoeEspaco      ; (so' mexe em A, HL)
                    djnz EsEsp2
                    pop hl
EsFim               ld a,(EsLarg)
                    add a,e
                    ld e,a
                    ret

; HL = numero, D,E = linha,coluna, B = largura (alinhado a' direita)
EscreveNum          push de
                    push bc
                    ld de,NumTxt+5
                    xor a
                    ld (de),a
ENc                 dec de
                    push de
                    ld c,10
                    call Div8
                    pop de
                    add a,'0'
                    ld (de),a
                    ld a,h
                    or l
                    jr nz,ENc
                    ld hl,NumTxt+5
                    or a
                    sbc hl,de           ; l = digitos
                    pop bc
                    ld a,b
                    sub l               ; espacos
                    ld c,l
                    pop hl              ; h = linha, l = coluna
                    push de
                    ld d,h
                    ld e,l
                    jr c,ENsem
                    jr z,ENsem
                    ld b,a
ENesp               push bc
                    push de
                    ld a,' '
                    call Letra
                    pop de
                    pop bc
                    inc e
                    djnz ENesp
ENsem               pop hl
                    ld b,c
                    jp Escreve

; HL = HL / C, A = resto
Div8                xor a
                    ld b,16
DVc                 add hl,hl
                    rla
                    cp c
                    jr c,DVn
                    sub c
                    inc l
DVn                 djnz DVc
                    ret

                    IF HIRES
; Hi-res do Timex (512x192): coluna par no banco 4000h, impar no 6000h, um byte por
; letra. O "atributo" em 5800h (que o hi-res nao mostra) diz se a celula (2 colunas)
; esta' invertida: bits 4-5 diferentes de 0 = invertido.

; A = letra, D = linha (0-23), E = coluna (0-63)
Letra               push af
                    call PosEcra
                    pop af
                    jr PoeLetra

; D = linha, E = coluna -> EsEcra (banco 4000h), EsAttr, EsImpar, EsMasc. Nao mexe em B, C, D, E.
PosEcra             push bc
                    ld a,e
                    and 1
                    ld (EsImpar),a
                    ld a,d
                    rrca
                    rrca
                    rrca
                    ld c,a
                    and 0E0h
                    ld l,a
                    ld a,e
                    srl a
                    or l
                    ld l,a
                    ld a,d
                    and 18h
                    or 40h
                    ld h,a
                    ld (EsEcra),hl
                    ld a,c
                    and 03h
                    or 58h
                    ld h,a
                    ld (EsAttr),hl
                    pop bc
                    jr PEmasc

; A = letra: desenha na posicao actual e avanca uma coluna (mexe em A, C, DE, HL)
PoeLetra            sub 32
                    jr c,PoeEspaco
                    jr z,PoeEspaco
                    cp 96
                    jr nc,PoeEspaco
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,Fonte
                    add hl,de
                    ex de,hl            ; de = desenho (Fonte alinhada a 8: basta inc e)
                    ld hl,(EsEcra)
                    ld a,(EsImpar)
                    or a
                    jr z,PL0
                    set 5,h
PL0                 ld a,(EsMasc)
                    ld c,a
                    ld b,8              ; (quem chama guarda o B)
PLc                 ld a,(de)
                    xor c
                    ld (hl),a
                    inc e
                    inc h
                    djnz PLc
                    jr Avanca
PoeEspaco           ld hl,(EsEcra)      ; (mexe em A, HL)
                    ld a,(EsImpar)
                    or a
                    jr z,PE0
                    set 5,h
PE0                 ld a,(EsMasc)
                    rept 7
                    ld (hl),a
                    inc h
                    endr
                    ld (hl),a
Avanca              ld a,(EsImpar)
                    xor 1
                    ld (EsImpar),a
                    ret nz              ; passou para a coluna impar: mesma celula
                    ld hl,EsEcra
                    inc (hl)
                    ld hl,(EsAttr)
                    inc l
                    ld (EsAttr),hl
PEmasc              ld a,(hl)
                    and 30h
                    jr z,PEm
                    ld a,0FFh
PEm                 ld (EsMasc),a
                    ret

; D = linha, E = celula (0-31), B = celulas, A = atributo.
; Guarda o atributo e inverte os pixeis das celulas que mudam de normal/invertido.
Atrib               ld c,a
                    ld a,d
                    rrca
                    rrca
                    rrca
                    ld l,a
                    and 03h
                    or 58h
                    ld h,a
                    ld a,l
                    and 0E0h
                    or e
                    ld l,a
ATc                 push bc
                    ld a,(hl)
                    and 30h
                    jr z,AT0
                    ld a,1
AT0                 ld b,a
                    ld a,c
                    and 30h
                    jr z,AT1
                    ld a,1
AT1                 xor b
                    ld (hl),c
                    call nz,ATinv
                    pop bc
                    inc hl
                    djnz ATc
                    ret
ATinv               push hl             ; hl = atributo -> as 8 linhas das 2 colunas
                    ld a,h
                    and 03h
                    rlca
                    rlca
                    rlca
                    or 40h
                    ld h,a
                    ld b,8
ATi                 ld a,(hl)
                    cpl
                    ld (hl),a
                    set 5,h
                    ld a,(hl)
                    cpl
                    ld (hl),a
                    res 5,h
                    inc h
                    djnz ATi
                    pop hl
                    ret

; A seleccao pisca sempre (no hi-res so' ha' normal/invertido: sozinha via-se mal).
; De 16 em 16 frames troca o invertido da zona seleccionada. PiscaFim deixa-a acesa.
Pisca               ld a,(Frames)       ; um frame novo?
                    ld hl,Fase
                    cp (hl)
                    ret z
                    ld (hl),a
                    ld hl,PCnt
                    dec (hl)
                    ret nz
                    ld a,(Apagada)
                    xor 1
                    ld (hl),8           ; apagada 8 frames
                    jr nz,PiscaPoe
                    ld (hl),24          ; acesa 24
                    jr PiscaPoe
PiscaFim            ld a,24             ; acesa ja', e a proxima troca so' daqui a 24 frames
                    ld (PCnt),a
                    xor a
PiscaPoe            ld (Apagada),a
                    call ZonaSel        ; D, E, B, C = cor seleccionada, A = cor normal
                    ret nc
                    ld c,a
                    ld a,(Apagada)
                    or a
                    ld a,c
                    jr nz,PPn
                    ld a,(CorSel)
PPn                 jp Atrib
; zona da seleccao -> carry, D = linha, E = celula, B = celulas, A = cor normal, (CorSel)
ZonaSel             ld a,(NoMenu)
                    or a
                    jr z,ZSnav
                    ld a,(MenuSel)      ; menu das maquinas
                    call MNpos
                    ld b,16
                    ld a,A_SEL
                    ld (CorSel),a
                    ld a,A_FICH
                    scf
                    ret
ZSnav               ld a,(Foco)
                    or a
                    jr nz,ZS1
                    ld a,(Ocultas)
                    or a
                    ret nz
                    ld a,(GTopo)
                    ld b,a
                    ld a,(GSel)
                    sub b
                    add a,LIN0
                    ld d,a
                    ld e,0
                    ld b,LCEL
                    ld a,A_LETRASEL
                    ld (CorSel),a
                    ld a,A_LETRA
                    scf
                    ret
ZS1                 cp 1
                    jr nz,ZS2
                    ld hl,(Total)
                    ld a,h
                    or l
                    ret z
                    ld hl,(Sel)
                    ld de,(Topo)
                    or a
                    sbc hl,de
                    ld a,l
                    add a,LIN0
                    ld d,a
                    ld a,(ColF)
                    srl a
                    ld e,a
                    ld a,32
                    sub e
                    ld b,a
                    ld a,A_SEL
                    ld (CorSel),a
                    ld a,A_FICH
                    scf
                    ret
ZS2                 cp 2
                    jr nz,ZS3
                    ld d,0
                    ld e,0
                    ld b,8
                    ld a,A_BARRASEL
                    ld (CorSel),a
                    ld a,A_TOPO
                    scf
                    ret
ZS3                 ld a,(PSel)         ; barra das pastas
                    add a,a
                    add a,a
                    ld e,a
                    ld d,LPAST
                    ld b,4
                    ld a,A_BARRASEL
                    ld (CorSel),a
                    ld a,A_BARRA
                    scf
                    ret

; depois de um plugin: le' tudo outra vez (o que esta' fora do codigo pode ter mudado)
; e volta a' mesma letra e ao mesmo ficheiro
Recarrega           ld hl,(Sel)
                    push hl
                    ld hl,(Topo)
                    push hl
                    ld a,(GSel)
                    push af
                    call LePastas
                    xor a
                    ld (MsgEstado),a
                    call EntraPasta     ; NAV.IDX, letras, VeLetras e desenha
                    pop af
                    ld (GSel),a
                    call AjustaGTopo
                    call CarregaGrupo
                    pop hl
                    ld (Topo),hl
                    pop hl
                    ld (Sel),hl
                    ld hl,(Total)       ; ficheiros: o foco volta para la'
                    ld a,h
                    or l
                    ret z
                    ld a,1
                    ld (Foco),a
                    ret

; F3 da maquina sem o bit 5: a FF aceita o modo hi-res (o bit 5 so' conta no Timmy)
EntraHires          ld a,(Filtro)
                    call ValorF3
                    and 0DFh
                    out (0F3h),a
                    ret

; FF que o programa tinha (ou 0 se a FF nao era do Timex), depois o F3 da maquina
SaiEcra             call SEf3
                    ld a,(MudouFF)
                    or a
                    jr z,SEff
                    ld a,(PortaFF)
SEff                out (0FFh),a
                    pop af
                    out (0F3h),a
                    ret
SEf3                pop bc              ; F3 sem o bit 5 (a FF tem de aceitar) e o F3 todo na pilha
                    ld a,(Filtro)       ; (o ValorF3 usa o HL: o regresso fica no BC)
                    call ValorF3
                    push af
                    and 0DFh
                    out (0F3h),a
                    push bc
                    ret

; antes de um plugin: ecra normal limpo, a FF so' com o bit 7 e o F3 da maquina
EcraPlugin          call LimpaEcra      ; CLS: os dois ecras (4000h e 6000h) limpos,
                    ld hl,5800h         ; atributos como o BASIC (papel branco, tinta preta)
                    ld de,5801h
                    ld bc,2FFh
                    ld (hl),38h
                    ldir
                    ld a,7              ; borda branca
                    out (0FEh),a
                    call SEf3
                    ld a,(MudouFF)
                    or a
                    jr z,SEff
                    ld a,(PortaFF)
                    and 80h
                    jr SEff

; pasta so' com um grupo (ou sem indice): sem coluna das letras, a lista usa a linha toda
VeLetras            ld a,(Modo)
                    or a
                    jr nz,VLsim
                    ld a,(NVis)
                    cp 2
                    jr nc,VLnao
VLsim               ld a,1
                    ld (Ocultas),a
                    xor a
                    ld (ColF),a
                    jr FocoBase
VLnao               xor a
                    ld (Ocultas),a
                    ld a,8
                    ld (ColF),a
; foco por defeito: as letras, ou os ficheiros se nao houver letras
FocoBase            xor a
                    ld (Foco),a
                    ld a,(Ocultas)
                    or a
                    ret z
                    ld hl,(Total)
                    ld a,h
                    or l
                    ret z
                    ld a,1
                    ld (Foco),a
                    ret

; Barra das pastas (linha LPAST = 1, em cima; ate' a v14b era a 22): /_NAV/PASTAS.IDX, registos de 64 bytes:
; 0-7 nome (ate' 6 letras), 8-63 caminho 8.3 a partir da raiz ("/DEMOS"). Ate' 8.
; Lido para TMP: carry = nao ha'. BC = bytes lidos.
AbrePastas          ld hl,TxtPastas
                    ld de,TMP
                    ld bc,512
                    jp LeFich
LePastas            xor a
                    ld (NPastas),a
                    ld (PSel),a
                    call AbrePastas
                    ret c
                    ld h,b              ; registos = bytes / 64
                    ld l,c
                    add hl,hl
                    add hl,hl
                    ld a,h
                    cp 9
                    jr c,LPqq
                    ld a,8
LPqq                or a
                    ret z
                    ld (NPastas),a
                    ld b,a
                    ld hl,TMP
                    ld de,PLab
LPreg               push bc
                    push hl
                    ld a,'['
                    ld (de),a
                    inc de
                    ld b,6
LPl                 ld a,(hl)
                    or a
                    jr z,LPff
                    ld (de),a
                    inc hl
                    inc de
                    djnz LPl
LPff                ld a,']'
                    ld (de),a
                    inc de
                    inc b               ; o resto do sitio (9 bytes) a zeros
LPz                 xor a
                    ld (de),a
                    inc de
                    djnz LPz
                    pop hl
                    ld bc,64
                    add hl,bc
                    pop bc
                    djnz LPreg
                    ret
DesenhaPastas       ld d,LPAST
                    ld e,0
                    ld b,32
                    ld a,A_BARRA
                    call Atrib
                    ld hl,TxtVazio
                    ld d,LPAST
                    ld e,0
                    ld b,64
                    call Escreve
                    ld a,(NPastas)
                    or a
                    ret z
                    ld b,a
                    ld c,0
                    ld hl,PLab
DPc                 push bc
                    push hl
                    ld a,c
                    add a,a
                    add a,a
                    add a,a
                    ld e,a
                    ld d,LPAST
                    ld b,8
                    call Escreve
                    pop hl
                    pop bc
                    push bc
                    push hl
                    ld a,(Foco)
                    cp 3
                    jr nz,DPn
                    ld a,(PSel)
                    cp c
                    jr nz,DPn
                    ld a,c
                    add a,a
                    add a,a
                    ld e,a
                    ld d,LPAST
                    ld b,4
                    ld a,A_BARRASEL
                    call Atrib
DPn                 pop hl
                    ld bc,9
                    add hl,bc
                    pop bc
                    inc c
                    djnz DPc
                    ret
ParaPastas          ld a,(NPastas)
                    or a
                    ret z
                    ld a,3
                    ld (Foco),a
                    call DesenhaFiltro  ; tira a marca da maquina, se estava la'
DPtudo              call DesenhaPastas
                    jp DesenhaPaineis
SaiPastas           call FocoBase
                    jr DPtudo
; v15: a barra das pastas fica em cima, entre a maquina (linha 0) e a lista
AcimaLista          ld a,(NPastas)
                    or a
                    jp nz,ParaPastas
                    jp ParaFiltro
FiltroBaixo         ld a,(NPastas)
                    or a
                    jp z,SaiFiltro
                    jp ParaPastas
PastasCima          ld a,2
                    ld (Foco),a
                    call DesenhaPastas
                    jp ParaFiltro
PastaAnt            ld a,(PSel)
                    or a
                    ret z
                    dec a
PAok                ld (PSel),a
                    jp DesenhaPastas
PastaSeg            ld a,(NPastas)
                    ld b,a
                    ld a,(PSel)
                    inc a
                    cp b
                    ret nc
                    jr PAok
EntraAtalho         call AbrePastas
                    jp c,ErroPasta
                    ld a,(PSel)         ; TMP + 64 x PSel + 8
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,TMP+8
                    add hl,de
                    push hl
                    call SaiNav
                    pop hl
                    ld a,'*'
                    rst 08h
                    db F_CHDIR
                    jp c,ErroPasta
                    jp EntraPasta

                    ELSE
; Ecra normal: 32 colunas x 24 linhas, letra 8x8 do ROM, cores pelos atributos.

; A = letra, D = linha (0-23), E = coluna (0-31)
Letra               push af
                    call PosEcra
                    pop af
                    jr PoeLetra

; D = linha, E = coluna -> EsEcra. Nao mexe em B, C, D, E.
PosEcra             ld a,d
                    rrca
                    rrca
                    rrca
                    and 0E0h
                    or e
                    ld l,a
                    ld a,d
                    and 18h
                    or 40h
                    ld h,a
                    ld (EsEcra),hl
                    ret

; A = letra: desenha na posicao actual e avanca uma coluna (mexe em A, DE, HL)
PoeLetra            sub 32
                    jr c,PoeEspaco
                    jr z,PoeEspaco
                    cp 96
                    jr nc,PoeEspaco
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,Fonte
                    add hl,de
                    ex de,hl            ; de = desenho (Fonte alinhada a 8: basta inc e)
                    ld hl,(EsEcra)
                    rept 7
                    ld a,(de)
                    ld (hl),a
                    inc e
                    inc h
                    endr
                    ld a,(de)
                    ld (hl),a
                    jr Avanca
PoeEspaco           ld hl,(EsEcra)      ; (mexe em A, HL)
                    xor a
                    rept 7
                    ld (hl),a
                    inc h
                    endr
                    ld (hl),a
Avanca              ld hl,EsEcra
                    inc (hl)
                    ret

; D = linha, E = celula (0-31), B = celulas, A = atributo
Atrib               push af
                    ld a,d
                    rrca
                    rrca
                    rrca
                    ld l,a
                    and 03h
                    or 58h
                    ld h,a
                    ld a,l
                    and 0E0h
                    or e
                    ld l,a
                    pop af
ATc                 ld (hl),a
                    inc hl
                    djnz ATc
                    ret


                    ENDIF

; Ha' registo do Timex na FFh? (no modo 128K do GO128 a FFh e' o barramento flutuante)
; Escreve dois valores e le-os de volta; se for, guarda o modo e passa ao ecra normal.
VeTimex             xor a
                    ld (MudouFF),a
                    in a,(0FFh)
                    ld (PortaFF),a      ; testa sempre (tambem diz se e' Timex ou ZX)
                                        ; os dois valores de teste sao ecra normal (modo 000):
                    and 80h             ; se ficarem escritos sem ser o Timex, nao estragam nada
                    or 38h
                    ld c,a
                    out (0FFh),a
                    in a,(0FFh)
                    cp c
                    jr nz,VTnao         ; nao e' o Timex
                    ld a,c
                    and 80h             ; ecra normal, cor 0, bit 7 como estava
                    ld c,a
                    out (0FFh),a
                    in a,(0FFh)
                    cp c
                    jr nz,VTnao
                    ld a,1              ; e' o Timex: a' saida repoe-se o modo antigo
                    ld (MudouFF),a
                    ret
VTnao               xor a               ; a leitura nao e' o registo (Spectrum, ou o Timmy num modo
                    out (0FFh),a        ; ZX com o barramento flutuante): FF = 0, como num ZX
                    inc a               ; (NZ)
                    ret

                    IF !HIRES
; Som de arranque. Em cada NMI: RET em FE00h (o NAV chama FE00h depois de desenhar a
; 1.a pasta). So' no 1.o NMI depois de ligar (a pagina 12 sem o filtro): carrega o
; /BIN/SOMNAV.BIN em BUF e corre-o; ele poe o leitor em FE00h e o /SYS/NAV.SOM nas
; paginas 13/14 do DivMMC. Sem os ficheiros fica o RET.
SomArranque         ld a,0C9h
                    ld (0FE00h),a
                    call LeFiltro
                    ld a,(Guardada)
                    or a
                    ret nz
                    ld hl,TxtSomNav
                    ld de,BUF
                    ld bc,800h
                    call LeFich
                    ret c
                    ld a,b
                    or c
                    ret z
                    jp BUF
TxtSomNav           db "/BIN/SOMNAV.BIN",0

; Timex (FF e' o registo do Timex, ou e' o Timmy num modo ZX, com o bit 5 do F3 a esconde-la):
; carrega o /BIN/NAVHR.BIN por cima deste e corre-o, como se fosse o NMI.SYS a chama-lo.
; Se nao der (Spectrum, ou nao ha' o ficheiro), volta e segue este.
VeHR                ld a,(MudouFF)
                    or a
                    jr nz,VHtem
                    xor a               ; F3 sem o bit 5: no Timmy a FF passa a aceitar
                    out (0F3h),a
                    ld c,06h
                    call VHtesta
                    jr nz,VHnao
                    ld c,00h
                    call VHtesta
VHnao               ld a,20h            ; esconde outra vez (o AcertaMaquina poe o F3 todo)
                    out (0F3h),a
                    ret nz
VHtem               ld hl,TxtNavHR
                    ld de,BUF
                    ld bc,CODE2MAX-84D0h
                    call LeFich
                    ret c
                    ld a,b
                    or c
                    ret z
                    ld (VHcp+1),bc
                    ld hl,(SPguardado)
                    ld (VHsp+1),hl
                    ld a,(MudouFF)      ; o modo de ecra do programa, para o NAVHR o guardar
                    or a
                    jr z,VHff
                    ld a,(PortaFF)
                    out (0FFh),a
VHff                ld hl,VHcod         ; copia no buffer da impressora (fora de 84D0h-A3DFh)
                    ld de,5B00h
                    ld bc,VHlen
                    ldir
                    jp 5B00h
VHtesta             ld a,c              ; Z = a FF guardou C (ecra normal ou hi-res: sem bit 7)
                    out (0FFh),a
                    in a,(0FFh)
                    cp c
                    ld a,0
                    out (0FFh),a
                    ret
VHcod               ld hl,BUF
VHcp                ld bc,0
                    ld de,84D0h
                    ldir
VHsp                ld sp,0
                    jp 84D0h
VHlen               equ $-VHcod
TxtNavHR            db "/BIN/NAVHR.BIN",0
                    ENDIF

; v25 (2026-10-22): ordem do ESP32 (caixa de correio do Timmy, portos EE3Bh / EF3Bh).
; O ESP mostra o cartao e as capas; quando se escolhe um ficheiro, guarda a ordem e faz um NMI.
; Aqui pergunta-se (comando 10h) se ha' ordem: [tipo][caminho 8.3 com 0 no fim]. Havendo,
; muda para a pasta e corre o ficheiro com o plugin, como o ENTER, sem desenhar nada; o plugin
; volta direito ao programa. Sem o ESP (o EE3Bh nao da' 1000 00xx) ou sem ordem: o NAV normal.
                    IF !HIRES           ; v25i: no NAVHR so' o EspHerda
EspOrdem            ld bc,0EE3Bh        ; v25g: sem o ESP (o clone, ou um Spectrum com barramento flutuante)
                    in a,(c)            ; a leitura pode dar qualquer coisa: so' conta se der 8 vezes o
                    ld d,a              ; mesmo valor 1000 00xx
                    ld l,1              ; (v25h: diagnostico para o ESP: o passo e o valor em EF3Bh)
                    and 0FCh
                    cp 80h
                    jr nz,EOdiag
                    ld e,8
                    ld l,2
EOigual             in a,(c)
                    cp d
                    jr nz,EOdiag
                    dec e
                    jr nz,EOigual
                    ld a,10h            ; "ha' ordem?"
                    out (c),a
                    in a,(c)            ; o pedido fica logo a' espera (bit 0) ou ja' respondido (bit 1)
                    ld l,3
                    ld d,a
                    and 0FCh
                    cp 80h
                    jr nz,EOdiag
                    ld de,0
                    jr EOespera
EOdiag              ld b,0EFh           ; escreve no pedido (o ESP le'-o em 80h se nao vier comando)
                    out (c),l
                    out (c),d
                    ret
EOespera            in a,(c)
                    bit 1,a             ; resposta pronta
                    jr nz,EOtem
                    dec de
                    ld a,d
                    or e
                    jr nz,EOespera
                    ret
EOtem               ld b,0EFh           ; EF3Bh: a resposta
                    in a,(c)
                    or a
                    ret z               ; nao ha' ordem
                    cp 2Fh              ; so' os tipos conhecidos: 1-6 e 7Fh (ficheiros), 20h-26h, 2Fh
                    jr z,EOtipo
                    cp 7Fh
                    jr z,EOtipo
                    cp 7
                    jr c,EOtipo
                    cp 20h
                    ret c
                    cp 20h+NMENU
                    ret nc
EOtipo              ld (EspTipo),a
                    ld hl,EspCam
                    ld e,63
EOc                 in a,(c)
                    ld (hl),a
                    inc hl
                    or a
                    jr z,EOfim
                    dec e
                    jr nz,EOc
                    ld (hl),0
                    ENDIF
EOfim               ld a,(EspTipo)      ; 2Fh: o NMI depois do RESET de uma mudanca de maquina pedida
                    cp 2Fh              ; pelo ESP: o NAV acaba-a como sempre e vai para o BASIC
                    jr nz,EOn2f
                    ld (EspSai),a
                    jr EOpassa
EOn2f               sub 20h             ; 20h-26h: a linha do menu das maquinas: o NAV arranca como
                    jr c,EOfich         ; sempre e faz como o ENTER no menu dele (sem a pergunta)
                    cp NMENU
                    jr nc,EOfich
                    inc a
                    ld (EspMaq),a
EOpassa
                    IF !HIRES
                    ld a,(EspTipo)      ; para o NAVHR.BIN (o VeHR carrega-o por cima deste): em 5BFEh
                    ld (5BFFh),a
                    ld a,'E'
                    ld (5BFEh),a
                    ENDIF
                    ret
; NAVHR.BIN: a ordem de maquina deixada pelo BROWSE.BIN em 5BFEh ('E') / 5BFFh (tipo)
EspHerda            ld a,(5BFEh)
                    cp 'E'
                    ret nz
                    xor a
                    ld (5BFEh),a
                    ld a,(5BFFh)
                    ld (EspTipo),a
                    jr EOfim
EOfich                                  ; v25i: um ficheiro: o NAV arranca como sempre (no Timex o NAVHR)
                    IF !HIRES           ; e no fim corre-o como o ENTER (EspCorre)
                    ld a,(EspCam)       ; o caminho comeca por '/' (no NAVHR pede-se outra vez ao ESP)
                    cp '/'
                    ret nz
                    ENDIF
                    ld a,1
                    ld (EspFich),a
                    jr EOpassa
; o ESP repete a ultima ordem (comando 12h): o caminho para o NAVHR
EspRepete           ld bc,0EE3Bh
                    ld a,12h
                    out (c),a
                    ld de,0
ERw                 in a,(c)
                    bit 1,a
                    jr nz,ERtem
                    dec de
                    ld a,d
                    or e
                    jr nz,ERw
                    ret
ERtem               ld b,0EFh
                    in a,(c)            ; o tipo
                    ld hl,EspCam
                    ld e,63
ERc                 in a,(c)
                    ld (hl),a
                    inc hl
                    or a
                    ret z
                    dec e
                    jr nz,ERc
                    ld (hl),0
                    ret
; o plugin voltou (A = o que devolveu): diz ao ESP (comando 13h; com o bit 5, TAP no TC2068,
; o ESP escreve LOAD "") e sai para o programa
EspFeito            ld a,(RetPlugin)
                    ld bc,0EF3Bh
                    out (c),a
                    ld b,0EEh
                    ld a,13h
                    out (c),a
                    ld de,0
EFw                 in a,(c)
                    bit 1,a
                    jr nz,EFsai
                    dec de
                    ld a,d
                    or e
                    jr nz,EFw
EFsai               jp Sai
EspCorre            ld a,(EspCam)       ; um ficheiro: o caminho comeca por '/'
                    cp '/'
                    ret nz
                    ld a,1
                    ld (EspModo),a
                    call LeFiltro       ; a maquina, como no arranque normal (plugins do TC2068)
                    call AcertaMaquina
                    ld hl,EspCam        ; DE = a ultima '/'
                    ld de,0
EObarra             ld a,(hl)
                    or a
                    jr z,EOfimb
                    cp '/'
                    jr nz,EOprox
                    ld d,h
                    ld e,l
EOprox              inc hl
                    jr EObarra
EOfimb              ld a,d
                    or e
                    ld hl,EspCam
                    jp z,Corre          ; sem pasta: na actual
                    push de
                    or a
                    sbc hl,de
                    ld hl,TxtBarra      ; "/NOME": a raiz
                    jr z,EOcd
                    pop de
                    push de
                    xor a
                    ld (de),a           ; "/PASTA/SUB" 0 "NOME"
                    ld hl,EspCam
EOcd                ld a,'*'
                    rst 08h
                    db F_CHDIR
                    pop hl
                    jp c,Sai
                    inc hl              ; o nome 8.3
                    jp Corre
EspModo             db 0
EspFich             db 0
EspTipo             db 0
EspSai              db 0
EspMaq              db 0
EspCam              ds 64

; HL = texto -> A = comprimento
Comprimento         ld b,0
CMc                 ld a,(hl)
                    or a
                    ld a,b
                    ret z
                    inc hl
                    inc b
                    jr CMc

LNavIdx             equ 8+58+6*58
FimCodigo
                    assert FimCodigo <= 09FFCh  ; 9FFCh-9FFFh: o filtro na pagina 12 (GFescreve)

; ---------------------------------------------------------------------------
; Trampolim: corre em A000h (o plugin so' usa 8000h-9FFFh e A3E0h-FFFFh).
; Guarda 8000h-9FFFh na pagina 12 do DivMMC, carrega o plugin em 8000h,
; chama-o e repoe tudo. A = flags do plugin (FFh = nao ha' plugin).
                    ds TRAMP-$          ; 9FFCh-9FFFh e o resto ate' A000h: zeros no ficheiro
TrampSrc
TLanca              ld a,80h+12
                    out (0E3h),a
                    ld hl,8000h
                    ld de,2000h
                    ld bc,2000h
                    ldir
                    ld a,80h+PAG2       ; e A3E0h-BBE1h (o plugin pode usar A3E0h-FFFFh)
                    out (0E3h),a
                    ld hl,CODE2
                    ld de,2000h
                    ld bc,LCODE2
                    ldir
                    ld a,80h+12
                    out (0E3h),a
                    call GFescreve      ; o filtro, para o proximo NMI (o jogo pode nao voltar)
                    xor a
                    out (0E3h),a
                    ld a,'$'
                    ld b,FA_READ
                    ld hl,TPlugin
                    rst 08h
                    db F_OPEN
                    jp c,TSem
                    ld (TH),a
                    ld hl,8000h
                    ld bc,2000h
                    rst 08h
                    db F_READ
                    push af
                    ld a,(TH)
                    rst 08h
                    db F_CLOSE
                    pop af
                    jp c,TSem
                    ld hl,0
                    ld (TDE),hl
                    ld a,'$'
                    ld b,FA_READ
                    ld hl,TCfgNome
                    rst 08h
                    db F_OPEN
                    jr c,TSemCfg
                    ld (TH),a
                    ld hl,TCfg
                    ld bc,16
                    rst 08h
                    db F_READ
                    ld a,(TH)
                    rst 08h
                    db F_CLOSE
                    ld hl,TCfg
                    ld (TDE),hl
TSemCfg             ld a,(8006h)        ; PLUGIN_FLAGS1_COPY_SETTINGS
                    and 1
                    jr z,TSemSet
                    ld hl,TSettings
                    ld de,8008h
                    ld bc,14
                    ldir
TSemSet             push ix
                    ld hl,TNome
                    ld bc,TParam
                    ld de,(TDE)
                    call 8000h
                    pop ix
                    ld (TRet),a
                    xor a               ; copia a mensagem (esta' no plugin)
                    ld (TMsg),a
                    ld (TNav),a
                    ld a,(TRet)         ; PLUGIN_NAVIGATE: BC = 1..4 (seguinte, anterior, primeiro, ultimo)
                    and 8
                    jr z,TMsgSim
                    ld a,c
                    ld (TNav),a
                    jr TRepoe
TMsgSim             ld a,b
                    or c
                    jr z,TRepoe
                    ld h,b
                    ld l,c
                    ld de,TMsg
                    ld b,42
TMc                 ld a,(hl)
                    ld (de),a
                    or a
                    jr z,TRepoe
                    inc hl
                    inc de
                    djnz TMc
                    xor a
                    ld (de),a
TRepoe              ld a,80h+12
                    out (0E3h),a
                    ld hl,2000h
                    ld de,8000h
                    ld bc,2000h
                    ldir
                    ld a,80h+PAG2
                    out (0E3h),a
                    ld hl,2000h
                    ld de,CODE2
                    ld bc,LCODE2
                    ldir
                    xor a
                    out (0E3h),a
                    ld a,(TRet)
                    ret
TSem                ld a,0FFh
                    ld (TRet),a
                    xor a
                    ld (TMsg),a
                    jr TRepoe

TH                  db 0
TRet                db 0
TNav                db 0
TDE                 dw 0
TParam              db 0,1
TSettings           db 0Fh,0Fh,1,0Fh,0Eh,28h,0,0,0,'7','6','5','8',13
TPlugin             db "/BIN/BPLUGINS/",0,0,0,0
TxtP68              db "PLUG2068"
TCfgNome            db "/BIN/BPLUGINS/CFG/",0,0,0,0,0,0,0,0
TNome               ds 14
TCfg                ds 16
TMsg                ds 44
TFim
TrampLen            equ $-TrampSrc
; depois do trampolim, ate' BUF (o plugin nao mexe em A000h-A3DFh)
NavIdx              equ TFim
PLab                equ NavIdx+LNavIdx      ; hi-res: 8 x 9 ("[DEMOS]",0,0)
NPastas             equ PLab+72
                    assert NPastas+1 <= CODE2
                    assert TrampSrc == TRAMP

; ---------------------------------------------------------------------------
; 2.a parte: A3E0h-BBE1h (no ficheiro; o trampolim guarda-a na pagina PAG2)
                    ds CODE2-$

                    IF !HIRES
; v21: ao entrar, o ecra que estava (o do jogo) desfaz-se aos quadrados de 8x8 ate' ficar
; preto: 768 quadrados por uma ordem baralhada (passo 509, primo com 768), 48 por passo,
; 16 passos de ~20 ms = 0,32 s. So' no BROWSE (o NAVHR comeca ja' com o ecra preto).
; O NMI.SYS ja' guardou o ecra: no fim o jogo volta como estava.
Desfaz              ld hl,0             ; quadrado (0-767)
                    ld c,16
DFpasso             ld b,48
DFq                 push bc
                    push hl
                    ld a,l              ; atributo: 5800h + quadrado
                    ld e,a
                    ld a,h
                    add a,58h
                    ld d,a
                    xor a
                    ld (de),a
                    ld a,l              ; pixeis: linha = quadrado/32, coluna = quadrado%32
                    and 1Fh
                    ld e,a
                    add hl,hl
                    add hl,hl
                    add hl,hl           ; H = linha (0-23)
                    ld a,h
                    and 07h
                    rrca
                    rrca
                    rrca
                    or e
                    ld e,a              ; E = (linha&7)<<5 | coluna
                    ld a,h
                    and 18h
                    or 40h
                    ld d,a              ; D = 40h | (linha&18h)
                    xor a
                    ld b,8
DFl                 ld (de),a
                    inc d
                    djnz DFl
                    pop hl
                    ld de,509           ; o quadrado seguinte
                    add hl,de
                    ld de,768
                    or a
                    sbc hl,de
                    jr nc,DFok
                    add hl,de
DFok                pop bc
                    djnz DFq
                    dec c               ; o ultimo quadrado: a borda passa a preto ja', sem esperar
                    jr z,DFfim
                    inc c
                    ld b,48             ; ~8 ms (as interrupcoes estao desligadas: espera a contar)
DFe1                push bc
                    ld b,40
DFe2                djnz DFe2
                    pop bc
                    djnz DFe1
                    dec c
                    jr nz,DFpasso
DFfim               xor a
                    out (0FEh),a
                    ret
                    ENDIF

; ---------------------------------------------------------------------------
; v20: musica de fundo. O leitor (/BIN/NAVPT3.BIN) e o modulo (/SYS/NAV.PT3, ou o .PT3 que se
; escolher com a tecla 0) ficam na pagina PMUS do DivMMC, mapeada em 2000h so' o tempo de
; tocar um frame (com DI: o leitor usa o SP). Nos NMI seguintes a musica continua de onde
; estava (3FF8h: "NVM", 3FFBh: ligada). Ao desligar a maquina volta a ser o /SYS/NAV.PT3.
; Os efeitos (o blip da gota) sao no altifalante: o AY fica so' para a musica.
PMUS                equ 41
MusPag              ld a,80h+PMUS
                    out (0E3h),a
                    ret
MusTira             xor a
                    out (0E3h),a
                    ret
MusArranca          xor a
                    ld (MusOk),a
                    di
                    call MusPag
                    ld hl,(2009h)
                    ld (MusMod),hl
                    ld hl,(3FF8h)       ; "NV"
                    ld de,"VN"
                    or a
                    sbc hl,de
                    jr nz,MAnao
                    ld a,(3FFAh)
                    cp "M"
                    jr nz,MAnao
                    ld a,(200Bh)
                    cp "N"
                    jr nz,MAnao
                    ld a,(3FFBh)        ; ja' estava a tocar: continua
                    ld (MusLiga),a
                    call MusTira
                    ei
                    ld a,1
                    ld (MusOk),a
                    ret
MAnao               call MusTira
                    ei
                    ld hl,TxtNavPt3     ; o leitor
                    ld de,2000h
                    ld bc,1F00h
                    call MusLe
                    ret c
                    di
                    call MusPag
                    ld hl,(2009h)
                    ld (MusMod),hl
                    ld a,(200Bh)
                    ld b,a
                    call MusTira
                    ei
                    ld a,b
                    cp "N"
                    ret nz
                    ld hl,TxtMusica     ; a musica
                    call MusModulo
                    ret c
                    ld a,1
                    ld (MusLiga),a
                    jp MusPronto
; HL = nome do .PT3 -> para o sitio do modulo e Init. Carry = nao deu (sem musica)
MusModulo           xor a
                    ld (MusOk),a
                    push hl
                    call MusAssina      ; (A = 0: assinatura invalida enquanto carrega)
                    pop hl
                    ld de,(MusMod)
                    push hl
                    ld hl,3FF8h
                    or a
                    sbc hl,de
                    ld b,h
                    ld c,l
                    pop hl
                    call MusLe
                    ret c
                    di
                    call MusPag
                    push ix
                    push iy
                    ld hl,(MusMod)
                    call 2000h          ; Inicia
                    pop iy
                    pop ix
                    call MusTira
                    ei
                    or a
                    ret
MusPronto           ld a,1
                    ld (MusOk),a
                    ld a,"M"
MusAssina           di                  ; A = "M": valida; 0: invalida
                    push af
                    call MusPag
                    pop af
                    ld (3FFAh),a
                    ld hl,"VN"
                    ld (3FF8h),hl
                    ld a,(MusLiga)
                    ld (3FFBh),a
                    call MusTira
                    ei
                    ret
; um frame da musica (se houver e estiver ligada)
MusToca             ld a,(MusOk)
                    or a
                    ret z
                    ld a,(MusLiga)
                    or a
                    ret z
                    ld a,2003h & 0FFh
                    jr MusChama
MusCala             ld a,1              ; v22: a interrupcao deixa de tocar (ate' ao LeTecla)
                    ld (MusPara),a
                    ld a,(MusOk)
                    or a
                    ret z
                    ld a,2006h & 0FFh
MusChama            ld (MCend+1),a
                    di
                    push ix
                    push iy
                    call MusPag
MCend               call 2003h
                    call MusTira
                    pop iy
                    pop ix
                    ei
                    ret
; le o ficheiro HL (pasta actual) para DE na pagina PMUS, BC bytes no maximo (aos bocados de
; 1K por TMP). Carry = nao abriu, erro, ou grande demais.
MusLe               ld (MLdest),de
                    ld (MLmax),bc
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (MLh),a
MLciclo             ld a,(MLh)
                    ld hl,TMP
                    ld bc,1024
                    rst 08h
                    db F_READ
                    jr c,MLerro
                    ld a,b
                    or c
                    jr z,MLfim
                    ld hl,(MLmax)
                    or a
                    sbc hl,bc
                    jr c,MLerro         ; nao cabe
                    ld (MLmax),hl
                    di
                    call MusPag
                    ld hl,TMP
                    ld de,(MLdest)
                    ldir
                    ld (MLdest),de
                    call MusTira
                    ei
                    jr MLciclo
MLfim               ld a,(MLh)
                    rst 08h
                    db F_CLOSE
                    or a
                    ret
MLerro              ld a,(MLh)
                    rst 08h
                    db F_CLOSE
                    scf
                    ret
; tecla 0: num .PT3 passa a ser a musica de fundo; noutro sitio liga/desliga
MusTecla            ld a,(MusMod+1)     ; sem leitor carregado: nada
                    cp 20h
                    ret c
                    call RegSel
                    jr c,MTliga
                    inc hl
                    ld a,(hl)           ; pasta?
                    or a
                    jr nz,MTliga
                    inc hl
                    inc hl
                    inc hl              ; nome 8.3
                    push hl
                    ld b,9
MTp                 ld a,(hl)
                    inc hl
                    cp '.'
                    jr z,MText
                    or a
                    jr z,MTnao
                    djnz MTp
MTnao               pop hl
                    jr MTliga
MText               ld de,TxtExtPt3
                    ld b,3
MTe                 ld a,(hl)
                    cp 'a'              ; maiusculas (so' as letras)
                    jr c,MTm
                    sub 20h
MTm
                    ex de,hl
                    cp (hl)
                    ex de,hl
                    jr nz,MTnao
                    inc hl
                    inc de
                    djnz MTe
                    pop hl
                    ld de,MusNome       ; o nome, fora do bloco dos registos
                    ld bc,13
                    ldir
                    ld a,(NaNav)
                    push af
                    call SaiNav         ; o ficheiro esta' na pasta, nao no _NAV
                    call MusCala
                    ld hl,MusNome
                    call MusModulo
                    push af
                    ld a,1
                    ld (MusLiga),a
                    pop af
                    ld hl,TxtMusGrande
                    jr c,MTmsg
                    call MusPronto
                    ld hl,TxtMusNova
MTmsg               pop af
                    push hl
                    or a
                    call nz,EntraNav
                    pop hl
                    jp Mensagem
MTliga              ld a,(MusOk)
                    or a
                    ret z
                    ld a,(MusLiga)
                    xor 1
                    ld (MusLiga),a
                    push af
                    call z,MCcala
                    ld a,"M"
                    call MusAssina
                    pop af
                    ld hl,TxtMusLig
                    jr nz,MTm2
                    ld hl,TxtMusDesl
MTm2                jp Mensagem
MCcala              ld a,2006h & 0FFh   ; cala ja' (MusCala ve' o MusLiga desligado: chama direto)
                    jp MusChama
TxtNavPt3           db "/BIN/NAVPT3.BIN",0
TxtMusica           db "/SYS/NAV.PT3",0
TxtExtPt3           db "PT3"
TxtMusNova          db "Musica de fundo: este PT3",0
TxtMusGrande        db "PT3 grande demais para musica",0
TxtMusLig           db "Musica ligada",0
TxtMusDesl          db "Musica desligada",0
MusOk               db 0
MusLiga             db 0
MusPara             db 1                ; v22: 1 = a interrupcao nao toca
MusMod              dw 0
MLdest              dw 0
MLmax               dw 0
MLh                 db 0
MusNome             ds 13

                    IF HIRES
; ---------------------------------------------------------------------------
; v16: a gota. Quando a marca muda de sitio (lista, letras, pastas, maquina, menu):
;  - se foi para a linha de cima ou de baixo na mesma coluna, a marca passa de uma para a
;    outra pela fronteira (3 frames: a velha encolhe, a nova cresce a partir do lado comum);
;  - depois a nova estica e encolhe como uma gota (13, 6, 11, 7, 9, 8 linhas de pixeis), cai
;    uma gotinha, e soa um "blip" no altifalante (v18; antes no AY). 6 frames.
; Nas repeticoes da tecla nao faz nada (andar depressa fica igual).
; Janela: 16 linhas de pixeis (3 acima da linha nova, 5 abaixo) ou 24 (as duas linhas),
; guardadas em GBuf (64 bytes por linha: 2 por celula, 4000h e 6000h).
GotaAntes           call ZonaSel
                    sbc a,a             ; FFh = ha' zona
                    ld (GotaOk),a
                    ld (GotaDE),de
                    ld a,b
                    ld (GotaB),a
                    ret
GotaDepois          ld a,(Repetiu)
                    or a
                    ret nz
                    call ZonaSel
                    ret nc
                    ld a,e
                    ld (GZcel),a
                    ld a,b
                    ld (GZn),a
                    ld a,d
                    ld (GZlin),a
                    xor a               ; sem passagem (so' a gota)
                    ld (GPassa),a
                    ld (GOff),a
                    ld a,16
                    ld (GRows),a
                    ld a,d
                    add a,a
                    add a,a
                    add a,a
                    ld (GTop8),a        ; linha de pixeis de cima da janela + 3
                    ld a,(GotaOk)
                    or a
                    jr z,GDvai
                    ld hl,(GotaDE)
                    ld a,h              ; mesma linha e celula: nada
                    cp d
                    jr nz,GDdif
                    ld a,l
                    cp e
                    ret z
GDdif               ld a,l              ; a passagem: mesma celula e largura, linha ao lado
                    cp e
                    jr nz,GDvai
                    ld a,(GotaB)
                    cp b
                    jr nz,GDvai
                    ld a,h
                    inc a
                    cp d
                    jr z,GDdesce        ; velha+1 = nova
                    dec a
                    dec a
                    cp d
                    jr nz,GDvai
                    ld a,0FFh           ; sobe: a velha e' a de baixo
                    ld (GPassa),a
                    jr GDj24
GDdesce             ld a,1
                    ld (GPassa),a
                    ld a,8              ; a janela comeca na velha: a nova esta' 8 abaixo
                    ld (GOff),a
                    ld a,h
                    add a,a
                    add a,a
                    add a,a
                    ld (GTop8),a
GDj24               ld a,24
                    ld (GRows),a
GDvai               ld c,0              ; guarda a janela: ecra -> GBuf
GDg                 push bc
                    call GLinhaEcra
                    jr nc,GDg1
                    push hl
                    ld a,c
                    call GLinhaBuf
                    ex de,hl
                    pop hl
                    call GCopiaET
GDg1                pop bc
GDg2                inc c
                    ld a,(GRows)
                    cp c
                    jr nz,GDg
                    ld a,(GOff)         ; a linha nova (marcada) -> GMarca; no GBuf fica desmarcada
                    add a,3
                    call GLinhaBuf
                    ld de,GMarca
                    ld bc,8*64
                    push hl
                    ldir
                    pop hl
                    ld c,8
GDdm                push hl
                    ld a,(GZn)
                    add a,a             ; os 2 bancos: 0-31 e 32-63
                    ld b,a
                    push bc
                    ld a,(GZn)
                    ld b,a
GDd1                ld a,(hl)
                    cpl
                    ld (hl),a
                    inc hl
                    djnz GDd1
                    pop bc
                    pop hl
                    push hl
                    ld de,32
                    add hl,de
                    ld a,(GZn)
                    ld b,a
GDd2                ld a,(hl)
                    cpl
                    ld (hl),a
                    inc hl
                    djnz GDd2
                    pop hl
                    ld de,64
                    add hl,de
                    dec c
                    jr nz,GDdm
                    ld a,(GPassa)       ; a passagem pela fronteira: x = 2, 4, 6
                    or a
                    jr z,GDgota
                    ld b,2
GDpas               push bc
                    ld c,3              ; as duas linhas (janela 3-18): o fundo
                    ld a,16
                    call GFundo
                    pop bc
                    push bc
                    ld a,(GPassa)
                    dec a
                    jr nz,GDsobe
                    ld c,11             ; desce: nova (11) [11, 11+x), velha (3) [3+x, 11)
                    ld a,b
                    call GXor
                    pop bc
                    push bc
                    ld a,3
                    add a,b
                    ld c,a
                    ld a,8
                    sub b
                    call GXor
                    jr GDpp
GDsobe              ld a,11             ; sobe: nova (3) [11-x, 11), velha (11) [11, 19-x)
                    sub b
                    ld c,a
                    ld a,b
                    call GXor
                    pop bc
                    push bc
                    ld c,11
                    ld a,8
                    sub b
                    call GXor
GDpp                halt                ; desenha primeiro, mostra no frame seguinte
                    pop bc
                    inc b
                    inc b
                    ld a,b
                    cp 8
                    jr c,GDpas
GDgota              ld hl,GotaTab
                    xor a
                    ld (GFrame),a
GDframe             ld c,0              ; 16 linhas da janela (GOff+0..15): gota ou fundo
GDfl                ld a,(hl)
                    inc hl
                    push hl
                    push bc
                    ld b,a
                    ld a,(GOff)
                    add a,c
                    ld c,a
                    push bc
                    call GLinhaEcra     ; HL = ecra
                    pop bc
                    jr nc,GDfn
                    push hl
                    ld a,b
                    cp 0FFh
                    jr z,GDff
                    ld l,a              ; GMarca + 64*linha
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,GMarca
                    add hl,de
                    jr GDfc
GDff                ld a,c
                    call GLinhaBuf
GDfc                ex de,hl            ; DE = origem
                    pop hl              ; HL = ecra
                    call GCopiaTE
GDfn                pop bc
                    pop hl
                    inc c
                    ld a,c
                    cp 16
                    jr c,GDfl
                    push hl
                    call GotaPinga
                    halt
                    call GotaSom
                    pop hl
                    ld a,(GFrame)
                    inc a
                    ld (GFrame),a
                    cp 6
                    jr c,GDframe
                    ld c,0              ; no fim: tudo como estava (fundo + a linha nova marcada)
                    ld a,(GRows)
                    call GFundo
                    ld c,0
GDfim               push bc
                    ld a,(GOff)
                    add a,3
                    add a,c
                    ld c,a
                    call GLinhaEcra
                    pop bc
                    jr nc,GDfim2
                    push bc
                    push hl
                    ld l,c
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,GMarca
                    add hl,de
                    ex de,hl
                    pop hl
                    call GCopiaTE
                    pop bc
GDfim2              inc c
                    ld a,c
                    cp 8
                    jr c,GDfim
                    ret
; repoe A linhas do fundo (GBuf) a partir da linha C da janela
GFundo              or a
                    ret z
GFl                 push af
                    call GRepoe
                    pop af
                    inc c
                    dec a
                    jr nz,GFl
                    ret
GRepoeTudo          ld c,0
GRt                 call GRepoe
                    inc c
                    ld a,(GRows)
                    cp c
                    jr nz,GRt
                    ret
GRepoe              push bc
                    call GLinhaEcra
                    jr nc,GRn
                    push hl
                    ld a,c
                    call GLinhaBuf
                    ex de,hl
                    pop hl
                    call GCopiaTE
GRn                 pop bc
                    ret
; inverte A linhas da janela a partir da C (as celulas da zona), 0 = nada
GXor                or a
                    ret z
GXl                 push af
                    push bc
                    call GLinhaEcra
                    jr nc,GXn
                    ld a,(GZn)
                    ld b,a
GXc                 ld a,(hl)
                    cpl
                    ld (hl),a
                    set 5,h
                    ld a,(hl)
                    cpl
                    ld (hl),a
                    res 5,h
                    inc l
                    djnz GXc
GXn                 pop bc
                    pop af
                    inc c
                    dec a
                    jr nz,GXl
                    ret
; C = linha da janela -> HL = ecra (4000h) da 1.a celula da zona; NC = fora do ecra
GLinhaEcra          ld a,(GTop8)
                    add a,c
                    sub 3
                    jr c,GLfora         ; acima da linha 0
                    cp 192
                    ret nc              ; abaixo da 191: NC
                    ld b,a              ; y
                    and 7
                    ld h,a
                    ld a,b
                    rra
                    rra
                    rra
                    and 18h
                    or h
                    or 40h
                    ld h,a
                    ld a,b
                    rla
                    rla
                    and 0E0h
                    ld l,a
                    ld a,(GZcel)
                    or l
                    ld l,a
                    scf
                    ret
GLfora              or a
                    ret
; A = linha da janela -> HL = GBuf + 64*A
GLinhaBuf           ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,GBuf
                    add hl,de
                    ret
; HL = ecra, DE = GBuf: ecra -> GBuf (GZn bytes de 4000h e depois os de 6000h, com LDIR)
GCopiaET            push hl
                    push de
                    ld a,(GZn)
                    ld c,a
                    ld b,0
                    ldir
                    pop de
                    pop hl
                    set 5,h
                    ld a,e
                    add a,32
                    ld e,a
                    jr nc,GCe1
                    inc d
GCe1                ld a,(GZn)
                    ld c,a
                    ldir
                    ret
; HL = ecra, DE = GBuf: GBuf -> ecra
GCopiaTE            ex de,hl
                    push hl
                    push de
                    ld a,(GZn)
                    ld c,a
                    ld b,0
                    ldir
                    pop de
                    pop hl
                    set 5,d
                    ld a,l
                    add a,32
                    ld l,a
                    jr nc,GCt1
                    inc h
GCt1                ld a,(GZn)
                    ld c,a
                    ldir
                    ret
; a gotinha: nos frames 0-2, um pingo a cair por baixo do meio da zona
GotaPinga           ld a,(GFrame)
                    cp 3
                    ret nc
                    ld e,a
                    ld d,0
                    ld hl,GPingoTab
                    add hl,de
                    add hl,de
                    ld a,(GOff)
                    add a,(hl)          ; linha da janela
                    ld c,a
                    inc hl
                    ld b,(hl)           ; quantas linhas
GPl                 push bc
                    call GLinhaEcra
                    jr nc,GPn
                    ld a,(GZn)
                    srl a
                    add a,l
                    ld l,a
                    ld a,(hl)
                    xor 18h
                    ld (hl),a
GPn                 pop bc
                    inc c
                    djnz GPl
                    ret
GPingoTab           db 13,2, 14,2, 15,1
; v18: o "blip" sai pelo altifalante (porta FEh, bit 4), nao pelo AY: assim nao interrompe a
; musica. Um so' toque quando a gota cai (frame 0): 16 meias ondas a descer de ~1900 Hz para
; ~180 Hz, uns 24 ms (o 1.o frame da gota demora um pouco mais).
GotaSom             ld a,(GFrame)
                    or a
                    ret nz
GotaBip             ld b,16
                    ld c,0
                    ld hl,35            ; meia onda = HL x 26 T
GBl                 ld a,c
                    xor 10h
                    ld c,a
                    or 1                ; borda azul (no hi-res a borda vem da porta FFh)
                    out (0FEh),a
                    push hl
GBd                 dec hl
                    ld a,h
                    or l
                    jr nz,GBd
                    pop hl
                    ld de,22
                    add hl,de
                    djnz GBl
                    ld a,1
                    out (0FEh),a
                    ret
; por frame, as 16 linhas da janela (GOff+0..15): linha da marca (0-7, GMarca) ou FFh = fundo
GotaTab             db 0,0,1,1,2,3,3,4,4,5,6,6,7,0FFh,0FFh,0FFh            ; h 13
                    db 0FFh,0FFh,0FFh,0FFh,0,1,2,4,5,6,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh   ; h 6
                    db 0FFh,0,0,1,2,2,3,4,5,5,6,7,0FFh,0FFh,0FFh,0FFh                 ; h 11
                    db 0FFh,0FFh,0FFh,0,1,2,3,4,5,6,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh     ; h 7
                    db 0FFh,0FFh,0,0,1,2,3,4,5,6,7,0FFh,0FFh,0FFh,0FFh,0FFh           ; h 9
                    db 0FFh,0FFh,0FFh,0,1,2,3,4,5,6,7,0FFh,0FFh,0FFh,0FFh,0FFh        ; h 8
GotaOk              db 0
GotaDE              dw 0
GotaB               db 0
GZlin               db 0
GZcel               db 0
GZn                 db 0
GFrame              db 0
GPassa              db 0                ; 0 nao, 1 desce, FFh sobe
GOff                db 0                ; linha nova na janela = 3 + GOff
GRows               db 16
GTop8               db 0
GBuf                ds 24*64
GMarca                ds 8*64             ; a linha nova, marcada
                    ENDIF
; ---------------------------------------------------------------------------
; Dados

TxtNavIdx           db "NAV.IDX",0
TxtNavDir           db "_NAV",0
TxtIdx              db ".IDX",0
TxtGrupoNome        db "DIR",0,"0",0,"_",0
TxtPai              db "..",0
TxtBarra            db "/",0
TxtVazio            db 0
TxtGrupos           db "DIR",0,"0-9",0," #",0,0," *",0,0
TxtPentaNome        db " PENTAGON",0
TxtP1024Nome        db " PENTA 1024",0
TxtPentaBin         db "/BIN/PENTA.BIN",0
TxtFiltros          db " TIMEX 2048",0," ZX 48K",0," ZX 128K",0," TX2048 128",0," TC2068",0
TxtMaq              db "  ?",0,0,0,0,0
                    db "  48K",0,0,0
                    db "  AY",0,0,0,0
                    db " 128K",0,0,0
                    db "TIMEX",0,0,0
                    db "OUTRO",0,0,0
                    IF !HIRES
TxtEmblema          db 0,0,0,0,0,0,0,0
                    db "     48K"           ; as 4 primeiras ficam nas riscas
                    db "    48AY"
                    db "    128K"
                    db " TIMEX",0,0
                    db " OUTRA",0,0
TabCorEmb           db 47h,47h,47h,79h,47h  ; 48K, AY, 128K, Timex (azul em branco), outra
TabArco             db 50h,70h,60h,68h
TabCorMaq           db 0Fh,4Fh,4Eh,4Dh,4Ch,4Bh
                    ENDIF
TxtPastaTag         db "PASTA",0
TxtSemIndice        db "sem indice",0
                    IF HIRES
TxtAjuda            db "ENTER corre ESPACO volta 9 pastas",0
TxtPastas           db "/_NAV/PASTAS.IDX",0
                    ELSE
TxtAjuda            db "ENT corre SPC volta",0
                    ENDIF
TxtACorrer          db "A carregar...",0
TxtSemExt           db "Sem extensao",0
TxtSemPlugin        db "Sem plugin para isto",0
TxtErroPlugin       db "Erro no plugin",0
TxtErroPasta        db "Nao entrei na pasta",0
                    IF HIRES
TxtReinicia         db "Mudar a maquina? ENTER sim",0
                    ELSE
TxtReinicia         db "Reiniciar? ENTER sim",0
                    ENDIF
TxtMenuTit          db "  ESCOLHER A MAQUINA",0
TxtMenuAj           db "7/6 escolhe ENTER muda SPC volta",0
TabMenu             db "TIMEX 2048",0,0
                    db "ZX 48K",0,0
                    db "ZX 128K",0,0
                    db "TIMEX 128K",0,0
                    db "TC2068",0,0
TabPenta            db "PENTAGON 128 ",0,0     ; (o Menu poe aqui o nome certo, 14 bytes)
                    db "GENERAL SOUND",0,0
TxtAMudar           db "A reiniciar...",0
TxtSemRom           db "Falta a ROM (/BIN)",0
TxtRom              db "/BIN/128.rom",0
TxtRom2068          db "/BIN/2068.rom",0
TxtMReset           db "Agora RESET com NMI",0
TxtCfg              db "/SYS/NAV.CFG",0
TabF3               db 00h,22h,22h,02h,00h  ; v13: bit 0 (AY da placa) a 0 -> AY de fora; Timex 2048, ZX 48K, ZX 128K, Timex 128, TC2068

                    align 8
Fonte               incbin "font8.bin"       ; 8x8 propria (fonte/letra8.py), 32..127

; variaveis
PortaFF             db 0
F3extra             db 0                ; bits 6-7 do F3 (pagina 12, byte 3FFEh)
MudouFF             db 0
MenuSel             db 0
MNultesq            db 0
Guardada            db 0
Pendente            db 0                ; v23: 1 = arrancar a maquina guardada depois do RESET+NMI
PendPenta           db 0                ; v24: os bits do Pentagon dessa maquina
Esta128             db 0
NovaMaq             db 0
NovaPenta           db 0                ; 80h = a maquina escolhida e' o Pentagon
SemPergunta         db 0
                    IF !HIRES
CRk                 db 0
CRtam               db 0
CfgBuf              ds 4
                    ENDIF
NaNav               db 0
SoMaq               db 0
                    IF !HIRES
EsEcra              dw 0
EsLarg              db 0
                    ENDIF
                    IF HIRES
NoMenu              db 0                ; 1 = no menu das maquinas
                    ENDIF
                    IF !HIRES
SelAnt              dw 0
TopoAnt             dw 0
                    ENDIF
SPguardado          dw 0
Iguardado           db 0
Frames              db 0
UltTecla            db 0
JoyAnt              db 0
JoyConta            db 0
Repete              db 0
Larga               db 0                ; v17: 1 = espera que se largue tudo (depois do ENTER)
                    IF HIRES
Repetiu             db 0                ; v16: 1 = a ultima tecla foi repeticao
                    ENDIF
Modo                db 0                ; 0 indice, 1 pasta sem indice
Foco                db 0                ; 0 letras, 1 ficheiros
Filtro              db 0                ; 0 todas, 1..4 maquina, 5 outras
NVis                db 0
GSel                db 0
GTopo               db 0
GrupoAct            db 0
GrupoAnt            db 0
                    IF !HIRES
GrupoTmp            db 0
LinhaTmp            db 0
CorTmp              db 0
                    ENDIF
                    IF !HIRES
RetPlugin           db 0
GrTxt               ds 3
                    ENDIF
NavDir              db 0
Ext                 db 0
Handle              db 0
Total               dw 0
Sel                 dw 0
Topo                dw 0
Base                dw 0
NReg                dw 0
Indice              dw 0
NumTmp              dw 0
                    IF !HIRES
NumTxt              ds 6
Vis                 ds 30
NomeIdx             ds 14
                    ENDIF
                    IF !HIRES
MsgEstado           ds 54
                    ENDIF
                    IF HIRES
Cwd                 equ 0F800h          ; hi-res: fora do codigo (o plugin pode apagar: le-se de novo)
                    ELSE
Cwd                 ds 260
                    ENDIF
                    IF HIRES
HVars               ds 135
MsgEstado           equ HVars           ; hi-res (54 bytes)
Fase                equ MsgEstado+54    ; pisca: o ultimo frame visto
Apagada             equ Fase+1          ; 1 = a seleccao esta' apagada
PCnt                equ Fase+2          ; frames ate' a' proxima troca
CorSel              equ Fase+3
EsAttr              equ Fase+4          ; (2)
EsImpar             equ Fase+6
EsMasc              equ Fase+7
Ocultas             equ Fase+8          ; 1 = sem coluna das letras (VeLetras)
ColF                equ Fase+9          ; coluna da lista (VeLetras)
PSel                equ Fase+10         ; pasta escolhida na barra de baixo (LePastas)
NumTxt              equ Fase+11         ; (6)
Vis                 equ NumTxt+6        ; (30)
NomeIdx             equ Vis+30          ; (14)
EsEcra              equ NomeIdx+14      ; (2)
EsLarg              equ EsEcra+2
SelAnt              equ EsEcra+3        ; (2)
TopoAnt             equ EsEcra+5        ; (2)
GrupoTmp            equ EsEcra+7
LinhaTmp            equ EsEcra+8
CorTmp              equ EsEcra+9
CRk                 equ EsEcra+10
CRtam               equ EsEcra+11
CfgBuf              equ EsEcra+12       ; (4)
RetPlugin           equ EsEcra+16
GrTxt               equ EsEcra+17       ; (3) " A",0
                    assert GrTxt+3 == HVars+135
                    ENDIF
FimCode2
LCODE2              equ FimCode2-CODE2
                    assert FimCode2 <= CODE2MAX         ; BBE2h-FFFEh: o NMI.SYS apaga (BBE5h, BBF1h)

