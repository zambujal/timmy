# Teclas e botões

## Teclado USB (no core)

O teclado de PC é visto pelo core como o teclado do Spectrum:

| PC | Spectrum |
|---|---|
| Shift | CAPS SHIFT |
| Ctrl, Alt | SYMBOL SHIFT |
| Backspace | CS+0 (apagar) |
| Esc | CS+ESPAÇO (BREAK) |
| Setas | CS+5 / 6 / 7 / 8 |
| Tab | CS+SS (modo estendido) |
| Caps Lock | CS+2 |
| , . / ; ' - = | SS + N M V O 7 J L |
| Ctrl+Alt+Del | RESET da máquina |
| Ctrl+Alt+F11 | troca de core (multiboot, se houver outro core na flash em 0x100000) |

O rato USB é o rato Kempston; um comando USB (ou comando Xbox) é o joystick Kempston.
As combinações com a tecla Windows (Win+J, Win+S, Win+C, Win+R, Win+'+', Win+'-') são só para a placa
ESP32 e não fazem nada sem ela.

## Botões do Tang Nano 20K

- **Botão do pino 87:** NMI — abre o navegador (e, dentro dele, BREAK sai).
- **Botão do pino 88:** cada toque passa a uma escolha (os LEDs mostram o número em binário); carregar
  no outro botão faz a escolha: 0 NMI, 1 `.ls`, 2 `.go128`, 3 `.go128 -penta`, 4 `.go1024`, 5 `.go2068`,
  6 RESET+NMI (volta ao TC2048), 8 RESET, 10 `.gs`, 15 turbo (3,5 → 7 → 14 → 3,5 MHz). Carregado 3 s:
  troca de core (multiboot).

## O navegador (NMI)

| Tecla | Função |
|---|---|
| 7 / 6 (setas cima/baixo) | anda na lista; SYM+7 / SYM+6 página |
| 5 / 8 (setas esq./dir.) | coluna das letras / coluna dos ficheiros |
| ENTER | corre o ficheiro ou entra na pasta |
| ESPAÇO | pasta de cima |
| A–Z | salta para a letra |
| 0 | todas as máquinas; 1 48K; 2 48K+AY; 3 128K; 4 Timex; 9 outras (filtro, só com índices) |
| EDIT (CS+1) | o NMI original do esxDOS |
| BREAK (CS+ESPAÇO, Esc) | sai |

Dentro do navegador o menu das máquinas muda para 48K / 128K / Timex 128 / TC2068 / Pentagon e liga o
General Sound e os 3 AY. Um .MOD precisa do General Sound ligado.
