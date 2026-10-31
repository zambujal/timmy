#!/bin/bash
# faz_576p.sh - compila o Timextenso a 576p50 (720x576, 27 MHz, 4:3) em vez de 720p50, para TVs que nao aceitem 720p.
#   Usa as mesmas fontes; numa copia muda o MODO720 do top.vhd e os tempos do HDMI no timextenso.sdc.
#   O menu do ESP foi desenhado para 1280x720 e a 576p nao fica bem.
# Uso (dentro da pasta core/):  ./faz_576p.sh [pasta do IDE do Gowin]
#   Resultado: core/timextenso_576p.fs
set -e
G="${1:-$HOME/Transferências/Gowin_V1.9.11.03_Education_Linux/IDE}"
[ -x "$G/bin/gw_sh" ] || { echo "nao encontro $G/bin/gw_sh (passa a pasta IDE do Gowin como argumento)"; exit 1; }
AQUI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
cp -r "$AQUI/." "$T/"
rm -rf "$T/impl"
sed -i 's/MODO720 : boolean := true/MODO720 : boolean := false/' "$T/src/top.vhd"
grep -q "MODO720 : boolean := false" "$T/src/top.vhd" || { echo "nao consegui mudar o MODO720 no top.vhd"; exit 1; }
# os tempos do HDMI a 576p: serializador 27 x 5 = 135 MHz, ponto 27 MHz (o timextenso.sdc tem os do 720p, 27 x 55 / 4)
sed -i 's#-multiply_by 55 -divide_by 4 \[get_pins {pll/CLKOUT}\]#-multiply_by 5 [get_pins {pll/CLKOUT}]#' "$T/timextenso.sdc"
grep -q -- "-multiply_by 5 \[get_pins {pll/CLKOUT}\]" "$T/timextenso.sdc" || { echo "nao consegui mudar o timextenso.sdc"; exit 1; }
cd "$T"
LD_LIBRARY_PATH="$G/lib" QT_QPA_PLATFORM=offscreen "$G/bin/gw_sh" timextenso.tcl 2>&1 | tail -3 || true
F="$(ls "$T"/impl/pnr/*.fs 2>/dev/null | head -1)"
[ -n "$F" ] || { echo "a compilacao nao deu .fs (ver $T/impl)"; exit 1; }
rm -f "$AQUI/timextenso_576p.fs" "$AQUI/timextenso_576p.tr"   # o Gowin grava o .fs so' de leitura
cp "$F" "$AQUI/timextenso_576p.fs"
cp "$T"/impl/pnr/*.tr "$AQUI/timextenso_576p.tr" 2>/dev/null || true   # o relatorio de tempos
grep -A16 "Total Negative Slack Summary" "$T"/impl/pnr/*.tr | grep -E "pclk|sclk" || true
rm -rf "$T"
ls -l "$AQUI/timextenso_576p.fs"
