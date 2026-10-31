; arranque.asm - Timextenso (Tang Nano 20K): programa de arranque que carrega as ROMs do cartao SD
;
;   Corre no lugar do esxDOS: ao ligar, a DivTIESUS mapeia a "EEPROM" (8K, este programa) em
;   0000-1FFF. Le do cartao (FAT32 ou FAT16, com ou sem tabela de particoes):
;       /SYS/ROMS/TC2048.ROM   16384 bytes   a ROM da maquina (TC2048 ou Spectrum 48K)
;       /SYS/ROMS/ESXMMC.BIN    8192 bytes   o esxDOS (ESXMMC.BIN do pacote do esxDOS)
;   para a RAM (8000h e C000h), copia-os para as duas memorias da FPGA pelo registo ZX-UNO A4h
;   (porta FD3B com FC3B = A4h: bit 0 = alvo, 0 = ROM, 1 = esxDOS; bit 7 = fim) e a FPGA reinicia
;   o Z80, que arranca como um Timextenso normal. Com erro, mostra-o no ecra e tenta outra vez.
;   O cartao e' lido pelo SPI da DivMMC (portas E7h e EBh, como o esxDOS faz).
;   Letra propria (fonte.asm). Nao ha' aqui nada tirado de ROMs com direitos.
;
;   sjasmplus arranque.asm   ->  arranque.bin (8192 bytes)

    device NOSLOT64K

PORT_CS     equ 0E7h            ; CS do cartao: FEh selecciona, FFh larga
PORT_SPI    equ 0EBh            ; dados SPI (IN devolve o byte da transferencia anterior)
ZX_IDX      equ 0FC3Bh
ZX_DAT      equ 0FD3Bh
REG_CARGA   equ 0A4h

BUF_HOME    equ 8000h           ; 16K: a ROM
BUF_ESX     equ 0C000h          ; 8K: o esxDOS
COPIA       equ 0E000h          ; a rotina final, a correr na RAM
BUF_ARR     equ 0EA00h          ; 512: o /SYS/ARRANQUE.CFG
PILHA       equ 0F000h
SECT        equ 0F000h          ; 512: sector lido (MBR, BPB, directorios)
FATS        equ 0F200h          ; 512: o ultimo sector da FAT
VARS        equ 0F400h

    ; variaveis (32 bits em little-endian)
    struct V
part_lba    ds 4                ; 1.o sector da particao
fat_lba     ds 4                ; 1.o sector da FAT
data_lba    ds 4                ; 1.o sector dos dados (cluster 2)
root_lba    ds 4                ; FAT16: o directorio raiz
root_n      ds 2                ; FAT16: sectores da raiz
spf         ds 4                ; sectores por FAT
dir_cl      ds 4                ; cluster do directorio actual (FAT32 / sub-pastas)
dir_modo    ds 1                ; 0 = cadeia de clusters, 1 = raiz da FAT16
cur_cl      ds 4                ; cluster em curso
lba         ds 4                ; sector a ler
tmp         ds 4
fat_cache   ds 4                ; sector da FAT que esta' em FATS (FFFFFFFF = nenhum)
ent_cl      ds 4                ; da entrada encontrada: cluster, tamanho, atributos
ent_tam     ds 4
ent_atr     ds 1
spc         ds 1                ; sectores por cluster
spc_sh      ds 1                ; log2(spc)
fat32       ds 1                ; 1 = FAT32, 0 = FAT16
sdhc        ds 1                ; 1 = enderecos em blocos (SDHC/SDXC), 0 = em bytes
nsec        ds 1
nrest       ds 1                ; sectores que faltam ler do ficheiro
nome_ptr    ds 2
dest        ds 2                ; destino da leitura
cmdbuf      ds 6
    ends

    org VARS
v           V                   ; as variaveis (nao vao no binario)
    org 0

;---------------------------------------------------------------- arranque
inicio:
    di
    ld sp,PILHA
    jp principal

    ; 0008 / 0038 / 0066: nada (interrupcoes desligadas; o NMI nao entra com a DivMMC mapeada)

principal:
    ld a,1
    out (0FEh),a                ; borda azul: a ler
    call limpa_ecra
    ld hl,txt_titulo
    ld de,0101h
    call escreve
    ld hl,txt_ajuda1
    ld de,1101h
    call escreve
    ld hl,txt_ajuda2
    ld de,1201h
    call escreve
    ld hl,txt_ajuda3
    ld de,1301h
    call escreve

tenta:
    ld sp,PILHA
    ld a,1
    out (0FEh),a
    ld hl,txt_a_ler
    ld de,0401h
    call escreve
    ld hl,txt_vazio
    ld de,0601h
    call escreve

    call sd_init                ; nao volta se falhar (erro_cartao)
    call fs_monta               ; idem (erro_fat)

    ld hl,nome_sys
    call procura
    jp c,erro_sys
    call entra_dir
    ld hl,nome_roms
    call procura
    jp c,erro_roms
    call entra_dir

    ld hl,nome_rom
    call procura
    jp c,erro_rom
    ld hl,4000h
    call tam_igual
    jp nz,erro_tam
    ld de,BUF_HOME
    ld b,32
    call le_ficheiro

    ld hl,nome_esx
    call procura
    jp c,erro_esx
    ld hl,2000h
    call tam_igual
    jp nz,erro_tam
    ld de,BUF_ESX
    ld b,16
    call le_ficheiro

    ld a,4
    out (0FEh),a                ; verde
    ld hl,txt_ok
    ld de,0401h
    call escreve
    call le_arranque            ; A = a maquina por defeito (linha do menu do NAV; 0 = TIMEX 2048)
    push af
    ld hl,copia_ini
    ld de,COPIA
    ld bc,copia_fim-copia_ini
    ldir
    pop af
    ld (COPIA+copia_auto-copia_ini+1),a
    jp COPIA

; (2026-10-31) /SYS/ARRANQUE.CFG ("AR",0,linha; o NAV grava-o com a tecla D no menu das maquinas):
; A = a linha (1-7), ou 0 se nao houver / nao prestar
le_arranque:
    call fs_monta               ; de volta a' raiz
    ld hl,nome_sys
    call procura
    jr c,.nada
    call entra_dir
    ld hl,nome_arr
    call procura
    jr c,.nada
    ld hl,4                     ; exactamente 4 bytes (vazio ou outro: nao se le', o le_ficheiro daria erro)
    call tam_igual
    jr nz,.nada
    ld de,BUF_ARR
    ld b,1
    call le_ficheiro
    ld hl,BUF_ARR
    ld a,(hl)
    cp 'A'
    jr nz,.nada
    inc hl
    ld a,(hl)
    cp 'R'
    jr nz,.nada
    inc hl
    ld a,(hl)
    or a
    jr nz,.nada
    inc hl
    ld a,(hl)
    cp 8                        ; 1-7: as maquinas do menu (8 e' o GS)
    ret c
.nada:
    xor a
    ret

; a rotina final corre na RAM (em E000h): escreve as duas memorias e pede o fim
copia_ini:
    ld bc,ZX_IDX
    ld a,REG_CARGA
    out (c),a
    ld bc,ZX_DAT
    xor a
    out (c),a                   ; alvo: a ROM
    ld hl,BUF_HOME
    ld de,0
    ld bc,4000h
    ldir
    ld bc,ZX_DAT
    ld a,1
    out (c),a                   ; alvo: o esxDOS
    ld hl,BUF_ESX
    ld de,0
    ld bc,2000h
    ldir
    ; (2026-10-31) a maquina por defeito: marca na pagina 12 da DivMMC (3FF6h: "ARRQ", linha, linha xor FFh)
    ; e o bit 6 do fim: sem o ESP, o core faz um NMI uns segundos depois e o NAV muda para ela
copia_auto:
    ld a,0                      ; (a linha, posta antes de saltar para aqui)
    or a
    jr z,.so_fim
    ld e,a
    ld a,80h+12
    out (0E3h),a                ; a pagina 12 em 2000h-3FFFh (as escritas ja' nao vao para as ROMs: alvo 1, so' ate' 1FFFh)
    ld hl,3FF6h
    ld (hl),'A'
    inc hl
    ld (hl),'R'
    inc hl
    ld (hl),'R'
    inc hl
    ld (hl),'Q'
    inc hl
    ld (hl),e
    inc hl
    ld a,e
    cpl
    ld (hl),a
    xor a
    out (0E3h),a
    ld a,0C0h                   ; fim + NMI automatico
    jr .fim
.so_fim:
    ld a,80h
.fim:
    ld bc,ZX_DAT
    out (c),a                   ; fim: a FPGA reinicia o Z80
    jr $
copia_fim:

;---------------------------------------------------------------- erros
erro_cartao:
    ld hl,txt_e_cartao
    jr erro
erro_fat:
    ld hl,txt_e_fat
    jr erro
erro_sys:
erro_roms:
    ld hl,txt_e_pasta
    jr erro
erro_rom:
    ld hl,txt_e_rom
    jr erro
erro_esx:
    ld hl,txt_e_esx
    jr erro
erro_tam:
    ld hl,txt_e_tam
    jr erro
erro_leitura:
    ld hl,txt_e_leitura
erro:
    ld sp,PILHA
    ld a,2
    out (0FEh),a                ; borda vermelha
    ld de,0601h
    call escreve
    ld hl,txt_outra_vez
    ld de,0401h
    call escreve
    ld a,0FFh
    out (PORT_CS),a             ; larga o cartao
    ld b,4
.esp:
    push bc
    call espera
    pop bc
    djnz .esp
    jp tenta

espera:                         ; ~0,5 s a 3,5 MHz
    ld bc,0
.e: dec bc
    ld a,b
    or c
    jr nz,.e
    ret

;---------------------------------------------------------------- cartao SD (SPI)
; IN A,(EBh) devolve o byte recebido na transferencia anterior e comeca outra (a enviar FFh)
sd_cmd:                         ; HL -> 6 bytes (comando, 4 de argumento, CRC); devolve A = R1; carry = sem resposta
    ld a,0FEh
    out (PORT_CS),a
    ld b,6
.env:
    ld a,(hl)
    out (PORT_SPI),a
    inc hl
    djnz .env
    ld b,10
.esp:
    in a,(PORT_SPI)
    or a
    jp p,.ok                    ; bit 7 = 0: resposta
    djnz .esp
    scf
    ret
.ok:
    or a                        ; carry = 0 (A fica)
    ret

sd_fim:                         ; larga o cartao e da' 8 relogios (guarda A e as flags: o R1)
    push af
    ld a,0FFh
    out (PORT_CS),a
    out (PORT_SPI),a
    pop af
    ret

sd_init:
    xor a
    ld (v.sdhc),a
    ld a,0FFh
    out (PORT_CS),a
    ld b,10
.clk:
    out (PORT_SPI),a            ; 80 relogios com o CS largado
    djnz .clk
    ld b,20
.c0:
    push bc
    ld hl,cmd0
    call sd_cmd
    pop bc
    jr c,.c0n
    cp 1
    jr z,.c0ok
.c0n:
    push bc
    call sd_fim
    pop bc
    djnz .c0
    jp erro_cartao
.c0ok:
    call sd_fim
    ld hl,cmd8
    call sd_cmd
    jp c,erro_cartao
    cp 1
    jr nz,.v1                   ; 05h (ilegal): cartao v1
    in a,(PORT_SPI)             ; R7: 4 bytes
    in a,(PORT_SPI)
    in a,(PORT_SPI)
    in a,(PORT_SPI)
    push af
    call sd_fim
    pop af
    cp 0AAh
    jp nz,erro_cartao
    ld hl,cmd41hc
    call acmd41
    jr c,.mmc
    ; CMD58: OCR, bit 30 = CCS (enderecos em blocos)
    ld hl,cmd58
    call sd_cmd
    jp c,erro_cartao
    in a,(PORT_SPI)
    and 40h
    jr z,.ocr
    ld a,1
    ld (v.sdhc),a
.ocr:
    in a,(PORT_SPI)
    in a,(PORT_SPI)
    in a,(PORT_SPI)
    call sd_fim
    jr .tam
.v1:
    call sd_fim
    ld hl,cmd41
    call acmd41
    jr nc,.tam
.mmc:
    ld bc,2000                  ; CMD1 (MMC antigos)
.c1:
    push bc
    ld hl,cmd1
    call sd_cmd
    call sd_fim
    pop bc
    jp c,erro_cartao
    or a
    jr z,.tam
    dec bc
    ld a,b
    or c
    jr nz,.c1
    jp erro_cartao
.tam:
    ld hl,cmd16                 ; blocos de 512 (so' os SDSC precisam)
    call sd_cmd
    call sd_fim
    ret

acmd41:                         ; HL -> CMD41 (com ou sem HCS); carry = nao saiu de idle
    ld (v.nome_ptr),hl
    ld bc,4000
.a:
    push bc
    ld hl,cmd55
    call sd_cmd
    call sd_fim
    jr c,.nao
    ld hl,(v.nome_ptr)
    call sd_cmd
    call sd_fim
    jr c,.nao
    pop bc
    or a
    ret z                       ; 00: pronto
    cp 1
    jr nz,.nao2                 ; outra resposta (ilegal): nao e' SD
    dec bc
    ld a,b
    or c
    jr nz,.a
    scf
    ret
.nao:
    pop bc
.nao2:
    scf
    ret

; le o sector (v.lba) para HL (512 bytes); com erro vai para erro_leitura
le_sector:
    push hl
    ld hl,v.cmdbuf
    ld (hl),51h                 ; CMD17
    inc hl
    ld a,(v.sdhc)
    or a
    jr z,.bytes
    ld a,(v.lba+3)
    ld (hl),a
    inc hl
    ld a,(v.lba+2)
    ld (hl),a
    inc hl
    ld a,(v.lba+1)
    ld (hl),a
    inc hl
    ld a,(v.lba+0)
    ld (hl),a
    jr .crc
.bytes:                         ; endereco em bytes = lba * 512
    ld a,(v.lba+2)
    rlca
    and 0FEh
    ld c,a
    ld a,(v.lba+1)
    rlca
    and 1
    or c
    ld (hl),a
    inc hl
    ld a,(v.lba+1)
    rlca
    and 0FEh
    ld c,a
    ld a,(v.lba+0)
    rlca
    and 1
    or c
    ld (hl),a
    inc hl
    ld a,(v.lba+0)
    rlca
    and 0FEh
    ld (hl),a
    inc hl
    ld (hl),0
.crc:
    inc hl
    ld (hl),1
    ld hl,v.cmdbuf
    call sd_cmd
    jr c,.erro
    or a
    jr nz,.erro
    ld de,0                     ; espera o inicio dos dados (FEh)
.tok:
    in a,(PORT_SPI)
    cp 0FEh
    jr z,.dados
    dec de
    ld a,d
    or e
    jr nz,.tok
.erro:
    call sd_fim
    jp erro_leitura
.dados:
    pop hl
    ld bc,PORT_SPI              ; B = 0: 256 + 256 bytes
    inir
    inir
    in a,(PORT_SPI)             ; CRC
    in a,(PORT_SPI)
    jp sd_fim

;---------------------------------------------------------------- 32 bits
mov32:                          ; (DE) <- (HL)
    ldi
    ldi
    ldi
    ldi
    ret

add32:                          ; (DE) <- (DE) + (HL)
    ld b,4
    or a
.a: ld a,(de)
    adc a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz .a
    ret

inc32:                          ; (HL) <- (HL) + 1
    ld b,4
.i: inc (hl)
    ret nz
    inc hl
    djnz .i
    ret

shl32:                          ; (HL) <- (HL) * 2
    ld b,4
    or a
.s: rl (hl)
    inc hl
    djnz .s
    ret

shr32:                          ; (HL) <- (HL) / 2   (HL aponta para o byte alto no fim... recebe o byte baixo)
    inc hl
    inc hl
    inc hl
    ld b,4
    or a
.s: rr (hl)
    dec hl
    djnz .s
    ret

zero32:                         ; (HL) <- 0
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    ret

tam_igual:                      ; Z se ent_tam = HL (e os bytes altos 0)
    ld a,(v.ent_tam+2)
    ld c,a
    ld a,(v.ent_tam+3)
    or c
    ret nz
    ld a,(v.ent_tam+0)
    cp l
    ret nz
    ld a,(v.ent_tam+1)
    cp h
    ret

;---------------------------------------------------------------- FAT
fs_monta:
    ld hl,v.lba
    call zero32
    ld hl,SECT
    call le_sector
    call e_bpb
    jr z,.bpb0
    ld a,(SECT+1C2h)            ; tabela de particoes: a 1.a
    or a
    jp z,erro_fat
    ld hl,SECT+1C6h
    ld de,v.part_lba
    call mov32
    ld hl,v.part_lba
    ld de,v.lba
    call mov32
    ld hl,SECT
    call le_sector
    call e_bpb
    jp nz,erro_fat
    jr .bpb
.bpb0:
    ld hl,v.part_lba
    call zero32
.bpb:
    ld a,(SECT+0Dh)             ; sectores por cluster
    ld (v.spc),a
    ld b,0
.sh: rrca
    jr c,.shok
    inc b
    jr .sh
.shok:
    ld a,b
    ld (v.spc_sh),a
    ; fat_lba = part_lba + reservados
    ld hl,v.part_lba
    ld de,v.fat_lba
    call mov32
    ld hl,SECT+0Eh
    ld de,v.tmp
    ldi
    ldi
    xor a
    ld (de),a
    inc de
    ld (de),a
    ld hl,v.tmp
    ld de,v.fat_lba
    call add32
    ; spf: 16 bits (FAT16) ou 32 (FAT32)
    ld hl,(SECT+16h)
    ld a,h
    or l
    jr z,.f32
    xor a
    ld (v.fat32),a
    ld (v.spf+2),a
    ld (v.spf+3),a
    ld (v.spf),hl
    ; raiz = fat_lba + nfats * spf
    ld hl,v.fat_lba
    ld de,v.root_lba
    call mov32
    ld a,(SECT+10h)
    ld b,a
.nf: push bc
    ld hl,v.spf
    ld de,v.root_lba
    call add32
    pop bc
    djnz .nf
    ; root_n = entradas / 16;  data = root + root_n
    ld hl,(SECT+11h)
    ld b,4
.d16:
    srl h
    rr l
    djnz .d16
    ld (v.root_n),hl
    ld (v.tmp),hl
    ld hl,0
    ld (v.tmp+2),hl
    ld hl,v.root_lba
    ld de,v.data_lba
    call mov32
    ld hl,v.tmp
    ld de,v.data_lba
    call add32
    ld a,1
    ld (v.dir_modo),a
    jr .fim
.f32:
    ld a,1
    ld (v.fat32),a
    ld hl,SECT+24h
    ld de,v.spf
    call mov32
    ld hl,v.fat_lba
    ld de,v.data_lba
    call mov32
    ld a,(SECT+10h)
    ld b,a
.nf32:
    push bc
    ld hl,v.spf
    ld de,v.data_lba
    call add32
    pop bc
    djnz .nf32
    ld hl,SECT+2Ch
    ld de,v.dir_cl
    call mov32
    xor a
    ld (v.dir_modo),a
.fim:
    ld hl,v.fat_cache
    ld a,0FFh
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    ret

e_bpb:                          ; Z se SECT parece um sector de arranque FAT (512 bytes/sector, spc potencia de 2)
    ld a,(SECT+0Bh)
    or a
    ret nz
    ld a,(SECT+0Ch)
    cp 2
    ret nz
    ld a,(SECT+0Dh)
    or a
    ret z
    ld b,a
    dec a
    and b                       ; potencia de 2: a & (a-1) = 0
    ret nz
    ld a,(SECT+1FEh)
    cp 55h
    ret nz
    ld a,(SECT+1FFh)
    cp 0AAh
    ret

entra_dir:                      ; a entrada encontrada passa a ser o directorio actual
    ld hl,v.ent_cl
    ld de,v.dir_cl
    call mov32
    xor a
    ld (v.dir_modo),a
    ret

; procura o nome 8.3 (HL, 11 bytes) no directorio actual; carry = nao esta'
procura:
    ld (v.nome_ptr),hl
    ld a,(v.dir_modo)
    or a
    jr nz,.raiz16
    ld hl,v.dir_cl
    ld de,v.cur_cl
    call mov32
.cl:
    call fim_cadeia
    jr c,.nao
    call cl_para_lba
    ld a,(v.spc)
    ld (v.nsec),a
.sec:
    ld hl,SECT
    call le_sector
    ld hl,(v.nome_ptr)
    call procura_sector
    or a
    ret z                       ; encontrado (carry = 0)
    cp 2
    jr z,.nao
    ld hl,v.lba
    call inc32
    ld hl,v.nsec
    dec (hl)
    jr nz,.sec
    call prox_cluster
    jr .cl
.nao:
    scf
    ret
.raiz16:
    ld hl,v.root_lba
    ld de,v.lba
    call mov32
    ld bc,(v.root_n)
.r:
    push bc
    ld hl,SECT
    call le_sector
    ld hl,(v.nome_ptr)
    call procura_sector
    pop bc
    or a
    ret z
    cp 2
    jr z,.nao
    ld hl,v.lba
    call inc32
    dec bc
    ld a,b
    or c
    jr nz,.r
    jr .nao

; procura nas 16 entradas de SECT: A = 0 encontrado (ent_*), 1 continua, 2 fim do directorio
procura_sector:
    ld ix,SECT
    ld b,16
.ent:
    ld a,(ix+0)
    or a
    jr z,.fim
    cp 0E5h
    jr z,.prox
    ld a,(ix+11)
    and 08h                     ; nome do volume ou nome longo: salta
    jr nz,.prox
    push hl
    push bc
    push ix
    pop de
    ld b,11
.cmp:
    ld a,(de)
    cp (hl)
    jr nz,.dif
    inc hl
    inc de
    djnz .cmp
    pop bc
    pop hl
    ; encontrada: cluster (hi em 14h so' na FAT32), tamanho, atributos
    ld a,(ix+1Ah)
    ld (v.ent_cl+0),a
    ld a,(ix+1Bh)
    ld (v.ent_cl+1),a
    ld a,(v.fat32)
    or a
    jr z,.c16
    ld a,(ix+14h)
    ld (v.ent_cl+2),a
    ld a,(ix+15h)
    and 0Fh
    ld (v.ent_cl+3),a
    jr .c
.c16:
    xor a
    ld (v.ent_cl+2),a
    ld (v.ent_cl+3),a
.c:
    ld a,(ix+1Ch)
    ld (v.ent_tam+0),a
    ld a,(ix+1Dh)
    ld (v.ent_tam+1),a
    ld a,(ix+1Eh)
    ld (v.ent_tam+2),a
    ld a,(ix+1Fh)
    ld (v.ent_tam+3),a
    ld a,(ix+0Bh)
    ld (v.ent_atr),a
    xor a
    ret
.dif:
    pop bc
    pop hl
.prox:
    ld de,32
    add ix,de
    djnz .ent
    ld a,1
    ret
.fim:
    ld a,2
    ret

; le B sectores do ficheiro (ent_cl) para DE
le_ficheiro:
    ld (v.dest),de
    ld a,b
    ld (v.nrest),a
    ld hl,v.ent_cl
    ld de,v.cur_cl
    call mov32
.cl:
    call fim_cadeia
    jp c,erro_leitura           ; o ficheiro acabou antes do tamanho
    call cl_para_lba
    ld a,(v.spc)
    ld (v.nsec),a
.sec:
    ld hl,(v.dest)
    call le_sector
    ld hl,(v.dest)
    inc h
    inc h
    ld (v.dest),hl
    ld hl,v.nrest
    dec (hl)
    ret z
    ld hl,v.lba
    call inc32
    ld hl,v.nsec
    dec (hl)
    jr nz,.sec
    call prox_cluster
    jr .cl

; lba = data_lba + (cur_cl - 2) << spc_sh
cl_para_lba:
    ld hl,v.cur_cl
    ld de,v.tmp
    call mov32
    ld hl,v.tmp
    ld a,(hl)
    sub 2
    ld (hl),a
    jr nc,.s
    inc hl
    ld a,(hl)
    sub 1
    ld (hl),a
    jr nc,.s
    inc hl
    ld a,(hl)
    sub 1
    ld (hl),a
    jr nc,.s
    inc hl
    dec (hl)
.s:
    ld a,(v.spc_sh)
    or a
    jr z,.add
    ld b,a
.sh:
    push bc
    ld hl,v.tmp
    call shl32
    pop bc
    djnz .sh
.add:
    ld hl,v.data_lba
    ld de,v.lba
    call mov32
    ld hl,v.tmp
    ld de,v.lba
    jp add32

; carry se cur_cl e' fim de cadeia (ou invalido)
fim_cadeia:
    ld a,(v.fat32)
    or a
    jr z,.f16
    ld a,(v.cur_cl+3)
    cp 0Fh
    jr nz,.ok3
    ld a,(v.cur_cl+2)
    cp 0FFh
    jr nz,.ok
    ld a,(v.cur_cl+1)
    cp 0FFh
    jr nz,.ok
    ld a,(v.cur_cl+0)
    cp 0F7h                     ; F7 = cluster mau, F8-FF = fim
    ccf
    ret
.ok3:
    jr c,.ok                    ; byte 3 < 0F: pode ser valido
    scf                         ; > 0F: invalido
    ret
.f16:
    ld a,(v.cur_cl+1)
    cp 0FFh
    jr nz,.ok
    ld a,(v.cur_cl+0)
    cp 0F7h
    ccf
    ret
.ok:                            ; cluster < 2: invalido
    ld a,(v.cur_cl+3)
    ld c,a
    ld a,(v.cur_cl+2)
    or c
    ld c,a
    ld a,(v.cur_cl+1)
    or c
    jr nz,.val
    ld a,(v.cur_cl+0)
    cp 2
    ret                         ; carry se < 2
.val:
    or a
    ret

; cur_cl <- FAT[cur_cl]
prox_cluster:
    ld hl,v.cur_cl
    ld de,v.tmp
    call mov32
    ld a,(v.fat32)
    or a
    ld b,7                      ; FAT32: 128 entradas por sector
    jr nz,.d
    ld b,8                      ; FAT16: 256
.d:
    push bc
    ld hl,v.tmp
    call shr32
    pop bc
    djnz .d
    ld hl,v.fat_lba
    ld de,v.lba
    call mov32
    ld hl,v.tmp
    ld de,v.lba
    call add32
    ; ja' esta' em FATS?
    ld hl,v.lba
    ld de,v.fat_cache
    ld b,4
.cmp:
    ld a,(de)
    cp (hl)
    jr nz,.le
    inc hl
    inc de
    djnz .cmp
    jr .entrada
.le:
    ld hl,FATS
    call le_sector
    ld hl,v.lba
    ld de,v.fat_cache
    call mov32
.entrada:
    ld a,(v.fat32)
    or a
    jr z,.e16
    ld a,(v.cur_cl)
    and 7Fh
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,FATS
    add hl,de
    ld de,v.cur_cl
    call mov32
    ld a,(v.cur_cl+3)
    and 0Fh
    ld (v.cur_cl+3),a
    ret
.e16:
    ld a,(v.cur_cl)
    ld l,a
    ld h,0
    add hl,hl
    ld de,FATS
    add hl,de
    ld a,(hl)
    ld (v.cur_cl+0),a
    inc hl
    ld a,(hl)
    ld (v.cur_cl+1),a
    xor a
    ld (v.cur_cl+2),a
    ld (v.cur_cl+3),a
    ret

;---------------------------------------------------------------- ecra
limpa_ecra:
    ld hl,4000h
    ld de,4001h
    ld bc,1800h-1
    ld (hl),0
    ldir
    ld hl,5800h
    ld de,5801h
    ld bc,300h-1
    ld (hl),47h                 ; branco brilhante sobre preto
    ldir
    ret

; escreve o texto (HL, acaba em 0) na linha D (0-23), coluna E (0-31)
escreve:
    push hl
    ld a,d
    and 18h
    or 40h
    ld h,a
    ld a,d
    and 7
    rrca
    rrca
    rrca
    or e
    ld l,a
    ex de,hl                    ; DE = endereco no ecra
    pop hl
.car:
    ld a,(hl)
    or a
    ret z
    inc hl
    push hl
    ld b,a                      ; B = caracter; C = indice na tabela
    ld hl,fonte_ordem
    ld c,0
.proc:
    ld a,(hl)
    or a
    jr z,.semcar                ; nao existe: espaco
    cp b
    jr z,.ach
    inc hl
    inc c
    jr .proc
.semcar:
    ld c,0
.ach:
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld bc,fonte
    add hl,bc                   ; HL = os 8 bytes da letra
    push de
    ld b,8
.lin:
    ld a,(hl)
    ld (de),a
    inc hl
    inc d
    djnz .lin
    pop de
    inc e
    pop hl
    jr .car

;---------------------------------------------------------------- dados
cmd0:    db 40h,0,0,0,0,95h
cmd8:    db 48h,0,0,1,0AAh,87h
cmd55:   db 77h,0,0,0,0,1
cmd41hc: db 69h,40h,0,0,0,1
cmd41:   db 69h,0,0,0,0,1
cmd58:   db 7Ah,0,0,0,0,1
cmd16:   db 50h,0,0,2,0,1
cmd1:    db 41h,0,0,0,0,1

nome_sys:  db "SYS        "
nome_roms: db "ROMS       "
nome_rom:  db "TC2048  ROM"
nome_esx:  db "ESXMMC  BIN"
nome_arr:  db "ARRANQUECFG"

txt_titulo:    db "TIMEXTENSO - ARRANQUE",0
txt_a_ler:     db "A LER O CARTAO SD...        ",0
txt_ok:        db "ROMS CARREGADAS: A ARRANCAR ",0
txt_outra_vez: db "TENTO OUTRA VEZ DAQUI A 2 S ",0
txt_vazio:     db "                            ",0
txt_e_cartao:  db "SEM CARTAO (OU ESTA EM USO) ",0
txt_e_fat:     db "O CARTAO NAO E FAT32/FAT16  ",0
txt_e_pasta:   db "FALTA A PASTA /SYS/ROMS     ",0
txt_e_rom:     db "FALTA /SYS/ROMS/TC2048.ROM  ",0
txt_e_esx:     db "FALTA /SYS/ROMS/ESXMMC.BIN  ",0
txt_e_tam:     db "FICHEIRO COM TAMANHO ERRADO ",0
txt_e_leitura: db "ERRO A LER O CARTAO         ",0
txt_ajuda1:    db "O CARTAO (FAT32) PRECISA DE:",0
txt_ajuda2:    db "/SYS/ROMS/TC2048.ROM (16384)",0
txt_ajuda3:    db "/SYS/ROMS/ESXMMC.BIN (8192) ",0

    include "fonte.asm"

fim_codigo:
    assert fim_codigo < 1FF0h
    ds 2000h - $, 0FFh          ; ate' aos 8K (nunca executar em 1FF8-1FFF: tira o mapeamento)
    savebin "arranque.bin", 0, 2000h
