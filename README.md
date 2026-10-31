# Timextenso — Timex TC2068 e TC2048 (e mais) num Tang Nano 20K

*In English: [README.en.md](README.en.md)*

O Timextenso é um core em VHDL para a placa **Sipeed Tang Nano 20K** (FPGA Gowin GW2AR-18) que faz de
**Timex TC2068** e **TC2048**, com saída **HDMI 720p50**, cartão **microSD** com **esxDOS** (DivMMC),
teclado USB e som pelo HDMI. Arranca como TC2048 e pelo navegador do cartão passa a **TC2068** (com a
EXROM, os modos de ecrã do Timex: hi-colour, hi-res 512x192, e esxDOS também nesse modo), a
**ZX Spectrum 48K / 128K** ou a **Pentagon 128/512/1024**, com **General Sound**, **TurboSound** (3 AY),
**ULAplus**, rato Kempston e Z80 até 27 MHz. (O SID está nas fontes, `core/src/sid`, porto CF como o
ZX-TSid, mas **desligado** neste core — `SID := false` no `top.vhd`, por falta de BSRAM. O `cassete.vhd` é o
leitor de cassete que a placa ESP alimenta: sem ela não há cassete, e os TAP carregam pelo plugin do esxDOS.)

Precisa só do Tang Nano 20K, de um cartão microSD e de um teclado USB. (Há à parte uma placa com um
ESP32-S3 que dá menu com capas, rede, NAS, MP3 e mais; é outro projecto, depende deste e não é preciso
para nada do que está aqui: nada disso vem neste core.)

O core **não traz nenhuma ROM**: ao ligar, um pequeno programa de arranque lê do cartão a ROM do TC2048 e
o esxDOS, que cada um mete lá (ver "O cartão").

---

## 1. O que é preciso

- **Tang Nano 20K** (Sipeed), versão **3921** ou **3923** — o número impresso na placa por baixo do FPGA.
  O core é o mesmo nas duas (os pinos do FPGA não mudaram); o que muda na 3923, de meados de 2026, é o chip
  BL616 do teclado, que precisa do firmware **Companion da 3923** (secção 5). A placa liga-se ao PC pelo USB-C.
- **Cartão microSD** formatado em **FAT32** (até 32 GB é o mais simples).
- **Teclado USB** e um adaptador **USB-C OTG** (ou um hub USB-C alimentado) para o ligar ao Tang.
- **Cabo HDMI** para uma TV ou monitor que aceite 720p a 50 Hz.
- No PC: o **Gowin EDA** (gratuito, versão *Education*, Windows ou Linux) só para o **Programmer**, ou o
  **openFPGALoader** em Linux.
- O que é de outros e não está aqui:
  - a **ROM do TC2048** (16384 bytes) — ou a do ZX Spectrum 48K, que também serve — com que o core arranca;
  - para o modo **TC2068**, a **ROM do TC2068** (a home de 16K + a EXROM de 8K, `BIN/2068.rom`; e para o
    128K / Pentagon a do Spectrum 128, `BIN/128.rom`) — ver o passo 6 do cartão;
  - o **esxDOS** (www.esxdos.org): o pacote traz a pasta `BIN`, a pasta `SYS` e o ficheiro `ESXMMC.BIN`;
  - o **navegador do Bob Fossil** (http://www.thefossilrecord.co.uk, `BROWSE_latest.zip`): traz o
    `SYS/NMI.SYS` que carrega um navegador externo e os **plugins** `BIN/BPLUGINS` (TAP, Z80, SNA, TRD,
    PT3…). O esxDOS **não os traz**. O nosso navegador foi feito em cima do dele, entra pelo NMI.SYS dele e
    corre os jogos por estes plugins: sem isto fica o navegador a preto e branco do esxDOS, e os índices
    ficam vazios.

## 2. O cartão

1. Formatar em FAT32.
2. Copiar do pacote do esxDOS as pastas **`BIN`**, **`SYS`** e **`TMP`** para a raiz do cartão.
3. Copiar o zip do navegador do **Bob Fossil** inteiro por cima (o `BIN` com os `BPLUGINS` e o
   **`SYS/NMI.SYS`** dele: o NMI.SYS do esxDOS traz um navegador a preto e branco dentro e nunca carrega o
   `/BIN/BROWSE.BIN`; o do Bob Fossil carrega-o, e é por aí que o nosso entra).
4. Copiar para cima destas a pasta **`cartao/`** deste repositório (o `BIN` e o `SYS` daqui juntam-se aos do
   esxDOS: navegador, GO128/GO256/GO1024/GO2068, PENTA, plugin MOD, música de arranque).
5. Criar a pasta **`SYS/ROMS`** e meter lá:
   - `TC2048.ROM` — a ROM (16384 bytes);
   - `ESXMMC.BIN` — o esxDOS, tal como vem no pacote (8192 bytes).
6. Opcional, só para as outras máquinas e placas (também têm direitos, não estão aqui):
   - `BIN/128.rom` — a ROM do ZX Spectrum 128 (32768 bytes: ROM 0 + ROM 1), para o modo 128K e o
     Pentagon;
   - `BIN/2068.rom` — a do Timex TC2068 para o modo TC2068: ROM home de 16K + EXROM de 8K (24576
     bytes), ou com mais os 8K do esxDOS do 2068 a seguir (32768 bytes), que dá esxDOS nesse modo;
   - `BIN/GS105B.ROM` — o firmware do General Sound, versão 1.05b (32768 bytes), para o GS; as fontes
     estão em github.com/psbhlw/gs-firmware;
   - `BIN/PLUG2068/TAP` — plugin TAP para o TC2068 (**sem ele os TAP não carregam no navegador no modo
     TC2068**). Não vem no repositório porque é feito do plugin TAP do Bob Fossil; faz-se com
     `python3 fontes/plug2068/faz_plug2068.py BIN/BPLUGINS/TAP BIN/PLUG2068/TAP` (o `faz_cartao.sh` já o faz; o que é e porquê: `fontes/plug2068/LEIAME.md`).
   Sem eles o Timextenso é um TC2048 com esxDOS; o navegador avisa quando falta um.
7. Os jogos vão em pastas na raiz (por exemplo `JOGOS/`, ou uma por letra).
8. **No fim, com o cartão no PC, corre o `ferramentas/cartao.py`** (secção 6): faz os índices que dão
   ao navegador os nomes compridos, a coluna das letras e a barra de cima com o menu das máquinas. Sem
   eles o navegador funciona, mas incompleto.

Em Linux, os passos 2, 3, 4 e 8 (e o `BIN/PLUG2068/TAP`) fazem-se de uma vez com o `ferramentas/faz_cartao.sh` (descarrega ele
próprio o zip do Bob Fossil; as ROMs metes tu depois, ou antes):

```
cd timextenso/ferramentas && ./faz_cartao.sh /run/media/$USER/NOME_DO_CARTAO ~/Transferências/esxdos089.zip
```

Resumindo, a raiz do cartão fica assim:

```
BIN/        esxDOS + BPLUGINS/ do Bob Fossil (TAP, Z80, SNA, TRD, PT3...) + os nossos (BROWSE.BIN, NAVHR.BIN,
            GO128, GO256, GO1024, GO2068, PENTA.BIN, NAVPT3.BIN, SOMNAV.BIN, BPLUGINS/MOD, BPLUGINS/CFG/MOD.CFG e MOD.INI)
            (opcionais: 128.rom, 2068.rom, GS105B.ROM, PLUG2068/TAP)
SYS/        esxDOS + NMI.SYS do Bob Fossil + NAV.SOM + ROMS/TC2048.ROM + ROMS/ESXMMC.BIN
TMP/        esxDOS
JOGOS/ ...  o que quiseres
```

## 3. Gravar o core no Tang Nano 20K

Há duas maneiras de ter o core: **usar o já compilado** (`timextenso.fs`, na secção **Releases** deste
repositório) ou **compilá-lo** com o Gowin EDA (secção 3.4). Nas duas o ficheiro `.fs` grava-se na
flash da placa e fica lá até se gravar outro.

A placa liga-se ao PC pelo USB-C. Com o firmware de fábrica do BL616 aparece como um programador
FTDI ("20K's FRIEND"); com o firmware do teclado + Partner (secção 5) aparece como programador se
estiver ligada **directamente a uma porta do PC, sem hub**.

### 3.1 Windows, com o Gowin Programmer

1. Instalar o **Gowin EDA Education** (www.gowinsemi.com, precisa de registo gratuito). Os drivers USB
   do programador instalam-se com ele.
2. Abrir o **Gowin Programmer** (no Gowin EDA: "Program Device") e carregar em **scan_device**: deve
   aparecer o **GW2AR-18C**. OK.
3. Carregar duas vezes na linha do dispositivo (coluna "Operation") para abrir a configuração:
   - **Access Mode:** `External Flash Mode`
   - **Operation:** `exFlash Erase, Program`
   - **FS File:** o `timextenso.fs`
   - **External Flash:** `Generic Flash`, endereço `0x000000`
4. **Program** (o botão de gravar). Demora uns segundos. Desligar e voltar a ligar o Tang: o Timextenso
   arranca.

### 3.2 Windows, com o openFPGALoader (ferramenta livre)

1. Instalar o **MSYS2** (www.msys2.org) e, no terminal "MSYS2 UCRT64":
   `pacman -S mingw-w64-ucrt-x86_64-openFPGALoader`
2. O Windows tem de dar a interface do programador ao driver **WinUSB**: correr o **Zadig**
   (zadig.akeo.ie), em *Options → List All Devices*, escolher a **interface 0** do programador do Tang
   (FT2232-compatível) e instalar o WinUSB. (Isto tira a interface ao driver FTDI; o Gowin Programmer
   deixa de a ver até se repor o driver FTDI, também com o Zadig.)
3. No mesmo terminal: `openFPGALoader -b tangnano20k -f timextenso.fs`

### 3.3 Linux, com o openFPGALoader

```
sudo apt install openfpgaloader                      # Debian / Ubuntu
sudo dnf copr enable mobicarte/openFPGALoader && sudo dnf install openFPGALoader   # Fedora
openFPGALoader -b tangnano20k -f timextenso.fs
```

Se der "unable to open ftdi device" é permissão de USB: correr com `sudo` ou instalar as regras udev
que vêm com o openFPGALoader (`99-openfpgaloader.rules`). O Gowin Programmer também existe para Linux
e faz o mesmo que em Windows.

### 3.4 Compilar o core (opcional)

**TV que não aceita 720p?** Na pasta `core/`, `./faz_576p.sh` dá o `core/timextenso_576p.fs`: o mesmo core a 576p50
(4:3). O menu do ESP não fica bem a 576p.


Com o Gowin EDA (1.9.11 ou mais recente; a versão Education chega), na pasta `core/`:

```
gw_sh timextenso.tcl
```

Demora uns 10 minutos num PC normal (o core enche a FPGA quase toda) e no fim o Gowin às vezes queixa-se ao fechar;
se o `.fs` apareceu, está feito. O resultado fica em `core/impl/pnr/*.fs`. Não precisa de ROM nenhuma: o programa de arranque
(`arranque.hex`) já está feito; para o refazer, `sjasmplus arranque/arranque.asm` e converter o
`.bin` para `.hex` (um byte por linha, em hexadecimal). Com as ferramentas livres (GHDL + yosys +
nextpnr-himbaechel + apicula) ainda não experimentámos; o core usa PLLs e serializadores da Gowin,
por isso é provável que precise de adaptações.

## 4. Ligar e usar

- Ligar o cartão, o HDMI e o teclado; alimentar o Tang pelo USB-C por um **carregador de 2 A** (ou hub
  alimentado). Uma porta USB de PC chega para o Tang sozinho, mas não para o Tang com a placa ESP: os picos
  de corrente do WiFi fazem cair o 5 V e o HDMI perde o sinal por instantes. O PC fica só para gravar.
- Ao ligar aparece "TIMEXTENSO - ARRANQUE" um instante (o programa a ler as ROMs do cartão) e depois o
  esxDOS e o BASIC do TC2048. Se faltar alguma coisa no cartão, o ecrã diz o quê e a borda fica
  vermelha; corrige-se o cartão e ele tenta sozinho de 2 em 2 s.
- **Os dois botões do Tang:**
  - o do **pino 87** é o **NMI**: abre o navegador do cartão. Nele: ENTER num ficheiro carrega-o
    (TAP, SNA, Z80, TRD, PT3 e outros formatos AY, MOD no General Sound; TZX não, só com a placa ESP); o menu das máquinas
    muda para 48K / 128K / Timex 128 / TC2068 / Pentagon e liga o General Sound e o TurboSound. As
    teclas estão em `docs/teclas.md`.
  - o do **pino 88** anda numa lista de 16 escolhas, mostrada em binário nos 4 LEDs (que ficam acesos
    com o número escolhido). O botão do NMI faz então essa escolha em vez do NMI: 0 (LEDs apagados)
    NMI, 1 `.ls`, 2 `.go128`, 3 `.go128 -penta`, 4 `.go1024`, 5 `.go2068`, 6 RESET+NMI (volta ao
    TC2048), 8 RESET, 10 `.gs`, 15 turbo. Para voltar ao NMI normal, carrega até os LEDs apagarem.
    Carregado 3 s troca de core (multiboot, se houver outro em `0x100000`).
- Pelo teclado, sem a placa ESP32, não há tecla de NMI: é o botão.
- **Máquina de arranque** (sem a placa ESP32): no menu das máquinas, **D** numa máquina grava-a em
  `/SYS/ARRANQUE.CFG`. A Tang liga sempre no TC2048 e, uns 2 s depois, muda sozinha para essa máquina (o core dá
  um NMI e o navegador faz como o ENTER no menu). D no TIMEX 2048 volta ao normal. Com a placa ESP32 ligada não
  faz nada (fica como sempre).
- **Arranque rápido**: ao ligar, o Z80 vai a 14 MHz durante a carga das ROMs e nos 3 s seguintes (é aí que se
  muda para a máquina de arranque); depois volta à velocidade normal.
- **Velocidade do Z80** (com ou sem a placa ESP32): **F10** sobe (3,5 → 7 → 14 → 27 MHz), **F9** desce. Não fica
  gravada: ao ligar é sempre 3,5 MHz. A 27 MHz, enquanto a DivMMC está mapeada (esxDOS, navegador, cargas do
  cartão), o Z80 desce para 14 MHz.
- **Pentagon 128 ou 1024?** Para as demos e jogos de Pentagon *128* usa o **Pentagon 128**: no esxDOS escreve
  `.go128 -penta` (ou escolhe-o no menu das máquinas). No **Pentagon 1024** (`.go1024`) os bits 5, 6 e 7 do
  porto 7FFD passam a escolher bancos — uma demo de 128 que os escreva (muitas fazem) salta para outra zona da
  memória a meio: ecrã a preto e música estragada. O 1024 é só para o que o pede (modo 16C, 512K/1024K).

## 5. O teclado USB, o rato e o comando (firmware do BL616)

O Tang Nano 20K tem um chip **BL616** que de fábrica é só o programador da FPGA. Para o teclado USB,
o rato (Kempston) e o comando (joystick Kempston) chegarem ao core, o BL616 tem de ter o firmware
**FPGA Companion**, de Till Harbaum (github.com/MiSTle-Dev/FPGA-Companion), que vem acompanhado do
**FPGA Partner**: com o Partner, a placa arranca como programador se ao ligar estiver num PC e como
teclado se não estiver. Grava-se uma vez e não se volta a mexer.

**Atenção:** as placas feitas a partir do início de 2024 são "cifradas" e só aceitam firmware cifrado
(o dos releases recentes do FPGA-Companion é esse). Com um firmware errado a placa deixa de aparecer
no USB até se gravar outro; o firmware de fábrica ("Friend 20K", nas duas versões, normal e cifrada)
está no repositório do FPGA-Companion e grava-se da mesma maneira. Ninguém fica com a placa estragada,
mas é por conta e risco de cada um.

### 5.1 O que descarregar

- **Placa 3921**: do release do FPGA-Companion para o Tang Nano 20K: `bl616_fpga_partner_nano20k.bin`,
  `fpga_companion_nano20k.bin` e o `flash_nano20k.ini` (grava os dois: o Partner em `0x000000` e o
  Companion em `0x40000`).
- **Placa 3923**: o Companion da 3921 não dá teclado (o SPI do BL616 está noutros pinos). Do mesmo release do
  FPGA-Companion (desde o fim de Outubro de 2026): `bl616_fpga_partner_nano20k_v3923.bin`,
  `fpga_companion_nano20k_v3923.bin` e `flash_nano20k_v3923.ini`. O Companion que vem com o NextNano para a
  3923 (`fpga_companion_tn20k_3923.bin`) também serve. Gravar só um Companion, nunca os dois.
- Não há maneira de ver a versão com o BL616 em modo de gravação: vê-se o número na placa, e se o teclado
  não aparecer com um Companion, grava-se o outro — não faz mal nenhum.
- A ferramenta de gravar da Bouffalo Lab: em Windows o **BLDevCube** (programa gráfico); em Linux o
  **BLFlashCommand**, que vem no mesmo pacote "Bouffalo Flash Cube" / no Bouffalo SDK
  (`tools/bflb_tools/bouffalo_flash_cube/`).

### 5.2 Pôr o BL616 em modo de gravação

Com o Tang **desligado**, carregar no botão **UPDATE** (o que está ao lado do HDMI) e, sem o largar,
ligar o USB ao PC. Aparece uma porta série nova, "Bouffalo CDC DEMO": em Windows uma `COMx`, em
Linux `/dev/ttyACM0` (ou outro número; `ls /dev/ttyACM*`). Pode-se largar o botão.

### 5.3 Gravar

**Linux**, na pasta com os três ficheiros:

```
sudo ./BLFlashCommand --interface=uart --baudrate=2000000 --port=/dev/ttyACM0 --chipname=bl616 --cpu_id= --config=flash_nano20k.ini
```

No fim diz "All programming completed successfully".

**Windows**, no BLDevCube: escolher o chip **BL616/618**; em *Single download option* pôr o
`bl616_fpga_partner_nano20k.bin` no endereço `0x0`; escolher a `COMx` da placa e *Create & Download*.
Repetir com o `fpga_companion_nano20k.bin` no endereço `0x40000`. (Ou importar o `flash_nano20k.ini`,
que já tem os dois.)

### 5.4 Usar

- Desligar e voltar a ligar o Tang (sem o UPDATE).
- **Para jogar:** o teclado (ou um hub com teclado, rato e comando) ligado ao USB-C do Tang por um
  adaptador OTG; a alimentação vem pelo hub (se for alimentado) ou por um carregador num hub com
  entrada de energia. O core vê o teclado, o rato e o comando.
- **Para gravar um core novo:** ligar o Tang **directamente a uma porta do PC** (num hub pode não
  aparecer): o Partner arranca como programador ("USB Debugger") e o Gowin Programmer ou o
  openFPGALoader funcionam como na secção 3. Para voltar a jogar, basta mudar o cabo.
- O Tang tem de ficar mesmo sem corrente ao mudar de um para o outro: o BL616 só decide o modo ao
  arrancar.

## 6. Ferramentas: os índices do navegador (importante)

**Convém fazer isto logo:** sem índices o navegador fica incompleto. Lê cada pasta pelo esxDOS, mas os
nomes aparecem curtos, em 8.3 (`JETSETW~1.TAP`), não há a coluna das letras nem a **barra de cima com a
máquina** (onde o ENTER abre o menu das máquinas e das placas), e uma pasta com milhares de ficheiros
demora a abrir. Sem índice, o menu das máquinas só se abre com as teclas 1 a 4. Os **índices** são ficheiros
`_NAV/*.IDX` que o `ferramentas/cartao.py` escreve em cada pasta, no PC, com o nome comprido de cada
jogo, o nome 8.3 e a máquina; com eles o navegador mostra os nomes inteiros, a máquina (`[48K]`,
`[128K]`…), as letras na coluna da esquerda, e abre qualquer pasta num instante. De caminho o
`cartao.py` arruma a colecção: separa por letra e título e mete a máquina no nome dos ficheiros.
Precisa só de Python 3.

1. No `ferramentas/config.ini` dizes o que ele faz a cada pasta (nomes separados por espaços):
   - `jogos = JOGOS DEMOS` — pastas de jogos: arruma-as, mete a máquina no nome e indexa-as
     (`jogos =` vazio: nenhuma; sem a linha: todas as da raiz menos as do sistema e `FAVORITOS`);
   - `indexar = FAVORITOS MUSICA` — pastas que só indexa, sem mexer nos nomes nem na ordem
     (`tudo` = o cartão inteiro);
   - em `[pastas]`, as que aparecem na barra de baixo do navegador (`FAVORI = FAVORITOS`).
   O mesmo dá-se no comando, com `--pastas`, `--indexar` e `--pasta`, que ganham ao `config.ini`;
   `--so-indices` faz só os índices do cartão todo.
2. Com o cartão no PC, primeiro só a ver o que faria:
   - Linux: `python3 ferramentas/cartao.py /run/media/$USER/NOME_DO_CARTAO`
   - Windows: `python ferramentas\cartao.py E:\` (a letra do cartão)
3. Se estiver bem, o mesmo comando com `--fazer` no fim.
   O `cartao.py` começa por dizer `plugins em .../BIN/BPLUGINS: ...`: só entram no índice os ficheiros
   que o navegador consegue correr (os que têm plugin). Se só aparecer `MOD` e quase tudo ficar
   "sem plugin, fora", falta a pasta `BIN/BPLUGINS` do Bob Fossil (secção 2, passo 3).
   Se no Tang o navegador aparecer a preto e branco, com nomes curtos, é o do esxDOS: falta o `SYS/NMI.SYS`
   do Bob Fossil (mesmo passo), ou a pasta `cartao/` não ficou por cima.

Pode-se repetir sempre que se juntam jogos (ele refaz os índices). Sem índices tudo funciona na mesma,
só com os nomes curtos e mais devagar nas pastas muito grandes.

`fontes/` tem o código de tudo o que vai no cartão (navegador, GO*, PENTA, SOMNAV, NAVPT3, plugin MOD,
stub do TAP do 2068). Montam-se com o **sjasmplus**.

## 7. Ligações (de onde vem cada coisa)

- Tang Nano 20K, documentação da Sipeed: https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html
- Gowin EDA (Education) e Gowin Programmer: https://www.gowinsemi.com/en/support/download_eda/
- openFPGALoader: https://github.com/trabucayre/openFPGALoader
- esxDOS: https://www.esxdos.org
- Navegador e plugins do Bob Fossil (BPLUGINS), de que o nosso navegador partiu: http://www.thefossilrecord.co.uk
- FPGA Companion / Partner para o BL616 (teclado, rato, comando): https://github.com/MiSTle-Dev/FPGA-Companion
- HDMI com som: hdl-util/hdmi (Sameer Puri), https://github.com/hdl-util/hdmi , na versão do NanoMig do djnice: https://github.com/djnice/NanoMig
- Ferramentas de gravar o BL616 (BLDevCube, BLFlashCommand), Bouffalo Lab: https://dev.bouffalolab.com
- Firmware do General Sound (fontes): https://github.com/psbhlw/gs-firmware
- ROMs do ZX Spectrum 48K e 128K (a Amstrad autoriza a distribuição para emulação):
  https://worldofspectrum.org e https://spectrumcomputing.co.uk
- ROMs do Timex TC2048 e TC2068: https://www.timexsinclair.com
- sjasmplus (para montar os programas do cartão): https://github.com/z00m128/sjasmplus
- DivTIESUS (Miguel Angel Rodríguez Jodar): https://github.com/mcleod-ideafix/divtiesus
- T80 reparado e completado por mim em 2026 (registo Q): https://github.com/zambujal/T80-Q-fix
- O SCLD em CPLD, reparado e completado por mim (o scld.vhd de que o core partiu): https://github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex
- O modelo do SCLD do Load ZX Museum (Álvaro Lopes, Paulo Cortesão): https://github.com/LoadZX/timex_scld

## 8. O que está aqui e de quem é

**A base é o SCLD.** O chip do Timex (o SCLD, a "ULA" do TC2048/TC2068) está aqui como o modelo em VHDL
do Load ZX Museum, de **Álvaro Lopes** e Paulo Cortesão (CC BY-SA 4.0), que eu reparei e completei para
o meu CPLD de substituição do SCLD, o `scld.vhd` do github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex
(IN nos portos FF e F4, EXROM/HOME, modos de ecrã, contenção, 128K pelo F4/7FFD, barramento flutuante…),
testado num TC2068 verdadeiro. No `core_timextenso.vhd` está a parte desse SCLD que não é DRAM, reescrita para
o relógio do core; o resto (portos, modos, tempos) é o mesmo.

**O Z80 é o T80** (Daniel Wallner, Sorgelig), **que eu reparei e completei em 2026**: ao testar o Timextenso
reparei que o T80 falhava nos testes de flags do Z80 (o registo Q do Zilog nos SCF/CCF: os bits 3 e 5 dependem de a
instrução anterior ter escrito os flags; SET/RES não contam, POP AF e EX AF também não; o prefixo DD/FD
conta como instrução sem flags). Corrigi-o no `T80.vhd` daqui (comentários com a data) e em
github.com/zambujal/T80-Q-fix. Passa os testes todos.

Código próprio (GPL v3): o core `core_timextenso.vhd` e o `top.vhd`, o vídeo (`video_timex`), a ligação ao
HDMI (`src/hdmi/hdmi_hdlutil.sv`, `hdmi_tx.vhd`), a cassete, o som, a ponte do cartão, o programa de arranque e a sua letra, o
navegador (`fontes/nav`, com letra própria) e os restantes programas do cartão, o `cartao.py`.

Código escrito com ajuda de IA.

Código de outros, cada um com a sua licença (ver `LICENCAS.md`):
SCLD (Load ZX Museum, Álvaro Lopes, Paulo Cortesão, CC BY-SA 4.0), T80 (Daniel Wallner, Sorgelig),
YM2149 (MikeJ), General Sound, SID, sysctrl e mcu_spi (MiSTer / MiSTeryNano, GPL), DivTIESUS e
ULAplus (Miguel Angel Rodríguez Jodar / ZX-UNO, GPL v3), o leitor PT3 (S. V. Bulba), e o GO128
baseado no LOADROM do DivTIESUS (GPL v3).

Não estão aqui, por terem direitos ou serem de outros: as ROMs (Timex / Sinclair / Amstrad), o esxDOS
(www.esxdos.org), os plugins do navegador do Bob Fossil (www.thefossilrecord.co.uk), o firmware do BL616.
