; MOD: plugin do navegador (formato dos plugins do Bob Fossil) que toca um .MOD no General Sound.
; O ficheiro vai byte a byte para o GS pelas portas do Spectrum (xxBB comando/estado, xxB3 dados):
;   F3h (reinicio quente: liberta os modulos), 30h (carregar modulo; o GS responde o numero),
;   os bytes do ficheiro, D2h (fim), e o numero do modulo + 31h (tocar). O GS continua a tocar depois
;   de o plugin voltar ao navegador. Estado (IN xxBB): bit 7 = dado por tirar, bit 0 = comando por tirar.
; v2 (00:25): o ciclo de envio apertado (~72 T por byte, o dobro da velocidade).
; v3 (00:30): fica a' espera do fim (o GS da' a volta a' posicao da cancao: comando 60h) e pede o ficheiro
;   seguinte (PLUGIN_NAVIGATE, BC = 1); o BREAK (Caps + Espaco, tambem o F4/F6/F7 do ESP) para o modulo e volta.
; v5 (00:40): a espera por cada byte volta a contar so' esse byte (corrige o v2-v4).
; v4 (00:35): opcoes no /BIN/BPLUGINS/CFG/MOD.CFG (o navegador passa-o em DE; editar com o .plugcfg e o MOD.INI):
;   byte 0 bit 0 = repetir (nao acaba; so' o BREAK sai), bit 1 = no fim, o ficheiro seguinte (por omissao 1);
;   byte 1 = tempo maximo em minutos (0 = sem limite): ao fim desse tempo conta como o fim da musica.
; Memoria: codigo em 8000h; o ficheiro passa em bocados de 4K por A3E0h (PLUGIN_RESTORE_BUFFERS).
; v6 (2026-10-29): a posicao (60h) so' conta depois de o GS a por a 0 (a cancao nova a andar): logo a seguir
;   ao 31h a primeira leitura podia trazer a posicao do modulo anterior e a seguinte (0) parecia "voltou para
;   tras" -> o 2.o MOD acabava em 1-2 s. Espera ate' 2 s pelo 0; e no fim diz em que posicao acabou (mensagem).
; (Timextenso, 2026-10-26)

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_NAVIGATE     equ 8
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

BUF                 equ 0A3E0h
BOCADO              equ 4096
GS_CMD              equ 0BBh
GS_DAT              equ 0B3h

                    org 8000h
                    jr Inicio
                    db "BP",0,0
                    db 0                ; flags
                    db 0                ; flags2
                    db "MOD (GS) - Timextenso",0

Inicio              push ix
                    push iy
                    ld a,2              ; sem CFG: o seguinte no fim, sem limite de tempo
                    ld (Opc),a
                    xor a
                    ld (Minutos),a
                    ld a,d              ; DE = o CFG (16 bytes) ou 0
                    or e
                    jr z,SemCfg
                    ld a,(de)
                    ld (Opc),a
                    inc de
                    ld a,(de)
                    ld (Minutos),a
SemCfg
                    ld a,'*'            ; HL = nome do ficheiro
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ; reinicio quente do GS (liberta o que estava carregado)
                    ld a,0F3h
                    call Comando
                    jp c,ErroGS
                    ld de,0             ; o INITVAR leva um bocadinho (~0,2 s; o plugin corre com DI: sem HALT)
Pausa               dec de
                    ld a,d
                    or e
                    jr nz,Pausa
                    ; carregar modulo: o GS responde o numero do modulo
                    ld a,30h
                    call Comando
                    jp c,ErroGS
                    in a,(GS_DAT)
                    ld (Modulo),a
                    ; os bytes do ficheiro
Bloco               ld a,(FH)
                    ld hl,BUF
                    ld bc,BOCADO
                    rst 08h
                    db F_READ
                    jp c,ErroLe
                    ld a,b
                    or c
                    jr z,Fim            ; acabou o ficheiro
                    ld hl,BUF
                    ld d,b              ; DE = bytes lidos
                    ld e,c
                    ld bc,0             ; BC = contador do tempo de espera
; (v2) o ciclo apertado: ~72 T por byte em vez de ~144 (o dobro da velocidade)
Byte                in a,(GS_CMD)       ; o GS ja' tirou o anterior? (bit 7 a 0)
                    rla
                    jr c,Espera
                    ld a,(hl)
                    out (GS_DAT),a
                    ld bc,0             ; (v5) o tempo de espera conta por byte (no v2-v4 era para o ficheiro todo:
                    inc hl              ;  num MOD grande acabava em "o GS nao responde" a meio)
                    dec de
                    ld a,d
                    or e
                    jr nz,Byte
                    jr Bloco
Espera              dec bc              ; o GS nao tira: desiste ao fim de ~65536 voltas
                    ld a,b
                    or c
                    jr nz,Byte
                    jp ErroGS
Fim                 ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    call EsperaDado     ; o ultimo byte ja' foi tirado?
                    jp c,ErroGS2
                    ld a,0D2h           ; fim do modulo
                    call Comando
                    jp c,ErroGS2
                    ; tocar o modulo
                    call EsperaDado
                    jp c,ErroGS2
                    ld a,(Modulo)
                    out (GS_DAT),a
                    ld a,31h
                    call Comando
                    jp c,ErroGS2
                    xor a
                    ld (Pos),a
                    ld (PosAnt),a
                    ld b,40             ; (v6) espera que o GS ponha a posicao a 0 (ate' 40 x 50 ms)
Esp0                push bc
                    ld de,4000
Esp0a               dec de
                    ld a,d
                    or e
                    jr nz,Esp0a
                    ld a,60h
                    call Comando
                    pop bc
                    jp c,ErroGS2
                    in a,(GS_DAT)
                    or a
                    jr z,Esp0ok
                    djnz Esp0
Esp0ok              ld hl,0
                    ld (Voltas),hl      ; voltas de ~70 ms (860 por minuto)
                    ld a,(Minutos)      ; o limite em voltas: minutos x 860
                    ld hl,0
                    or a
                    jr z,SemLim
                    ld b,a
                    ld de,860
Mult                add hl,de
                    djnz Mult
SemLim              ld (Limite),hl
; (v3) a tocar: de ~50 em ~50 ms pergunta a posicao; se voltar para tras, a cancao acabou
Toca                ld de,4000          ; ~50 ms a 3,5 MHz (o plugin corre com DI)
TEsp                ld a,7Fh            ; BREAK: Caps Shift (FEFE bit 0) + Espaco (7FFE bit 0)
                    in a,(0FEh)
                    rra
                    jr c,TSemBrk
                    ld a,0FEh
                    in a,(0FEh)
                    rra
                    jr nc,Brk
TSemBrk             dec de
                    ld a,d
                    or e
                    jr nz,TEsp
                    ld hl,(Limite)      ; (v4) o tempo maximo
                    ld a,h
                    or l
                    jr z,TSemLim
                    ld de,(Voltas)
                    inc de
                    ld (Voltas),de
                    or a
                    sbc hl,de
                    jr z,Acabou
TSemLim             ld a,60h            ; a posicao na cancao
                    call Comando
                    jr c,Fim2           ; o GS deixou de responder: sai
                    in a,(GS_DAT)
                    ld hl,Pos
                    ld c,(hl)
                    ld (PosAnt),bc      ; (v6) PosAnt = a anterior (C); o byte seguinte e' lixo, nao faz mal
                    cp (hl)
                    ld (hl),a
                    jr nc,Toca          ; ainda a andar para a frente
                    ld a,(Opc)          ; voltou para tras: acabou. (v4) A repetir: continua
                    rra
                    jr c,Toca
Acabou              call MostraFim      ; (v6) escreve "NNN MMM" (posicao final, anterior) no canto do ecra, 2 s
                    ld a,(Opc)          ; o seguinte (bit 1) ou so' parar
                    and 2
                    jr z,Brk
                    ld a,32h
                    call Comando
                    pop iy
                    pop ix
                    ld bc,1             ; o ficheiro seguinte
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS|PLUGIN_NAVIGATE
                    ret
Brk                 ld a,32h            ; BREAK: para o modulo e volta (quem carregou escolhe a seguir)
                    call Comando
Fim2                pop iy
                    pop ix
                    ld bc,0
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS
                    ret

; manda o comando A e espera que o GS o tire (bit 0 a 0); CF = o GS nao respondeu
Comando             push bc
                    push af
                    call EsperaCmd
                    jr c,ComErro
                    pop af
                    out (GS_CMD),a
                    call EsperaCmd
                    pop bc
                    ret
ComErro             pop af
                    pop bc
                    scf
                    ret
; espera pelo bit 0 do estado a 0 (~1 s no maximo)
EsperaCmd           push de
                    ld de,0
ECv                 in a,(GS_CMD)
                    rra
                    jr nc,ECok
                    dec de
                    ld a,d
                    or e
                    jr nz,ECv
                    pop de
                    scf
                    ret
ECok                pop de
                    or a
                    ret
; espera pelo bit 7 do estado a 0 (o GS tirou o dado)
EsperaDado          push de
                    ld de,0
EDv                 in a,(GS_CMD)
                    rla
                    jr nc,EDok
                    dec de
                    ld a,d
                    or e
                    jr nz,EDv
                    pop de
                    scf
                    ret
EDok                pop de
                    or a
                    ret

ErroAbre            pop iy
                    pop ix
                    ld bc,TxtAbre
                    ld a,PLUGIN_ERROR|PLUGIN_MSG
                    ret
ErroLe              ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    pop iy
                    pop ix
                    ld bc,TxtLe
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret
ErroGS              ld a,(FH)
                    rst 08h
                    db F_CLOSE
ErroGS2             pop iy
                    pop ix
                    ld bc,TxtGS
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret

; (v6) diagnostico: escreve no canto superior esquerdo do ecra a posicao final (Pos) e a anterior (PosAnt),
; 3 algarismos cada, com uma letra 8x8 propria, e espera ~2 s para se ler (o navegador redesenha depois)
MostraFim           push af
                    push bc
                    push de
                    push hl
                    ld hl,4000h
                    ld a,(Pos)
                    call Num3
                    inc hl
                    ld a,(PosAnt)
                    call Num3
                    ld a,47h            ; atributos: branco sobre azul, brilho
                    ld hl,5800h
                    ld b,7
MFa                 ld (hl),a
                    inc hl
                    djnz MFa
                    ld de,0             ; ~2 s a 3,5 MHz (65536 x ~100 T)
MFe                 push de
                    ld b,8
MFe2                djnz MFe2
                    pop de
                    dec de
                    ld a,d
                    or e
                    jr nz,MFe
                    pop hl
                    pop de
                    pop bc
                    pop af
                    ret
Num3                ld c,100            ; A -> 3 algarismos a partir da celula (HL), HL avanca 3
                    call Dig
                    ld c,10
                    call Dig
                    ld c,1
Dig                 ld b,0              ; B = algarismo = quantas vezes cabe C em A
Dig2                cp c
                    jr c,Dig3
                    sub c
                    inc b
                    jr Dig2
Dig3                push af
                    push hl
                    push bc
                    ld a,b
                    add a,a
                    add a,a
                    add a,a             ; x 8
                    ld e,a
                    ld d,0
                    ex de,hl
                    ld bc,Algarismos
                    add hl,bc           ; HL = a letra, DE = a celula
                    ld b,8
Dig4                ld a,(hl)
                    ld (de),a
                    inc hl
                    inc d               ; linha seguinte do ecra (+256)
                    djnz Dig4
                    pop bc
                    pop hl
                    pop af
                    inc hl
                    ret
Algarismos          db 3Ch,66h,6Eh,76h,66h,66h,3Ch,00h   ; 0
                    db 18h,38h,18h,18h,18h,18h,3Ch,00h   ; 1
                    db 3Ch,66h,06h,0Ch,18h,30h,7Eh,00h   ; 2
                    db 3Ch,66h,06h,1Ch,06h,66h,3Ch,00h   ; 3
                    db 0Ch,1Ch,3Ch,6Ch,7Eh,0Ch,0Ch,00h   ; 4
                    db 7Eh,60h,7Ch,06h,06h,66h,3Ch,00h   ; 5
                    db 1Ch,30h,60h,7Ch,66h,66h,3Ch,00h   ; 6
                    db 7Eh,06h,0Ch,18h,30h,30h,30h,00h   ; 7
                    db 3Ch,66h,66h,3Ch,66h,66h,3Ch,00h   ; 8
                    db 3Ch,66h,66h,3Eh,06h,0Ch,38h,00h   ; 9
FH                  db 0
PosAnt              db 0
                    db 0                ; (o ld (PosAnt),bc escreve 2 bytes)
Modulo              db 0
Pos                 db 0
Opc                 db 2
Minutos             db 0
Voltas              dw 0
Limite              dw 0
TxtOk               db "MOD a tocar no General Sound",0
TxtAbre             db "MOD: nao abre o ficheiro",0
TxtLe               db "MOD: erro a ler o ficheiro",0
TxtGS               db "O GS nao responde (F2: General Sound)",0
