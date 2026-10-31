# Timextenso — Timex TC2068 and TC2048 (and more) on a Tang Nano 20K

*Em português: [README.md](README.md)*

Timextenso is a VHDL core for the **Sipeed Tang Nano 20K** board (Gowin GW2AR-18 FPGA) that behaves as a
**Timex TC2068** and **TC2048**, with **HDMI 720p50** output, a **microSD** card with **esxDOS** (DivMMC),
a USB keyboard and sound over HDMI. It boots as a TC2048 and, from the card browser, switches to a
**TC2068** (with the EXROM, the Timex screen modes — hi-colour, 512x192 hi-res — and esxDOS in that mode too),
a **ZX Spectrum 48K / 128K** or a **Pentagon 128/512/1024**, with **General Sound**, **TurboSound** (3 AYs),
**ULAplus**, a Kempston mouse and a Z80 up to 27 MHz. (The SID is in the sources, `core/src/sid`, on port CF
like the ZX-TSid, but **switched off** in this core — `SID := false` in `top.vhd`, for lack of BSRAM.
`cassete.vhd` is a tape player fed by the ESP board: without that board there is no tape, and TAPs load
through the esxDOS plugin.)

All it needs is the Tang Nano 20K, a microSD card and a USB keyboard. (There is a separate board with an
ESP32-S3 that adds a menu with covers, network, NAS, MP3 and more; that is another project, it depends on
this one and is not needed for anything here: none of it is in this core.)

The core **ships with no ROM**: at power-up a small boot program reads the TC2048 ROM and esxDOS from the
card, which each user puts there (see "The card").

---

## 1. What you need

- **Tang Nano 20K** (Sipeed), version **3921** or **3923** — the number printed on the board under the FPGA.
  The core is the same on both (the FPGA pins did not change); what changes on the 3923, from mid-2026, is the
  BL616 keyboard chip, which needs the **3923 Companion** firmware (section 5). The board connects to the PC
  over USB-C.
- **microSD card** formatted as **FAT32** (up to 32 GB is simplest).
- **USB keyboard** and a **USB-C OTG** adapter (or a powered USB-C hub) to plug it into the Tang.
- **HDMI cable** to a TV or monitor that accepts 720p at 50 Hz.
- On the PC: **Gowin EDA** (free, *Education* edition, Windows or Linux), only for the **Programmer**, or
  **openFPGALoader** on Linux.
- Things that belong to others and are not here:
  - the **TC2048 ROM** (16384 bytes) — or the ZX Spectrum 48K one, which also works — which the core boots with;
  - for the **TC2068** mode, the **TC2068 ROM** (16K home + 8K EXROM, `BIN/2068.rom`; and for 128K / Pentagon
    the Spectrum 128 ROM, `BIN/128.rom`) — see step 6 of the card;
  - **esxDOS** (www.esxdos.org): the package brings the `BIN` folder, the `SYS` folder and the file `ESXMMC.BIN`;
  - **Bob Fossil's browser** (http://www.thefossilrecord.co.uk, `BROWSE_latest.zip`): it brings the
    `SYS/NMI.SYS` that loads an external browser, and the **plugins** `BIN/BPLUGINS` (TAP, Z80, SNA, TRD,
    PT3…). esxDOS **does not** ship them. Our browser was built on top of his, is entered through his NMI.SYS
    and runs the games through these plugins: without them you get the black-and-white esxDOS browser, and
    the indexes come out empty.

## 2. The card

1. Format as FAT32.
2. Copy the **`BIN`**, **`SYS`** and **`TMP`** folders from the esxDOS package to the root of the card.
3. Copy the whole **Bob Fossil** browser zip on top (its `BIN` with the `BPLUGINS`, and its **`SYS/NMI.SYS`**:
   the esxDOS NMI.SYS has a black-and-white browser built in and never loads `/BIN/BROWSE.BIN`; Bob Fossil's
   loads it, and that is how ours gets in).
4. Copy the **`cartao/`** folder of this repository on top of those (its `BIN` and `SYS` merge with the esxDOS
   ones: browser, GO128/GO256/GO1024/GO2068, PENTA, MOD plugin, boot sound).
5. Create the **`SYS/ROMS`** folder and put there:
   - `TC2048.ROM` — the ROM (16384 bytes);
   - `ESXMMC.BIN` — esxDOS, as it comes in the package (8192 bytes).
6. Optional, only for the other machines and boards (also copyrighted, not here):
   - `BIN/128.rom` — the ZX Spectrum 128 ROM (32768 bytes: ROM 0 + ROM 1), for the 128K mode and the Pentagon;
   - `BIN/2068.rom` — the Timex TC2068 one for the TC2068 mode: 16K home ROM + 8K EXROM (24576 bytes), or with
     the 8K of the 2068 esxDOS appended (32768 bytes), which gives esxDOS in that mode;
   - `BIN/GS105B.ROM` — the General Sound firmware, version 1.05b (32768 bytes), for the GS; sources at
     github.com/psbhlw/gs-firmware;
   - `BIN/PLUG2068/TAP` — TAP plugin for the TC2068 (**without it TAPs do not load from the browser in TC2068
     mode**). It is not in the repository because it is made from Bob Fossil's TAP plugin; make it with
     `python3 fontes/plug2068/faz_plug2068.py BIN/BPLUGINS/TAP BIN/PLUG2068/TAP` (`faz_cartao.sh` already does it; what it is and why: `fontes/plug2068/LEIAME.md`).
   Without them Timextenso is a TC2048 with esxDOS; the browser tells you when one is missing.
7. Games go in folders at the root (for example `GAMES/`, or one per letter).
8. **Finally, with the card in the PC, run `ferramentas/cartao.py`** (section 6): it builds the indexes that
   give the browser the long names, the letter column and the top bar with the machine menu. Without them the
   browser works, but incomplete.

On Linux, steps 2, 3, 4 and 8 (and `BIN/PLUG2068/TAP`) are done in one go by `ferramentas/faz_cartao.sh` (it downloads Bob Fossil's
zip itself; you put the ROMs in afterwards, or before):

```
cd timextenso/ferramentas && ./faz_cartao.sh /run/media/$USER/CARD_NAME ~/Downloads/esxdos089.zip
```

In short, the root of the card ends up like this:

```
BIN/        esxDOS + Bob Fossil's BPLUGINS/ (TAP, Z80, SNA, TRD, PT3...) + ours (BROWSE.BIN, NAVHR.BIN,
            GO128, GO256, GO1024, GO2068, PENTA.BIN, NAVPT3.BIN, SOMNAV.BIN, BPLUGINS/MOD, BPLUGINS/CFG/MOD.CFG and MOD.INI)
            (optional: 128.rom, 2068.rom, GS105B.ROM, PLUG2068/TAP)
SYS/        esxDOS + Bob Fossil's NMI.SYS + NAV.SOM + ROMS/TC2048.ROM + ROMS/ESXMMC.BIN
TMP/        esxDOS
GAMES/ ...  whatever you like
```

## 3. Flashing the core into the Tang Nano 20K

There are two ways to get the core: **use the prebuilt one** (`timextenso.fs`, in the **Releases** section of
this repository) or **build it** with Gowin EDA (section 3.4). Either way the `.fs` file is written to the
board's flash and stays there until another one is written.

The board connects to the PC over USB-C. With the factory BL616 firmware it shows up as an FTDI programmer
("20K's FRIEND"); with the keyboard + Partner firmware (section 5) it shows up as a programmer when plugged
**directly into a PC port, with no hub**.

### 3.1 Windows, with the Gowin Programmer

1. Install **Gowin EDA Education** (www.gowinsemi.com, free registration needed). The programmer's USB
   drivers are installed with it.
2. Open the **Gowin Programmer** (in Gowin EDA: "Program Device") and click **scan_device**: a
   **GW2AR-18C** should appear. OK.
3. Double-click the device row ("Operation" column) to open the configuration:
   - **Access Mode:** `External Flash Mode`
   - **Operation:** `exFlash Erase, Program`
   - **FS File:** `timextenso.fs`
   - **External Flash:** `Generic Flash`, address `0x000000`
4. **Program** (the flash button). It takes a few seconds. Power the Tang off and on: Timextenso boots.

### 3.2 Windows, with openFPGALoader (free tool)

1. Install **MSYS2** (www.msys2.org) and, in the "MSYS2 UCRT64" terminal:
   `pacman -S mingw-w64-ucrt-x86_64-openFPGALoader`
2. Windows has to hand the programmer interface to the **WinUSB** driver: run **Zadig** (zadig.akeo.ie),
   *Options → List All Devices*, pick **interface 0** of the Tang's programmer (FT2232-compatible) and install
   WinUSB. (This takes the interface away from the FTDI driver; the Gowin Programmer stops seeing it until the
   FTDI driver is restored, also with Zadig.)
3. In the same terminal: `openFPGALoader -b tangnano20k -f timextenso.fs`

### 3.3 Linux, with openFPGALoader

```
sudo apt install openfpgaloader                      # Debian / Ubuntu
sudo dnf copr enable mobicarte/openFPGALoader && sudo dnf install openFPGALoader   # Fedora
openFPGALoader -b tangnano20k -f timextenso.fs
```

"unable to open ftdi device" is a USB permission problem: run with `sudo` or install the udev rules that
ship with openFPGALoader (`99-openfpgaloader.rules`). The Gowin Programmer also exists for Linux and does the
same as on Windows.

### 3.4 Building the core (optional)

**TV that does not accept 720p?** In the `core/` folder, `./faz_576p.sh` gives `core/timextenso_576p.fs`: the same
core at 576p50 (4:3). The ESP menu does not look right at 576p.


With Gowin EDA (1.9.11 or newer; the Education edition is enough), in the `core/` folder:

```
gw_sh timextenso.tcl
```

It takes about 10 minutes on an ordinary PC (the core fills almost the whole FPGA) and at the end Gowin
sometimes complains while closing; if the `.fs` appeared, it is done. The result is in `core/impl/pnr/*.fs`.
No ROM is needed: the boot program (`arranque.hex`) is already built; to rebuild it, `sjasmplus
arranque/arranque.asm` and convert the `.bin` to `.hex` (one byte per line, in hexadecimal). We have not yet
tried the open-source tools (GHDL + yosys + nextpnr-himbaechel + apicula); the core uses Gowin PLLs and
serializers, so it will probably need adapting.

## 4. Powering up and using it

- Plug in the card, the HDMI and the keyboard; power the Tang over USB-C from a **2 A charger** (or a powered
  hub). A PC USB port is enough for the Tang alone, but not for the Tang with the ESP board: the WiFi current
  spikes pull the 5 V down and the HDMI drops out for an instant. Keep the PC for flashing only.
- At power-up "TIMEXTENSO - ARRANQUE" shows for an instant (the boot program reading the ROMs from the card),
  then esxDOS and the TC2048 BASIC. If something is missing from the card, the screen says what and the
  border turns red; fix the card and it retries by itself every 2 s.
- **The two buttons on the Tang:**
  - the **pin 87** one is the **NMI**: it opens the card browser. There, ENTER on a file loads it
    (TAP, SNA, Z80, TRD, PT3 and other AY formats, MOD on the General Sound; not TZX, which needs the ESP
    board); the machine menu switches to 48K / 128K / Timex 128 / TC2068 / Pentagon and turns on the General
    Sound and the TurboSound. The keys are in `docs/teclas.md`.
  - the **pin 88** one steps through a list of 16 choices, shown in binary on the 4 LEDs (which stay lit
    with the chosen number). The NMI button then performs that choice instead of the NMI: 0 (LEDs off) NMI,
    1 `.ls`, 2 `.go128`, 3 `.go128 -penta`, 4 `.go1024`, 5 `.go2068`, 6 RESET+NMI (back to the TC2048),
    8 RESET, 10 `.gs`, 15 turbo. To get back to the plain NMI, press until the LEDs go off. Held for 3 s it
    switches core (multiboot, if there is another one at `0x100000`).
- From the keyboard, without the ESP32 board, there is no NMI key: it is the button.
- **Start-up machine** (without the ESP32 board): in the machine menu, **D** on a machine saves it in
  `/SYS/ARRANQUE.CFG`. The Tang always powers up as a TC2048 and, about 2 s later, switches by itself to that
  machine (the core gives an NMI and the browser does what ENTER does in the menu). D on TIMEX 2048 goes back to
  normal. With the ESP32 board connected it does nothing (as always).
- **Pentagon 128 or 1024?** For Pentagon *128* demos and games use **Pentagon 128**: in esxDOS type
  `.go128 -penta` (or pick it in the machine menu). In **Pentagon 1024** (`.go1024`) bits 5, 6 and 7 of port
  7FFD select banks — a 128 demo that writes them (many do) jumps to another memory area halfway through:
  black screen and broken music. 1024 is only for what asks for it (16C mode, 512K/1024K).

## 5. USB keyboard, mouse and gamepad (BL616 firmware)

The Tang Nano 20K has a **BL616** chip that, from the factory, is only the FPGA programmer. For the USB
keyboard, the mouse (Kempston) and the gamepad (Kempston joystick) to reach the core, the BL616 must run the
**FPGA Companion** firmware by Till Harbaum (github.com/MiSTle-Dev/FPGA-Companion), which comes with the
**FPGA Partner**: with the Partner, the board boots as a programmer if it is plugged into a PC at power-up
and as a keyboard if it is not. It is flashed once and never touched again.

**Warning:** boards made from early 2024 on are "encrypted" and only accept encrypted firmware (the one in
the recent FPGA-Companion releases is). With the wrong firmware the board stops showing up on USB until
another one is flashed; the factory firmware ("Friend 20K", in both versions, plain and encrypted) is in the
FPGA-Companion repository and is flashed the same way. Nobody ends up with a bricked board, but it is at your
own risk.

### 5.1 What to download

- **3921 board**: from the FPGA-Companion release for the Tang Nano 20K: `bl616_fpga_partner_nano20k.bin`,
  `fpga_companion_nano20k.bin` and `flash_nano20k.ini` (it flashes both: the Partner at `0x000000` and the
  Companion at `0x40000`).
- **3923 board**: the 3921 Companion gives no keyboard (the BL616's SPI is on other pins). From the same
  FPGA-Companion release (since late October 2026): `bl616_fpga_partner_nano20k_v3923.bin`,
  `fpga_companion_nano20k_v3923.bin` and `flash_nano20k_v3923.ini`. The Companion shipped with NextNano for the
  3923 (`fpga_companion_tn20k_3923.bin`) also works. Flash only one Companion, never both.
- There is no way to tell the version with the BL616 in flashing mode: read the number on the board, and if
  the keyboard does not show up with one Companion, flash the other — it does no harm.
- Bouffalo Lab's flashing tool: on Windows **BLDevCube** (graphical); on Linux **BLFlashCommand**, which
  comes in the same "Bouffalo Flash Cube" package / in the Bouffalo SDK
  (`tools/bflb_tools/bouffalo_flash_cube/`).

### 5.2 Putting the BL616 into flashing mode

With the Tang **unpowered**, press the **UPDATE** button (the one next to the HDMI) and, holding it, plug
the USB into the PC. A new serial port appears, "Bouffalo CDC DEMO": on Windows a `COMx`, on Linux
`/dev/ttyACM0` (or another number; `ls /dev/ttyACM*`). The button can be released.

### 5.3 Flashing

**Linux**, in the folder with the three files:

```
sudo ./BLFlashCommand --interface=uart --baudrate=2000000 --port=/dev/ttyACM0 --chipname=bl616 --cpu_id= --config=flash_nano20k.ini
```

It ends with "All programming completed successfully".

**Windows**, in BLDevCube: pick the **BL616/618** chip; under *Single download option* put
`bl616_fpga_partner_nano20k.bin` at address `0x0`; pick the board's `COMx` and *Create & Download*. Repeat
with `fpga_companion_nano20k.bin` at address `0x40000`. (Or import `flash_nano20k.ini`, which has both.)

### 5.4 Using it

- Power the Tang off and on (without UPDATE).
- **To play:** the keyboard (or a hub with keyboard, mouse and gamepad) into the Tang's USB-C through an
  OTG adapter; power comes from the hub (if powered) or from a charger on a hub with a power input. The
  core sees the keyboard, the mouse and the gamepad.
- **To flash a new core:** plug the Tang **directly into a PC port** (on a hub it may not show up): the
  Partner boots as a programmer ("USB Debugger") and the Gowin Programmer or openFPGALoader work as in
  section 3. To play again, just swap the cable.
- The Tang must really lose power when switching from one to the other: the BL616 only decides the mode at
  boot.

## 6. Tools: the browser indexes (important)

**Do this early:** without indexes the browser is incomplete. It reads each folder through esxDOS, but the
names show up short, in 8.3 (`JETSETW~1.TAP`), there is no letter column and no **top bar with the machine**
(where ENTER opens the menu of machines and boards), and a folder with thousands of files takes a while to
open. Without an index, the machine menu only opens with keys 1 to 4. The **indexes** are `_NAV/*.IDX` files
that `ferramentas/cartao.py` writes in each folder, on the PC, with each game's long name, 8.3 name and
machine; with them the browser shows the full names, the machine (`[48K]`, `[128K]`…), the letters in the
left column, and opens any folder instantly. Along the way `cartao.py` tidies the collection: splits by
letter and title and puts the machine in the file names. It only needs Python 3.

1. In `ferramentas/config.ini` you say what it does with each folder (names separated by spaces):
   - `jogos = GAMES DEMOS` — game folders: tidies them, puts the machine in the name and indexes them
     (`jogos =` empty: none; line absent: all root folders except the system ones and `FAVORITOS`);
   - `indexar = FAVORITOS MUSICA` — folders it only indexes, without touching names or order
     (`tudo` = the whole card);
   - under `[pastas]`, the ones that appear in the browser's bottom bar (`FAVORI = FAVORITOS`).
   The same can be given on the command line, with `--pastas`, `--indexar` and `--pasta`, which override
   `config.ini`; `--so-indices` only builds the indexes of the whole card.
2. With the card in the PC, first just to see what it would do:
   - Linux: `python3 ferramentas/cartao.py /run/media/$USER/CARD_NAME`
   - Windows: `python ferramentas\cartao.py E:\` (the card's drive letter)
3. If it looks right, the same command with `--fazer` at the end.
   `cartao.py` starts by printing `plugins em .../BIN/BPLUGINS: ...`: only files the browser can run (the
   ones with a plugin) go into the index. If only `MOD` is listed and almost everything comes out as
   "sem plugin, fora" (no plugin, left out), Bob Fossil's `BIN/BPLUGINS` folder is missing (section 2, step 3).
   If on the Tang the browser shows up black and white, with short names, it is the esxDOS one: Bob Fossil's
   `SYS/NMI.SYS` is missing (same step), or the `cartao/` folder did not go on top.

It can be run again whenever games are added (it rebuilds the indexes). Without indexes everything still
works, only with short names and slower in very large folders.

`fontes/` has the source of everything that goes on the card (browser, GO*, PENTA, SOMNAV, NAVPT3, MOD
plugin, 2068 TAP stub). They are assembled with **sjasmplus**.

## 7. Links (where each thing comes from)

- Tang Nano 20K, Sipeed documentation: https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html
- Gowin EDA (Education) and Gowin Programmer: https://www.gowinsemi.com/en/support/download_eda/
- openFPGALoader: https://github.com/trabucayre/openFPGALoader
- esxDOS: https://www.esxdos.org
- Bob Fossil's browser and plugins (BPLUGINS), which our browser started from: http://www.thefossilrecord.co.uk
- FPGA Companion / Partner for the BL616 (keyboard, mouse, gamepad): https://github.com/MiSTle-Dev/FPGA-Companion
- HDMI with sound: hdl-util/hdmi (Sameer Puri), https://github.com/hdl-util/hdmi , in djnice's NanoMig version: https://github.com/djnice/NanoMig
- BL616 flashing tools (BLDevCube, BLFlashCommand), Bouffalo Lab: https://dev.bouffalolab.com
- General Sound firmware (sources): https://github.com/psbhlw/gs-firmware
- ZX Spectrum 48K and 128K ROMs (Amstrad allows distribution for emulation):
  https://worldofspectrum.org and https://spectrumcomputing.co.uk
- Timex TC2048 and TC2068 ROMs: https://www.timexsinclair.com
- sjasmplus (to assemble the card programs): https://github.com/z00m128/sjasmplus
- DivTIESUS (Miguel Angel Rodríguez Jodar): https://github.com/mcleod-ideafix/divtiesus
- T80 repaired and completed by me in 2026 (Q register): https://github.com/zambujal/T80-Q-fix
- The SCLD on a CPLD, repaired and completed by me (the scld.vhd the core started from): https://github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex
- The Load ZX Museum SCLD model (Álvaro Lopes, Paulo Cortesão): https://github.com/LoadZX/timex_scld

## 8. What is here and whose it is

**The base is the SCLD.** The Timex chip (the SCLD, the "ULA" of the TC2048/TC2068) is here as the Load ZX
Museum VHDL model, by **Álvaro Lopes** and Paulo Cortesão (CC BY-SA 4.0), which I repaired and completed for
my SCLD replacement CPLD, the `scld.vhd` of github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex
(IN on ports FF and F4, EXROM/HOME, screen modes, contention, 128K through F4/7FFD, floating bus…), tested
in a real TC2068. `core_timextenso.vhd` holds the non-DRAM part of that SCLD, rewritten for the core's clock;
the rest (ports, modes, timings) is the same.

**The Z80 is the T80** (Daniel Wallner, Sorgelig), **which I repaired and completed in 2026**: while testing
Timextenso I noticed the T80 failed the Z80 flag tests (the Zilog Q register on SCF/CCF: bits 3 and 5 depend on
whether the previous instruction wrote the flags; SET/RES do not count, nor do POP AF and EX AF; a DD/FD
prefix counts as an instruction that does not write flags). I fixed it in the `T80.vhd` here (comments carry
the date) and in github.com/zambujal/T80-Q-fix. It passes all the tests.

Own code (GPL v3): the core `core_timextenso.vhd` and `top.vhd`, the video (`video_timex`), the glue to the HDMI
(`src/hdmi/hdmi_hdlutil.sv`, `hdmi_tx.vhd`), the tape, the sound, the card bridge, the boot program and its font, the browser (`fontes/nav`,
with its own font) and the other card programs, `cartao.py`.

Code written with the help of AI.

Code by others, each under its own licence (see `LICENCAS.md`):
SCLD (Load ZX Museum, Álvaro Lopes, Paulo Cortesão, CC BY-SA 4.0), T80 (Daniel Wallner, Sorgelig),
YM2149 (MikeJ), General Sound, SID, sysctrl and mcu_spi (MiSTer / MiSTeryNano, GPL), DivTIESUS and
ULAplus (Miguel Angel Rodríguez Jodar / ZX-UNO, GPL v3), the PT3 player (S. V. Bulba), and GO128 based on
the DivTIESUS LOADROM (GPL v3).

Not here, being copyrighted or someone else's: the ROMs (Timex / Sinclair / Amstrad), esxDOS
(www.esxdos.org), Bob Fossil's browser plugins (www.thefossilrecord.co.uk), the BL616 firmware.
