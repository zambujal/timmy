; Acrescento ao plugin TAP do Bob Fossil (entra em 8071h no lugar de XOR A / RST 8 / DB 90h).
; Spectrum: o auto-load do esxDOS, como no original.
; TC2068 (CHANS = 6840h): o auto-load do esxDOS nao serve (reinicia com o ROM do 48K).
;   O NMI guardou a RAM 4000h-FFFFh nas paginas 5-10 do DivMMC e repoe-na a' saida:
;   escreve-se LOAD "" na linha de edicao dessa copia e deixa-se um ENTER pendente
;   (LASTK = 13, FLAGS bit 5). O plugin devolve 20h: o navegador sai e o BASIC carrega.
;   So' com a linha de edicao vazia; senao so' abre o TAP e diz para escrever LOAD "".
            org 8B31h
ELINE       equ 5C59h
KCUR        equ 5C5Bh
WORKSP      equ 5C61h
STKBOT      equ 5C63h
STKEND      equ 5C65h
LASTK       equ 5C08h
FLAGS       equ 5C3Bh

Inicio      ld a,(5C50h)        ; CHANS alto: 68h no TC2068
            cp 68h
            jr z,T68
            xor a
            rst 8
            db 90h              ; auto-load (Spectrum)
            ld a,80h
            ret
T68         ld hl,ELINE
            call LePal
            ld (VELine),de
            ld a,d              ; E_LINE tem de estar na RAM do BASIC
            cp 5Ch
            jp c,SoAbre
            ex de,hl
            call LeByte
            cp 0Dh              ; linha de edicao vazia?
            jp nz,SoAbre
            ld hl,STKEND
            call LePal
            ld (VStkend),de
            ld a,d
            cp 0FDh             ; a copia so' vai ate' FDFFh
            jp nc,SoAbre
            ld hl,(VStkend)     ; BC = STKEND - E_LINE
            ld de,(VELine)
            or a
            sbc hl,de
            jp c,SoAbre
            ld b,h
            ld c,l
            ld hl,(VStkend)
            dec hl
Move        ld a,b              ; [E_LINE, STKEND) sobe 3 bytes, de cima para baixo
            or c
            jr z,Escreve
            call LeByte
            inc hl
            inc hl
            inc hl
            call PoeByte
            dec hl
            dec hl
            dec hl
            dec hl
            dec bc
            jr Move
Escreve     ld hl,(VELine)
            ld a,0EFh           ; LOAD
            call PoeByte
            inc hl
            ld a,22h            ; "
            call PoeByte
            inc hl
            call PoeByte
            inc hl
            ex de,hl            ; DE = E_LINE+3: o cursor fica antes do ENTER da linha
            ld hl,KCUR
            call PoePal
            ld hl,WORKSP
            call Mais3
            ld hl,STKBOT
            call Mais3
            ld hl,STKEND
            call Mais3
            ld hl,LASTK
            ld a,0Dh            ; ENTER a' espera
            call PoeByte
            ld hl,FLAGS
            call LeByte
            or 20h              ; KEYHIT
            call PoeByte
            xor a
            out (0E3h),a
            ld a,31h            ; OK + mensagem + 20h: sair do navegador
            ld bc,TxtLoad
            ret
SoAbre      xor a
            out (0E3h),a
            ld a,11h            ; OK + mensagem
            ld bc,TxtAberto
            ret

; HL = endereco da RAM do BASIC -> HL = sitio na copia (2000h-3FFFh), pagina ligada
Mapa        ld a,h
            sub 40h
            rlca
            rlca
            rlca
            and 7
            add a,5
            out (0E3h),a
            ld a,h
            and 1Fh
            or 20h
            ld h,a
            ret
LeByte      push hl             ; A = (HL) da copia
            call Mapa
            ld a,(hl)
            pop hl
            ret
PoeByte     push hl             ; (HL) da copia = A
            push af
            call Mapa
            pop af
            ld (hl),a
            pop hl
            ret
LePal       call LeByte         ; DE = palavra em HL da copia
            ld e,a
            inc hl
            call LeByte
            ld d,a
            dec hl
            ret
PoePal      ld a,e              ; palavra em HL da copia = DE
            call PoeByte
            inc hl
            ld a,d
            call PoeByte
            dec hl
            ret
Mais3       call LePal
            inc de
            inc de
            inc de
            jr PoePal

VELine      dw 0
VStkend     dw 0
TxtAberto   db ".TAP aberto: LOAD \"\"",0
TxtLoad     db "LOAD \"\"",0
