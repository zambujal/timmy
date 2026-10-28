# Timmy — Timex TC2068 e TC2048 (e mais) num Tang Nano 20K

O Timmy é um core em VHDL para a placa **Sipeed Tang Nano 20K** (FPGA Gowin GW2AR-18) que faz de
**Timex TC2068** e **TC2048**, com saída **HDMI 720p50**, cartão **microSD** com **esxDOS** (DivMMC),
teclado USB e som pelo HDMI. Arranca como TC2048 e pelo navegador do cartão passa a **TC2068** (com a
EXROM, os modos de ecrã do Timex: hi-colour, hi-res 512x192, e esxDOS também nesse modo), a
**ZX Spectrum 48K / 128K** ou a **Pentagon 128/512/1024**, com **General Sound**, **TurboSound** (3 AY),
**SID**, **ULAplus**, rato Kempston, Z80 até 27 MHz e cassete TAP/TZX.

Precisa só do Tang Nano 20K, de um cartão microSD e de um teclado USB. (Há à parte uma placa com um
ESP32-S3 que dá menu com capas, rede, MP3 e mais; esse projecto depende deste e não é preciso para nada
do que está aqui.)

O core **não traz nenhuma ROM**: ao ligar, um pequeno programa de arranque lê do cartão a ROM do TC2048 e
o esxDOS, que cada um mete lá (ver "O cartão").

---

## 1. O que é preciso

- **Tang Nano 20K** (Sipeed). Qualquer revisão; a placa liga-se ao PC pelo USB-C.
- **Cartão microSD** formatado em **FAT32** (até 32 GB é o mais simples).
- **Teclado USB** e um adaptador **USB-C OTG** (ou um hub USB-C alimentado) para o ligar ao Tang.
- **Cabo HDMI** para uma TV ou monitor que aceite 720p a 50 Hz.
- No PC: o **Gowin EDA** (gratuito, versão *Education*, Windows ou Linux) só para o **Programmer**, ou o
  **openFPGALoader** em Linux.
- Dois ficheiros com direitos que não estão aqui:
  - a **ROM do TC2048** (16384 bytes) — ou a do ZX Spectrum 48K, que também serve;
  - o **esxDOS** (www.esxdos.org): o pacote traz a pasta `BIN`, a pasta `SYS` e o ficheiro `ESXMMC.BIN`.

## 2. O cartão

1. Formatar em FAT32.
2. Copiar do pacote do esxDOS as pastas **`BIN`**, **`SYS`** e **`TMP`** para a raiz do cartão.
3. Copiar para cima destas a pasta **`cartao/`** deste repositório (o `BIN` e o `SYS` daqui juntam-se aos do
   esxDOS: navegador, GO128/GO256/GO1024/GO2068, PENTA, plugin MOD, música de arranque).
4. Criar a pasta **`SYS/ROMS`** e meter lá:
   - `TC2048.ROM` — a ROM (16384 bytes);
   - `ESXMMC.BIN` — o esxDOS, tal como vem no pacote (8192 bytes).
5. Opcional, só para as outras máquinas e placas (também têm direitos, não estão aqui):
   - `BIN/128.rom` — a ROM do ZX Spectrum 128 (32768 bytes: ROM 0 + ROM 1), para o modo 128K e o
     Pentagon;
   - `BIN/2068.rom` — a do Timex TC2068 para o modo TC2068: ROM home de 16K + EXROM de 8K (24576
     bytes), ou com mais os 8K do esxDOS do 2068 a seguir (32768 bytes), que dá esxDOS nesse modo;
   - `BIN/GS105B.ROM` — o firmware do General Sound, versão 1.05b (32768 bytes), para o GS; as fontes
     estão em github.com/psbhlw/gs-firmware;
   - `BIN/PLUG2068/TAP` — plugin TAP para o TC2068, feito a partir do plugin TAP do esxDOS com
     `python3 fontes/plug2068/faz_plug2068.py BIN/BPLUGINS/TAP BIN/PLUG2068/TAP`.
   Sem eles o Timmy é um TC2048 com esxDOS; o navegador avisa quando falta um.
6. Os jogos vão em pastas na raiz (por exemplo `JOGOS/`, ou uma por letra).
7. **No fim, com o cartão no PC, corre o `ferramentas/cartao.py`** (secção 6): faz os índices que dão
   ao navegador os nomes compridos, a coluna das letras e a barra de cima com o menu das máquinas. Sem
   eles o navegador funciona, mas incompleto.

Resumindo, a raiz do cartão fica assim:

```
BIN/        esxDOS + os nossos (BROWSE.BIN, NAVHR.BIN, GO128, GO256, GO1024, GO2068, PENTA.BIN, NAVPT3.BIN,
            SOMNAV.BIN, BPLUGINS/MOD, BPLUGINS/CFG/MOD.CFG e MOD.INI)
            (opcionais: 128.rom, 2068.rom, GS105B.ROM, PLUG2068/TAP)
SYS/        esxDOS + NAV.SOM + ROMS/TC2048.ROM + ROMS/ESXMMC.BIN
TMP/        esxDOS
JOGOS/ ...  o que quiseres
```

## 3. Gravar o core no Tang Nano 20K

Há duas maneiras de ter o core: **usar o já compilado** (`timmy.fs`, na secção **Releases** deste
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
   - **FS File:** o `timmy.fs`
   - **External Flash:** `Generic Flash`, endereço `0x000000`
4. **Program** (o botão de gravar). Demora uns segundos. Desligar e voltar a ligar o Tang: o Timmy
   arranca.

### 3.2 Windows, com o openFPGALoader (ferramenta livre)

1. Instalar o **MSYS2** (www.msys2.org) e, no terminal "MSYS2 UCRT64":
   `pacman -S mingw-w64-ucrt-x86_64-openFPGALoader`
2. O Windows tem de dar a interface do programador ao driver **WinUSB**: correr o **Zadig**
   (zadig.akeo.ie), em *Options → List All Devices*, escolher a **interface 0** do programador do Tang
   (FT2232-compatível) e instalar o WinUSB. (Isto tira a interface ao driver FTDI; o Gowin Programmer
   deixa de a ver até se repor o driver FTDI, também com o Zadig.)
3. No mesmo terminal: `openFPGALoader -b tangnano20k -f timmy.fs`

### 3.3 Linux, com o openFPGALoader

```
sudo apt install openfpgaloader                      # Debian / Ubuntu
sudo dnf copr enable mobicarte/openFPGALoader && sudo dnf install openFPGALoader   # Fedora
openFPGALoader -b tangnano20k -f timmy.fs
```

Se der "unable to open ftdi device" é permissão de USB: correr com `sudo` ou instalar as regras udev
que vêm com o openFPGALoader (`99-openfpgaloader.rules`). O Gowin Programmer também existe para Linux
e faz o mesmo que em Windows.

### 3.4 Compilar o core (opcional)

Com o Gowin EDA (1.9.11 ou mais recente; a versão Education chega), na pasta `core/`:

```
gw_sh timmy.tcl
```

Demora uns 10 minutos num PC normal (o core enche a FPGA quase toda) e no fim o Gowin às vezes queixa-se ao fechar;
se o `.fs` apareceu, está feito. O resultado fica em `core/impl/pnr/*.fs`. Não precisa de ROM nenhuma: o programa de arranque
(`arranque.hex`) já está feito; para o refazer, `sjasmplus arranque/arranque.asm` e converter o
`.bin` para `.hex` (um byte por linha, em hexadecimal). Com as ferramentas livres (GHDL + yosys +
nextpnr-himbaechel + apicula) ainda não experimentámos; o core usa PLLs e serializadores da Gowin,
por isso é provável que precise de adaptações.

## 4. Ligar e usar

- Ligar o cartão, o HDMI e o teclado; alimentar o Tang pelo USB-C (um carregador USB chega).
- Ao ligar aparece "TIMMY - ARRANQUE" um instante (o programa a ler as ROMs do cartão) e depois o
  esxDOS e o BASIC do TC2048. Se faltar alguma coisa no cartão, o ecrã diz o quê e a borda fica
  vermelha; corrige-se o cartão e ele tenta sozinho de 2 em 2 s.
- **Os dois botões do Tang:**
  - o do **pino 87** é o **NMI**: abre o navegador do cartão. Nele: ENTER num ficheiro carrega-o
    (TAP, TZX, SNA, Z80, TRD, PT3 e outros formatos AY, MOD no General Sound); o menu das máquinas
    muda para 48K / 128K / Timex 128 / TC2068 / Pentagon e liga o General Sound e o TurboSound. As
    teclas estão em `docs/teclas.md`.
  - o do **pino 88** anda numa lista de 16 escolhas, mostrada em binário nos 4 LEDs (que ficam acesos
    com o número escolhido). O botão do NMI faz então essa escolha em vez do NMI: 0 (LEDs apagados)
    NMI, 1 `.ls`, 2 `.go128`, 3 `.go128 -penta`, 4 `.go1024`, 5 `.go2068`, 6 RESET+NMI (volta ao
    TC2048), 8 RESET, 10 `.gs`, 15 turbo. Para voltar ao NMI normal, carrega até os LEDs apagarem.
    Carregado 3 s troca de core (multiboot, se houver outro em `0x100000`).
- Pelo teclado, sem a placa ESP32, não há tecla de NMI: é o botão.

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

- Do release do FPGA-Companion para o Tang Nano 20K: `bl616_fpga_partner_nano20k.bin`,
  `fpga_companion_nano20k.bin` e o `flash_nano20k.ini` (grava os dois: o Partner em `0x000000` e o
  Companion em `0x40000`).
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

Pode-se repetir sempre que se juntam jogos (ele refaz os índices). Sem índices tudo funciona na mesma,
só com os nomes curtos e mais devagar nas pastas muito grandes.

`fontes/` tem o código de tudo o que vai no cartão (navegador, GO*, PENTA, SOMNAV, NAVPT3, plugin MOD,
stub do TAP do 2068). Montam-se com o **sjasmplus**.

## 7. Ligações (de onde vem cada coisa)

- Tang Nano 20K, documentação da Sipeed: https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html
- Gowin EDA (Education) e Gowin Programmer: https://www.gowinsemi.com/en/support/download_eda/
- openFPGALoader: https://github.com/trabucayre/openFPGALoader
- esxDOS: https://www.esxdos.org
- FPGA Companion / Partner para o BL616 (teclado, rato, comando): https://github.com/MiSTle-Dev/FPGA-Companion
- Ferramentas de gravar o BL616 (BLDevCube, BLFlashCommand), Bouffalo Lab: https://dev.bouffalolab.com
- Firmware do General Sound (fontes): https://github.com/psbhlw/gs-firmware
- ROMs do ZX Spectrum 48K e 128K (a Amstrad autoriza a distribuição para emulação):
  https://worldofspectrum.org e https://spectrumcomputing.co.uk
- ROMs do Timex TC2048 e TC2068: https://www.timexsinclair.com
- sjasmplus (para montar os programas do cartão): https://github.com/z00m128/sjasmplus
- DivTIESUS (Miguel Angel Rodríguez Jodar): https://github.com/mcleod-ideafix/divtiesus
- T80 com a correcção do registo Q: https://github.com/zambujal/T80-Q-fix

## 8. O que está aqui e de quem é

Código próprio (GPL v3): o core `core_timmy.vhd` e o `top.vhd`, o vídeo e o HDMI (`video_timex`,
`hdmi_tx`, `tmds_enc`), a cassete, o som, a ponte do cartão, o programa de arranque e a sua letra, o
navegador (`fontes/nav`, com letra própria) e os restantes programas do cartão, o `cartao.py`.

Código de outros, cada um com a sua licença (ver `LICENCAS.md`):
T80 (Daniel Wallner, Sorgelig), YM2149 (MikeJ), General Sound, SID, sysctrl e mcu_spi (MiSTer /
MiSTeryNano, GPL), DivTIESUS e ULAplus (Miguel Angel Rodríguez Jodar / ZX-UNO, GPL v3), o leitor
PT3 (S. V. Bulba), e o GO128 baseado no LOADROM do DivTIESUS (GPL v3).

Não estão aqui, por terem direitos: as ROMs (Timex / Sinclair / Amstrad), o esxDOS e os seus
plugins (www.esxdos.org), o firmware do BL616.
