#!/bin/bash
# imagens de teste: FAT32 e FAT16, com e sem tabela de particoes, directorios grandes, nomes longos
set -e
faz() {   # $1 = nome, $2 = -F 32|16, $3 = tamanho em KB, $4 = spc
  rm -f $1.img
  mkfs.vfat -C -F $2 -S 512 -s $4 $1.img $3 >/dev/null 2>&1
  mmd -i $1.img ::/SYS ::/SYS/ROMS ::/JOGOS ::/Musica
  # nomes longos e muitas entradas (o directorio ROMS passa de um cluster)
  for k in $(seq 1 200); do echo "x" > /tmp/pequeno_$k.txt; mcopy -i $1.img /tmp/pequeno_$k.txt "::/SYS/ROMS/ficheiro longo numero $k.txt"; done
  mcopy -i $1.img lixo.bin ::/SYS/ROMS/A.BIN
  mcopy -i $1.img rom_esperada.bin ::/SYS/ROMS/TC2048.ROM
  mcopy -i $1.img lixo.bin ::/SYS/ROMS/B.BIN
  mcopy -i $1.img esx_esperado.bin ::/SYS/ROMS/ESXMMC.BIN
  mcopy -i $1.img lixo.bin ::/SYS/ROMS/C.BIN
}
faz f32g 32 65536 8
faz f16g 16 32768 4
faz f16b 16 65536 32
# com tabela de particoes: a particao comeca no sector 8192
mbr() {   # $1 = base, $2 = tipo de particao
  python3 - $1 $2 <<'P'
import sys, struct
base, tipo = sys.argv[1], int(sys.argv[2], 16)
vol = open(base + '.img', 'rb').read()
ini = 8192
mbr = bytearray(512)
total = ini + len(vol) // 512
struct.pack_into('<B3sB3sII', mbr, 0x1be, 0x80, b'\x01\x01\x00', tipo, b'\xfe\xff\xff', ini, total - ini)
mbr[0x1fe:0x200] = b'\x55\xaa'
out = open(base + 'p.img', 'wb'); out.write(bytes(mbr)); out.write(b'\0' * (512 * (ini - 1))); out.write(vol); out.close()
P
}
mbr f32g 0c
mbr f16g 06
ls -l *.img
