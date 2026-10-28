; PENTA.BIN: o NAV carrega-o em F400h ao reiniciar no Pentagon (menu das maquinas).
; Testa os dois CPLDs como o .go128 -penta e, se tiverem a sombra, liga a copia
; da DivTIESUS (DDh bit 1) e copia 4000h-7FFFh para a SRAM.
; Entrada: A = F3 da maquina (com o bit 7). Saida: A = 80h (so' os tempos) ou C0h (sombra).
; O F3 bit 6 liga-o o codigo que reinicia (C128f3). Interrupcoes desligadas.
; A pilha do NAV esta' na RAM de video (abaixo de 8000h): entre ligar o bit 6 e
; desliga-lo nao ha' CALL/RET/PUSH/POP.
                    org 0F400h
                    di
                    ld d,a              ; D = F3
                    ld a,(4000h)
                    push af             ; byte do ecra, repoe-se no fim
                    xor a
                    call PoeDD          ; copia desligada
                    ld e,5Ah            ; com o bit 6 e sem copia ninguem responde a' leitura
                    call Testa
                    jr z,SoTempos
                    ld e,0A5h
                    call Testa
                    jr z,SoTempos
                    ld a,2
                    call PoeDD          ; copia ligada
                    ld e,55h            ; a DivTIESUS copia? (banco 5 na pagina 26)
                    call TCopia
                    jr nz,SemCopia
                    ld e,0AAh
                    call TCopia
                    jr nz,SemCopia
                    pop af
                    ld (4000h),a
                    ld hl,4000h         ; copia: ler e escrever cada byte
CV                  ld a,(hl)
                    ld (hl),a
                    inc hl
                    ld a,h
                    cp 80h
                    jr nz,CV
                    ld a,0C0h
                    ret
SemCopia            xor a
                    call PoeDD
SoTempos            pop af
                    ld (4000h),a
                    ld a,80h
                    ret

; E = byte: escreve-o em 4000h, le' com o bit 6 ligado. Z = leu o mesmo (sem sombra)
Testa               ld a,e
                    ld (4000h),a
                    ld bc,00F3h
                    ld a,d
                    or 40h
                    out (c),a
                    ld a,(4000h)
                    ld l,a
                    ld a,d
                    out (c),a
                    ld a,l
                    cp e
                    ret

; E = byte: escreve-o em 4000h com a copia ligada, le' a pagina 26. Z = a SRAM tem-no
TCopia              ld a,e
                    ld (4000h),a
                    ld a,80h+26
                    out (0E3h),a
                    ld a,(2000h)
                    ld l,a
                    xor a
                    out (0E3h),a
                    ld a,l
                    cp e
                    ret

; A = valor do registo ZXUNO DDh
PoeDD               ld l,a
                    ld bc,0FC3Bh
                    ld a,0DDh
                    out (c),a
                    inc b
                    out (c),l
                    ret
Fim
                    assert Fim-0F400h <= 100h
