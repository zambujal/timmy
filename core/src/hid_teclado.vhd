-- hid_teclado.vhd: alvo HID do FPGA-Companion -> matriz do teclado do Spectrum.
--   Comando 1 (teclado): 1.o byte = codigo de uso USB HID (bits 6-0) e bit 7 = tecla
--   largada. Os modificadores chegam como 68h + bit (68 Ctrl esq, 69 Shift esq, 6A Alt esq,
--   6B GUI esq, 6C Ctrl dir, 6D Shift dir, 6E Alt dir, 6F GUI dir). Os bytes seguintes
--   (codigos PS/2) nao interessam.
--   Comando 0 (estado): devolve 01 00.
--   Saida: matriz 8 x 5, bit fila*5+coluna, 1 = carregada (como o teclas_auto).
--     fila 0 CS Z X C V   1 A S D F G   2 Q W E R T   3 1 2 3 4 5
--     fila 4 0 9 8 7 6    5 P O I U Y   6 ENT L K J H 7 SPC SS M N B
--   Shift = CAPS SHIFT; Ctrl e Alt = SYMBOL SHIFT.
--   Teclas de PC que valem duas do Spectrum: Backspace = CS+0, Esc = CS+SPACE (BREAK),
--   setas = CS+5/6/7/8, Tab = CS+SS (modo estendido), Caps Lock = CS+2,
--   , . / ; ' - = = SS + N M V O 7 J L.
--   Ctrl+Alt+F11 sai em "f11" (troca de core). Win+J, Win+S e Win+C sao para o ESP (menu, captura, ...).
--   Comando 2 (rato): botoes (bit 0 esquerdo, 1 direito, 2 meio), dx, dy (com sinal) [, roda].
--   Sai como o rato Kempston: X sobe para a direita, Y sobe para cima (contadores de 8 bits).
--   Comando 3 (joystick, tambem comandos Xbox/XInput): indice, estado (bit 0 dir, 1 esq, 2 baixo,
--   3 cima, 4-7 A B X Y), X, Y, extra. O joystick 0 sai como Kempston (1F): bits 0-3 e fogo = qualquer botao.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hid_teclado is
  port (
    clk    : in  std_logic;
    reset  : in  std_logic;
    stb    : in  std_logic;
    inicio : in  std_logic;
    d      : in  std_logic_vector(7 downto 0);
    q      : out std_logic_vector(7 downto 0);
    mat    : out std_logic_vector(39 downto 0);
    f11    : out std_logic;
    cad    : out std_logic;                          -- (esp44b) Ctrl+Alt+Del: reset do Spectrum
    rato_x, rato_y : out std_logic_vector(7 downto 0);
    rato_b : out std_logic_vector(2 downto 0);       -- 1 = carregado: 0 esquerdo, 1 direito, 2 meio
    joy    : out std_logic_vector(7 downto 0);       -- Kempston (1 = carregado)
    atalho : out std_logic_vector(20 downto 0);       -- (2026-10-22) com a tecla Windows: bit 0 Win+J (menu), bit 1
                                                     -- Win+S (captura), bit 2 Win+C, bit 3 Win+'+' (mais MHz), bit 4
                                                     -- Win+'-' (menos MHz), bit 5 Win+R (corre sem a maquina
                                                     -- guardada); o Spectrum nao os ve'
    alt    : out std_logic;                          -- uma tecla Windows carregada (diagnostico: LED 3)
    jcru   : out std_logic_vector(31 downto 0)       -- joystick 0 tal como vem: estado, X, Y, extra (para o ESP)
  );
end entity;

architecture rtl of hid_teclado is
  signal cmd : std_logic_vector(7 downto 0) := (others => '0');
  signal st  : unsigned(3 downto 0) := (others => '0');
  signal q_r : std_logic_vector(7 downto 0) := (others => '0');
  signal k   : std_logic_vector(127 downto 0) := (others => '0');   -- teclas carregadas
  signal rx, ry : unsigned(7 downto 0) := (others => '0');
  signal rb : std_logic_vector(2 downto 0) := (others => '0');
  signal j_idx : std_logic_vector(7 downto 0) := (others => '0');
  signal jy : std_logic_vector(7 downto 0) := (others => '0');
  signal jc : std_logic_vector(31 downto 0) := (others => '0');
  signal mais, menos : std_logic;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        k <= (others => '0'); st <= (others => '0');
      elsif stb = '1' then
        if inicio = '1' then
          st <= (others => '0'); cmd <= d;
        else
          if st /= 15 then st <= st + 1; end if;
          if cmd = x"00" then
            if st = 0 then q_r <= x"01"; else q_r <= x"00"; end if;
          end if;
          if cmd = x"01" and st = 0 then
            k(to_integer(unsigned(d(6 downto 0)))) <= not d(7);
          end if;
          if cmd = x"02" then
            if st = 0 then rb <= d(2 downto 0); end if;
            if st = 1 then rx <= rx + unsigned(d); end if;            -- dx com sinal: soma modulo 256
            if st = 2 then ry <= ry - unsigned(d); end if;            -- USB: dy > 0 para baixo; Kempston: Y sobe para cima
          end if;
          if cmd = x"03" then
            if st = 0 then j_idx <= d; end if;
            if st = 1 and j_idx = x"00" then
              jy <= "000" & (d(7) or d(6) or d(5) or d(4)) & d(3 downto 0);
            end if;
            if j_idx = x"00" then
              if st = 1 then jc(7 downto 0) <= d; end if;
              if st = 2 then jc(15 downto 8) <= d; end if;
              if st = 3 then jc(23 downto 16) <= d; end if;
              if st = 4 then jc(31 downto 24) <= d; end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
  q <= q_r;
  rato_x <= std_logic_vector(rx);
  rato_y <= std_logic_vector(ry);
  rato_b <= rb;
  joy <= jy;
  jcru <= jc;

  process(k, mais, menos)
    variable m : std_logic_vector(39 downto 0);
    procedure t(c : integer; b : integer) is
    begin
      if k(c) = '1' then m(b) := '1'; end if;
    end procedure;
    procedure t2(c : integer; b1, b2 : integer) is
    begin
      if k(c) = '1' then m(b1) := '1'; m(b2) := '1'; end if;
    end procedure;
    constant CS : integer := 0;  constant SS : integer := 36;
  begin
    m := (others => '0');
    -- letras (HID 04h = A ... 1Dh = Z)
    t(16#04#, 5);  t(16#05#, 39); t(16#06#, 3);  t(16#07#, 7);  t(16#08#, 12); -- A B C D E
    t(16#09#, 8);  t(16#0A#, 9);  t(16#0B#, 34); t(16#0C#, 27); t(16#0D#, 33); -- F G H I J
    t(16#0E#, 32); t(16#0F#, 31); t(16#10#, 37); t(16#11#, 38); t(16#12#, 26); -- K L M N O
    t(16#13#, 25); t(16#14#, 10); t(16#15#, 13); t(16#16#, 6);  t(16#17#, 14); -- P Q R S T
    t(16#18#, 28); t(16#19#, 4);  t(16#1A#, 11); t(16#1B#, 2);  t(16#1C#, 29); -- U V W X Y
    t(16#1D#, 1);                                                               -- Z
    -- algarismos (1Eh = 1 ... 26h = 9, 27h = 0)
    t(16#1E#, 15); t(16#1F#, 16); t(16#20#, 17); t(16#21#, 18); t(16#22#, 19);
    t(16#23#, 24); t(16#24#, 23); t(16#25#, 22); t(16#26#, 21); t(16#27#, 20);
    -- teclado numerico 1-9, 0 e Enter
    t(16#59#, 15); t(16#5A#, 16); t(16#5B#, 17); t(16#5C#, 18); t(16#5D#, 19);
    t(16#5E#, 24); t(16#5F#, 23); t(16#60#, 22); t(16#61#, 21); t(16#62#, 20);
    t(16#28#, 30); t(16#58#, 30);                     -- Enter
    t(16#2C#, 35);                                    -- Espaco
    -- modificadores
    t(16#69#, CS); t(16#6D#, CS);                     -- Shift
    t(16#68#, SS); t(16#6C#, SS); t(16#6A#, SS); t(16#6E#, SS);   -- Ctrl, Alt
    -- teclas compostas
    t2(16#2A#, CS, 20);                               -- Backspace = DELETE (CS+0)
    t2(16#29#, CS, 35);                               -- Esc = BREAK (CS+SPACE)
    t2(16#50#, CS, 19);                               -- seta esquerda (CS+5)
    t2(16#51#, CS, 24);                               -- seta baixo (CS+6)
    t2(16#52#, CS, 23);                               -- seta cima (CS+7)
    t2(16#4F#, CS, 22);                               -- seta direita (CS+8)
    t2(16#2B#, CS, SS);                               -- Tab = modo estendido
    t2(16#39#, CS, 16);                               -- Caps Lock (CS+2)
    t2(16#36#, SS, 38);                               -- ,  (SS+N)
    t2(16#37#, SS, 37);                               -- .  (SS+M)
    t2(16#38#, SS, 4);                                -- /  (SS+V)
    t2(16#33#, SS, 26);                               -- ;  (SS+O)
    t2(16#34#, SS, 23);                               -- '  (SS+7)
    t2(16#2D#, SS, 33);                               -- -  (SS+J)
    t2(16#2E#, SS, 31);                               -- =  (SS+L)
    -- atalhos do ESP com a tecla Windows (que o Spectrum nao usa): o Spectrum nao os ve'
    if (k(16#6B#) = '1' or k(16#6F#) = '1') and (k(16#0D#) = '1' or k(16#16#) = '1' or k(16#06#) = '1' or
        k(16#15#) = '1' or k(16#10#) = '1' or mais = '1' or menos = '1') then m := (others => '0'); end if;
    mat <= m;
  end process;
  alt <= k(16#6B#) or k(16#6F#);
  atalho(0) <= (k(16#6B#) or k(16#6F#)) and k(16#0D#);     -- Win+J
  atalho(1) <= (k(16#6B#) or k(16#6F#)) and k(16#16#);     -- Win+S
  atalho(2) <= (k(16#6B#) or k(16#6F#)) and k(16#06#);     -- Win+C
  -- '+' e '-': os do teclado numerico (iguais em todos os teclados) e as teclas onde estao no
  -- teclado americano (2Eh, 2Dh) e no portugues (2Fh, 38h)
  mais  <= k(16#57#) or k(16#2E#) or k(16#2F#);
  menos <= k(16#56#) or k(16#2D#) or k(16#38#);
  atalho(3) <= (k(16#6B#) or k(16#6F#)) and mais;          -- Win+'+'
  atalho(4) <= (k(16#6B#) or k(16#6F#)) and menos;         -- Win+'-'
  atalho(5) <= (k(16#6B#) or k(16#6F#)) and k(16#15#);     -- Win+R
  atalho(6) <= (k(16#6B#) or k(16#6F#)) and k(16#10#);     -- Win+M (2026-10-23: a maquina seguinte)
  atalho(7) <= k(16#3A#);                                  -- F1 (2026-10-23: maquinas e placas; o Spectrum nao a usa)
  atalho(8) <= k(16#3B#);                                  -- F2 (as placas)
  atalho(9)  <= k(16#4B#);                                 -- Page Up   (2026-10-23: o menu do ESP)
  atalho(10) <= k(16#4E#);                                 -- Page Down
  atalho(11) <= k(16#4A#);                                 -- Home
  atalho(12) <= k(16#4D#);                                 -- End
  atalho(13) <= k(16#3C#);                                 -- F3 (2026-10-24: cassete: tocar / pausa)
  atalho(14) <= k(16#3D#);                                 -- F4 (cassete: parar)
  atalho(15) <= k(16#3E#);                                 -- F5 (2026-10-24: musica seguinte)
  atalho(16) <= k(16#3F#);                                 -- F6 (musica anterior)
  atalho(17) <= k(16#40#);                                 -- F7 (esp44: musica seguinte)
  atalho(18) <= k(16#41#);                                 -- F8
  atalho(19) <= k(16#42#);                                 -- F9  (esp56: volume do som do ESP -)
  atalho(20) <= k(16#43#);                                 -- F10 (esp56: volume do som do ESP +)
  -- Ctrl + Alt + F11: troca de core
  f11 <= k(16#44#) and (k(16#68#) or k(16#6C#)) and (k(16#6A#) or k(16#6E#));
  -- reset do Spectrum, como no Amiga: Ctrl + Alt + AltGr (as duas Alt), ou Ctrl + as duas Windows (as "Amiga");
  -- e tambem Ctrl + Alt + Del (ou o Delete do teclado numerico)
  cad <= (k(16#68#) or k(16#6C#)) and ((k(16#6A#) and k(16#6E#)) or (k(16#6B#) and k(16#6F#)) or
                                       ((k(16#4C#) or k(16#63#)) and (k(16#6A#) or k(16#6E#))));
end architecture;
