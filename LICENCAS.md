# Licenças

O conjunto é distribuído sob a **GNU GPL v3** (ficheiro `LICENSE`), porque inclui código GPL. Cada
ficheiro de outros autores mantém o seu cabeçalho e a sua licença:

| O quê | De quem | Licença |
|---|---|---|
| a parte SCLD do `core/src/core_timmy.vhd` | modelo do SCLD do Load ZX Museum (Álvaro Lopes, Paulo Cortesão), reparado e completado por António Vitor (CPLD-XC95288XL-replacement-for-scld-timex) | CC BY-SA 4.0 |
| `core/src/T80*.vhd` | Daniel Wallner (2001-2002), Sorgelig (2018); reparado e completado em 2026 (registo Q, flags) por António Vitor | a do T80 (tipo BSD, no cabeçalho) |
| `core/src/ym2149.vhd` | MikeJ (2005) | a do cabeçalho (tipo BSD) |
| `core/src/gs.vhd` | tradução para VHDL do gs.v do core ZX Spectrum do MiSTer (Sorgelig) | GPL |
| `core/src/sysctrl.vhd`, `mcu_spi.vhd` | a partir do MiSTeryNano (MiSTle-Dev, Till Harbaum) | GPL |
| `core/src/sid/*.v` | sid_top e companhia do C64_MiSTer, passado por sv2v | GPL |
| `core/src/divt/*.v`, `divmmc.vhd` | DivTIESUS (Miguel Angel Rodríguez Jodar, 2021) e ZX-UNO | GPL v3 |
| `core/src/ulaplus.vhd` | segue o ula_radas.v do ZX-UNO | GPL |
| `fontes/go/go_sem7.asm` | baseado no LOADROM do DivTIESUS | GPL v3 |
| `fontes/navpt3/navpt3.asm` | contém o Universal PT2/PT3/TS player de S. V. Bulba | livre, com o crédito |
| `core/arranque_teste/` | usa o z80emu de Lin Ke-Fong (não incluído) | a do z80emu |
| o resto (core_timmy, top, vídeo/HDMI, cassete, som, ponte, arranque e letras, NAV, GO2068, PENTA, SOMNAV, MOD, stub68, cartao.py) | António Vitor | GPL v3 |
| `core/src/hdmi/hdl-util/*.sv`, `core/src/hdmi/hdmi_hdlutil.sv` / `.v` (o HDMI com som) | hdl-util/hdmi, Sameer Puri (versão do NanoMig do djnice), adaptado para o Timmy | MIT (ou Apache-2.0) |

Código escrito com ajuda de IA.

Não incluído, por ter direitos: as ROMs do Timex / Sinclair, o esxDOS e os seus plugins (Bob Fossil),
o firmware FPGA-Companion / Partner do BL616.
