# PLUG2068 — carregar TAP no modo TC2068

*(English below)*

## Para que serve

No navegador, um ENTER num `.TAP` corre o plugin TAP do Bob Fossil (`/BIN/BPLUGINS/TAP`): abre o ficheiro como
cassete e faz o auto-load do esxDOS. Nos modos TC2048 e Spectrum isto funciona tal como vem.

No modo **TC2068** não funciona: o auto-load do esxDOS reinicia com a ROM do 48K, e o 2068 tem outra ROM e outra
maneira de carregar. Por isso, no TC2068, o navegador procura primeiro `/BIN/PLUG2068/TAP` e usa esse.

## O que é o PLUG2068/TAP

É o plugin TAP do Bob Fossil com uma alteração pequena:

- em 8071h, os 3 bytes `XOR A / RST 8 / DB 90h` (o auto-load do esxDOS) passam a `JP 8B31h`;
- no fim do ficheiro (8B31h) junta-se o `stub68` (272 bytes, código nosso, `stub68.asm`).

O `stub68` vê em que máquina está (CHANS = 6840h no TC2068):

- **Spectrum / TC2048**: faz o auto-load do esxDOS, como o original;
- **TC2068**: o NMI guardou a RAM (4000h–FFFFh) nas páginas 5–10 do DivMMC e repõe-na à saída do navegador.
  O stub escreve `LOAD ""` na linha de edição dessa cópia e deixa um ENTER pendente (LASTK = 13, FLAGS bit 5).
  O plugin devolve 20h: o navegador sai e o BASIC do 2068 carrega o TAP. Se a linha de edição não estiver vazia,
  só abre o TAP e diz para escrever `LOAD ""`.

## Porque não está o ficheiro pronto aqui

O plugin TAP é do Bob Fossil (www.thefossilrecord.co.uk). Não temos licença para distribuir uma versão alterada,
por isso este repositório guarda só o que é nosso — a alteração e o `stub68` — e cada um faz o seu
`PLUG2068/TAP` a partir do plugin que tirou do Bob Fossil.

## Como se faz

O `ferramentas/faz_cartao.sh` já o faz. À mão, com o cartão montado:

```
python3 fontes/plug2068/faz_plug2068.py CARTAO/BIN/BPLUGINS/TAP CARTAO/BIN/PLUG2068/TAP
```

O script só aceita a versão do plugin que conhecemos (2865 bytes, `AF CF 90` em 8071h, md5
`bd2512de16de45ec485edd6b47cd39dd`). Se o Bob Fossil mudar o plugin, recusa em vez de fazer um ficheiro estragado.

Para refazer o `stub68.bin`: `sjasmplus --raw=stub68.bin stub68.asm`.

---

# PLUG2068 — loading TAP files in TC2068 mode

## What it is for

In the browser, ENTER on a `.TAP` runs Bob Fossil's TAP plugin (`/BIN/BPLUGINS/TAP`): it opens the file as a tape
and does the esxDOS auto-load. In TC2048 and Spectrum modes this works as it comes.

In **TC2068** mode it does not: the esxDOS auto-load restarts with the 48K ROM, and the 2068 has another ROM and
another way of loading. So, in TC2068 mode, the browser first looks for `/BIN/PLUG2068/TAP` and uses that one.

## What PLUG2068/TAP is

Bob Fossil's TAP plugin with a small change:

- at 8071h, the 3 bytes `XOR A / RST 8 / DB 90h` (the esxDOS auto-load) become `JP 8B31h`;
- at the end of the file (8B31h) the `stub68` is appended (272 bytes, our own code, `stub68.asm`).

The `stub68` checks the machine (CHANS = 6840h on the TC2068):

- **Spectrum / TC2048**: does the esxDOS auto-load, like the original;
- **TC2068**: the NMI saved RAM (4000h–FFFFh) in DivMMC pages 5–10 and restores it when the browser exits. The stub
  writes `LOAD ""` in the edit line of that copy and leaves a pending ENTER (LASTK = 13, FLAGS bit 5). The plugin
  returns 20h: the browser exits and the 2068 BASIC loads the TAP. If the edit line is not empty, it only opens the
  TAP and says to type `LOAD ""`.

## Why the ready-made file is not here

The TAP plugin is Bob Fossil's (www.thefossilrecord.co.uk). We have no licence to distribute a modified version, so
this repository only keeps what is ours — the change and the `stub68` — and everyone makes their own
`PLUG2068/TAP` from the plugin they got from Bob Fossil.

## How to make it

`ferramentas/faz_cartao.sh` already does it. By hand, with the card mounted:

```
python3 fontes/plug2068/faz_plug2068.py CARD/BIN/BPLUGINS/TAP CARD/BIN/PLUG2068/TAP
```

The script only accepts the plugin version we know (2865 bytes, `AF CF 90` at 8071h, md5
`bd2512de16de45ec485edd6b47cd39dd`). If Bob Fossil changes the plugin, it refuses instead of making a broken file.

To rebuild `stub68.bin`: `sjasmplus --raw=stub68.bin stub68.asm`.
