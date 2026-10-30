#!/bin/bash
# faz_oldtv.sh - compila o "Timmy old TV": o mesmo core, mas a 576p50 (720x576, 27 MHz, 4:3) em vez de 720p50.
#   Para TVs antigas (LCD de 2005 ou antes) que dao imagem mas nao som a 720p.
#   O HDMI e' o da biblioteca hdl-util (core/oldtv/), o mesmo do NanoMig do djnice que da' som numa TV antiga;
#   o src/hdmi_tx.vhd do Timmy normal nao e' usado. O menu do ESP foi desenhado para 1280x720 e a 576p nao fica bem.
# Uso (dentro da pasta core/):  ./faz_oldtv.sh [720] [pasta do IDE do Gowin]
#   Resultado: core/timmy_oldtv.fs (576p) ou, com 720, core/timmy_oldtv720.fs (o HDMI da hdl-util a 720p50,
#   com o menu do ESP normal)
set -e
R=576; [ "$1" = "720" ] && { R=720; shift; }
G="${1:-$HOME/Transferências/Gowin_V1.9.11.03_Education_Linux/IDE}"
NOME=timmy_oldtv; [ $R = 720 ] && NOME=timmy_oldtv720
[ -x "$G/bin/gw_sh" ] || { echo "nao encontro $G/bin/gw_sh (passa a pasta IDE do Gowin como argumento)"; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
cp -r "$AQUI/." "$T/"
rm -rf "$T/impl"
if [ $R = 576 ]; then
sed -i 's/MODO720 : boolean := true/MODO720 : boolean := false/' "$T/src/top.vhd"
grep -q "MODO720 : boolean := false" "$T/src/top.vhd" || { echo "nao consegui mudar o MODO720 no top.vhd"; exit 1; }
# os tempos do HDMI a 576p: serializador 27 x 5 = 135 MHz, ponto 27 MHz (o timmy.sdc tem os do 720p, 27 x 55 / 4)
sed -i 's#-multiply_by 55 -divide_by 4 \[get_pins {pll/CLKOUT}\]#-multiply_by 5 [get_pins {pll/CLKOUT}]#' "$T/timmy.sdc"
grep -q -- "-multiply_by 5 \[get_pins {pll/CLKOUT}\]" "$T/timmy.sdc" || { echo "nao consegui mudar o timmy.sdc"; exit 1; }
fi
# o HDMI da hdl-util (o do NanoMig do djnice) em vez do src/hdmi_tx.vhd
sed -i 's#^add_file src/hdmi_tx.vhd$#add_file oldtv/hdmi_oldtv.v\nadd_file oldtv/hdmi_tx_oldtv.vhd#' "$T/timmy.tcl"
grep -q "oldtv/hdmi_tx_oldtv.vhd" "$T/timmy.tcl" || { echo "nao consegui trocar o hdmi_tx no timmy.tcl"; exit 1; }
cd "$T"
LD_LIBRARY_PATH="$G/lib" QT_QPA_PLATFORM=offscreen "$G/bin/gw_sh" timmy.tcl 2>&1 | tail -3 || true
F="$(ls "$T"/impl/pnr/*.fs 2>/dev/null | head -1)"
[ -n "$F" ] || { echo "a compilacao nao deu .fs (ver $T/impl)"; exit 1; }
cp "$F" "$AQUI/$NOME.fs"
cp "$T"/impl/pnr/*.tr "$AQUI/$NOME.tr" 2>/dev/null || true   # o relatorio de tempos, para ver os caminhos
grep -A16 "Total Negative Slack Summary" "$T"/impl/pnr/*.tr | grep -E "pclk|sclk" || true
rm -rf "$T"
ls -l "$AQUI/$NOME.fs"
