#!/bin/bash
# faz_oldtv.sh - compila o "Timmy old TV": o mesmo core, mas a 576p50 (720x576, 27 MHz, 4:3) em vez de 720p50.
#   Para TVs antigas (LCD de 2005 ou antes) que dao imagem mas nao som a 720p.
#   O HDMI e' o da biblioteca hdl-util (core/oldtv/), o mesmo do NanoMig do djnice que da' som numa TV antiga;
#   o src/hdmi_tx.vhd do Timmy normal nao e' usado. O menu do ESP foi desenhado para 1280x720 e a 576p nao fica bem.
# Uso (dentro da pasta core/):  ./faz_oldtv.sh [pasta do IDE do Gowin]
#   Resultado: core/timmy_oldtv.fs
set -e
G="${1:-$HOME/Transferências/Gowin_V1.9.11.03_Education_Linux/IDE}"
[ -x "$G/bin/gw_sh" ] || { echo "nao encontro $G/bin/gw_sh (passa a pasta IDE do Gowin como argumento)"; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
cp -r "$AQUI/." "$T/"
rm -rf "$T/impl"
sed -i 's/MODO720 : boolean := true/MODO720 : boolean := false/' "$T/src/top.vhd"
# o HDMI da hdl-util (o do NanoMig do djnice) em vez do src/hdmi_tx.vhd
sed -i 's#^add_file src/hdmi_tx.vhd$#add_file oldtv/hdmi_oldtv.v\nadd_file oldtv/hdmi_tx_oldtv.vhd#' "$T/timmy.tcl"
grep -q "oldtv/hdmi_tx_oldtv.vhd" "$T/timmy.tcl" || { echo "nao consegui trocar o hdmi_tx no timmy.tcl"; exit 1; }
grep -q "MODO720 : boolean := false" "$T/src/top.vhd" || { echo "nao consegui mudar o MODO720 no top.vhd"; exit 1; }
cd "$T"
LD_LIBRARY_PATH="$G/lib" QT_QPA_PLATFORM=offscreen "$G/bin/gw_sh" timmy.tcl 2>&1 | tail -3 || true
F="$(ls "$T"/impl/pnr/*.fs 2>/dev/null | head -1)"
[ -n "$F" ] || { echo "a compilacao nao deu .fs (ver $T/impl)"; exit 1; }
cp "$F" "$AQUI/timmy_oldtv.fs"
cp "$T"/impl/pnr/*.tr "$AQUI/timmy_oldtv.tr" 2>/dev/null || true   # o relatorio de tempos, para ver os caminhos
grep -A16 "Total Negative Slack Summary" "$T"/impl/pnr/*.tr | grep -E "pclk|sclk" || true
rm -rf "$T"
ls -l "$AQUI/timmy_oldtv.fs"
