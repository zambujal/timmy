# Timmy — Timex TC2048 (e mais) numa Tang Nano 20K

O Timmy é um core em VHDL para a placa **Sipeed Tang Nano 20K** (FPGA Gowin GW2AR-18) que faz de
Timex TC2048, com saída **HDMI 720p50**, cartão **microSD** com **esxDOS** (DivMMC), teclado USB e
som pelo HDMI. Pelo navegador que vem no cartão muda-se para **ZX Spectrum 48K / 128K**, **Timex
TC2068** e **Pentagon 128/512/1024**, com **General Sound**, **TurboSound** (3 AY), **SID**, **ULAplus**,
rato Kempston, Z80 até 27 MHz e cassete TAP/TZX.

Precisa só da Tang Nano 20K, de um cartão microSD e de um teclado USB. (Há à parte uma placa com um
ESP32-S3 que dá menu com capas, rede, MP3 e mais; esse projecto depende deste e não é preciso para nada
do que está aqui.)

O core **não traz nenhuma ROM**: ao ligar, um pequeno programa de arranque lê do cartão a ROM do TC2048 e
o esxDOS, que cada um mete lá (ver "O cartão").

---

## 1. O que é preciso

- **Tang Nano 20K** (Sipeed). Qualquer revisão; a placa liga-se ao PC pelo USB-C.
- **Cartão microSD** formatado em **FAT32** (até 32 GB é o mais simples).
- **Teclado USB** e um adaptador **USB-C OTG** (ou um hub USB-C alimentado) para o ligar à Tang.
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
5. Opcional, para o modo TC2068: `BIN/2068.rom` (ver `cartao/LEIAME.txt`).
6. Opcional, para o TAP no TC2068: `BIN/PLUG2068/TAP`, feito a partir do plugin TAP do esxDOS com
   `python3 fontes/plug2068/faz_plug2068.py BIN/BPLUGINS/TAP BIN/PLUG2068/TAP`.
7. Os jogos vão em pastas na raiz (por exemplo `JOGOS/`, ou uma por letra). O navegador vê qualquer pasta;
   para pastas com milhares de ficheiros, `ferramentas/cartao.py` faz índices que o tornam instantâneo
   (ver "Ferramentas"). Não é obrigatório.

Resumindo, a raiz do cartão fica assim:

```
BIN/        esxDOS + os nossos (BROWSE.BIN, NAVHR.BIN, GO128, GO256, GO1024, GO2068, PENTA.BIN, NAVPT3.BIN,
            SOMNAV.BIN, BPLUGINS/MOD, BPLUGINS/CFG/MOD.CFG e MOD.INI)
SYS/        esxDOS + NAV.SOM + ROMS/TC2048.ROM + ROMS/ESXMMC.BIN
TMP/        esxDOS
JOGOS/ ...  o que quiseres
```

## 3. Gravar o core na Tang Nano 20K

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
4. **Program** (o botão de gravar). Demora uns segundos. Desligar e voltar a ligar a Tang: o Timmy
   arranca.

### 3.2 Windows, com o openFPGALoader (ferramenta livre)

1. Instalar o **MSYS2** (www.msys2.org) e, no terminal "MSYS2 UCRT64":
   `pacman -S mingw-w64-ucrt-x86_64-openFPGALoader`
2. O Windows tem de dar a interface do programador ao driver **WinUSB**: correr o **Zadig**
   (zadig.akeo.ie), em *Options → List All Devices*, escolher a **interface 0** do programador da Tang
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

O resultado fica em `core/impl/pnr/*.fs`. Não precisa de ROM nenhuma: o programa de arranque
(`arranque.hex`) já está feito; para o refazer, `sjasmplus arranque/arranque.asm` e converter o
`.bin` para `.hex` (um byte por linha, em hexadecimal). Com as ferramentas livres (GHDL + yosys +
nextpnr-himbaechel + apicula) ainda não experimentámos; o core usa PLLs e serializadores da Gowin,
por isso é provável que precise de adaptações.

## 4. Ligar e usar

- Ligar o cartão, o HDMI e o teclado; alimentar a Tang pelo USB-C (um carregador USB chega).
- Ao ligar aparece "TIMMY - ARRANQUE" um instante (o programa a ler as ROMs do cartão) e depois o
  esxDOS e o BASIC do TC2048. Se faltar alguma coisa no cartão, o ecrã diz o quê e a borda fica
  vermelha; corrige-se o cartão e ele tenta sozinho de 2 em 2 s.
- **NMI** (o botão da Tang ou a tecla do teclado, ver `docs/teclas.md`): abre o navegador. Nele:
  ENTER num ficheiro carrega-o (TAP, TZX, SNA, Z80, TRD, PT3 e outros formatos AY, MOD no General Sound);
  o menu das máquinas muda para 48K / 128K / Timex 128 / TC2068 / Pentagon e liga o General Sound e o
  TurboSound. As teclas estão em `docs/teclas.md`.

## 5. O teclado USB (firmware do BL616)

A Tang Nano 20K tem um chip BL616 que de fábrica é o programador da FPGA. Para o teclado USB falar com o
core, o BL616 tem de ter o firmware **FPGA Companion** (de Till Harbaum / MiSTle-Dev,
github.com/MiSTle-Dev/FPGA-Companion), que vem com o **FPGA Partner**: com o Partner, a placa arranca como
programador se estiver ligada a um PC e como teclado se não estiver, sem andar a trocar firmware.

Gravar o firmware do BL616 é por conta e risco de cada um: as placas feitas a partir do início de 2024
são "cifradas" e só aceitam firmware cifrado; um firmware errado deixa a placa sem programador até se
voltar a gravar o de fábrica (que também está nos releases do FPGA-Companion). Passos, com o
**BLDevCube** (Windows) ou o **BLFlashCommand** (Linux) do Bouffalo Lab:

1. Ligar a Tang ao PC **com o botão UPDATE carregado** (está ao lado do HDMI). Aparece uma porta série
   "Bouffalo CDC DEMO".
2. Gravar `bl616_fpga_partner_nano20k.bin` no endereço `0x000000` e `fpga_companion_nano20k.bin` no
   `0x40000` (o `flash_nano20k.ini` do pacote do FPGA-Companion faz as duas).
3. Desligar e ligar. Com um PC ligado directamente (sem hub) é programador ("USB Debugger"); com o
   teclado num adaptador OTG ou hub alimentado, é teclado.

Nota: com o Partner, se a placa estiver ligada ao PC através de um hub USB, pode não aparecer como
programador — ligar directamente.

## 6. Ferramentas

- `ferramentas/cartao.py` + `config.ini`: no PC, arruma as pastas de jogos por letra, mete a máquina no
  nome e faz os índices do navegador (`_NAV/*.IDX`) — para cartões com milhares de jogos. Sem índices
  o navegador mostra as pastas tal como estão, só mais devagar nas muito grandes.
  `python3 cartao.py E:\` mostra o que faria; `--fazer` faz.
- `fontes/`: o código de tudo o que vai no cartão (navegador, GO*, PENTA, SOMNAV, NAVPT3, plugin MOD,
  stub do TAP do 2068). Montam-se com o **sjasmplus**.

## 7. O que está aqui e de quem é

Código próprio (GPL v3): o core `core_timmy.vhd` e o `top.vhd`, o vídeo e o HDMI (`video_timex`,
`hdmi_tx`, `tmds_enc`), a cassete, o som, a ponte do cartão, o programa de arranque e a sua letra, o
navegador (`fontes/nav`, com letra própria) e os restantes programas do cartão, o `cartao.py`.

Código de outros, cada um com a sua licença (ver `LICENCAS.md`):
T80 (Daniel Wallner, Sorgelig), YM2149 (MikeJ), General Sound, SID, sysctrl e mcu_spi (MiSTer /
MiSTeryNano, GPL), DivTIESUS e ULAplus (Miguel Angel Rodríguez Jodar / ZX-UNO, GPL v3), o leitor
PT3 (S. V. Bulba), e o GO128 baseado no LOADROM do DivTIESUS (GPL v3).

Não estão aqui, por terem direitos: as ROMs (Timex / Sinclair / Amstrad), o esxDOS e os seus
plugins (www.esxdos.org), o firmware do BL616.
