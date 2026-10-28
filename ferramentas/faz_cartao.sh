#!/bin/bash
# faz_cartao.sh: prepara um cartao do Timmy (Linux). Uso:
#   ./faz_cartao.sh /run/media/$USER/TIMMY2 [pacote_esxdos.zip]
# 1. (se dado) o esxDOS: BIN, SYS, TMP do zip (esxdos.org)
# 2. o navegador do Bob Fossil (NMI.SYS + BIN/BPLUGINS), descarregado de thefossilrecord.co.uk
# 3. a pasta cartao/ deste repositorio por cima
# 4. os indices (cartao.py --fazer)
# As ROMs (SYS/ROMS/TC2048.ROM, SYS/ROMS/ESXMMC.BIN, BIN/128.rom...) metes tu: ver o README.
set -e
CARTAO="$1"; ESXDOS="$2"
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$AQUI")"
[ -d "$CARTAO" ] || { echo "cartao nao montado: $CARTAO"; exit 1; }
TMP="$(mktemp -d)"

if [ -n "$ESXDOS" ]; then
    echo "== esxDOS: $ESXDOS"
    mkdir -p "$TMP/esx" && unzip -q "$ESXDOS" -d "$TMP/esx"
    E="$(dirname "$(find "$TMP/esx" -iname ESXMMC.BIN | head -1)")"
    [ -d "$E/BIN" ] || { echo "nao encontro o BIN do esxDOS no zip"; exit 1; }
    cp -r "$E/BIN" "$E/SYS" "$E/TMP" "$CARTAO/"
    mkdir -p "$CARTAO/SYS/ROMS"
    cp "$E/ESXMMC.BIN" "$CARTAO/SYS/ROMS/ESXMMC.BIN"
fi

echo "== navegador do Bob Fossil (NMI.SYS + BPLUGINS)"
curl -fsSL -o "$TMP/fossil.zip" http://www.thefossilrecord.co.uk/wp-content/uploads/zx/BROWSE_latest.zip
mkdir -p "$TMP/fossil" && unzip -q "$TMP/fossil.zip" -d "$TMP/fossil"
F="$(dirname "$(find "$TMP/fossil" -iname BPLUGINS -type d | head -1)")"
N="$(find "$TMP/fossil" -iname NMI.SYS | head -1)"
[ -d "$F/BPLUGINS" ] || { echo "nao encontro BPLUGINS no zip do Bob Fossil"; exit 1; }
[ -n "$N" ] || { echo "nao encontro NMI.SYS no zip do Bob Fossil"; exit 1; }
mkdir -p "$CARTAO/BIN/BPLUGINS" "$CARTAO/SYS"
cp -r "$F/BPLUGINS/." "$CARTAO/BIN/BPLUGINS/"
cp "$N" "$CARTAO/SYS/NMI.SYS"

echo "== cartao/ do Timmy por cima"
cp -r "$REPO/cartao/." "$CARTAO/"

echo "== indices"
python3 "$AQUI/cartao.py" "$CARTAO" --fazer
sync
rm -rf "$TMP"

echo
for f in SYS/ROMS/TC2048.ROM SYS/ROMS/ESXMMC.BIN; do
    [ -f "$CARTAO/$f" ] || echo "FALTA $f (ver o README, seccao 2)"
done
echo "feito: agora 'Ejetar' e cartao no Tang"
