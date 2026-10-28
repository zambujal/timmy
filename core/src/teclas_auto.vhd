-- teclas_auto.vhd: teclado fantasma para testar sem teclado.
--   Sequencias em teclas_seq.vhd (gera_teclas.py). Timex: modo K. 128K/Pentagon: escolhe
--   "128 BASIC" no menu e escreve o mesmo programa letra a letra.
--   Botao A (impulso em "inicio"): escreve, tecla a tecla,
--       10 PRINT x: LET x=x+1: GO TO 10   ENTER   LET x=0   ENTER   GO TO 10   ENTER
--     (modo K: P = PRINT, L = LET, G = GO TO; ':' '=' '+' com SYMBOL SHIFT)
--   Botao B (nivel em "brk"): BREAK (CAPS SHIFT + SPACE) enquanto estiver carregado.
-- Saida: matriz 8 x 5, bit (fila*5 + coluna) a 1 = carregada.
--   fila 0 (A8):  CS Z X C V      fila 4 (A12): 0 9 8 7 6
--   fila 1 (A9):  A S D F G       fila 5 (A13): P O I U Y
--   fila 2 (A10): Q W E R T       fila 6 (A14): ENTER L K J H
--   fila 3 (A11): 1 2 3 4 5       fila 7 (A15): SPACE SS M N B
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.teclas_seq.all;

entity teclas_auto is
  generic (M128 : boolean := false;               -- true: 128K/Pentagon (escreve letra a letra)
           LS   : boolean := false;               -- true: escreve .ls ENTER (DivMMC); o B nao faz BREAK
           BR   : boolean := false;               -- true (com LS): escreve .browser ENTER em vez do .ls
           PK   : boolean := false;               -- true: escreve PRINT PEEK 23733 (teste da SDRAM)
           TR   : boolean := false);              -- true: Pentagon + DivMMC: 48 BASIC, .vdisk 0 teste.trd, TR-DOS, RUN
  port (
    clk    : in  std_logic;                       -- 54 MHz
    inicio : in  std_logic;                       -- botao A (ja' sem ressaltos)
    brk    : in  std_logic;                       -- botao B
    mat    : out std_logic_vector(39 downto 0)
  );
end entity;

architecture rtl of teclas_auto is
  constant K_CS : integer := 0*5+0; constant K_SP : integer := 7*5+0;
  constant K_SS : integer := 7*5+1;
  function escolhe return seq_t is
  begin
    if TR then return SEQ_TRD; elsif PK then return SEQ_PK; elsif LS and BR then return SEQ_BR; elsif LS then return SEQ_LS; elsif M128 then return SEQ_128; else return SEQ_TIMEX; end if;
  end function;
  constant SEQ : seq_t := escolhe;

  signal ativo : std_logic := '0';
  signal idx : integer range 0 to SEQ'length := 0;
  -- tempo de cada tecla: Timex 2^23 ciclos (78 ms carregada + 78 solta); 128K o dobro
  --   (o editor do 128K e' mais lento a aceitar teclas)
  function bits return integer is begin if M128 then return 24; else return 23; end if; end function;
  constant NB : integer := bits;
  signal t : unsigned(NB-1 downto 0) := (others => '0');
  signal ini_d : std_logic := '0';
  signal m : std_logic_vector(39 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      ini_d <= inicio;
      if ativo = '0' then
        if inicio = '1' and ini_d = '0' then ativo <= '1'; idx <= 0; t <= (others => '0'); end if;
      else
        t <= t + 1;
        if t = 2**NB - 1 then                       -- 78 ms carregada + 78 ms solta
          if idx = SEQ'length - 1 then ativo <= '0'; else idx <= idx + 1; end if;
        end if;
      end if;
    end if;
  end process;

  process(ativo, idx, t, brk)
    variable v : std_logic_vector(39 downto 0);
  begin
    v := (others => '0');
    if ativo = '1' and t(NB-1) = '0' and idx < SEQ'length and SEQ(idx).np = '0' then
      v(SEQ(idx).k) := '1';
      if SEQ(idx).ss = '1' then v(K_SS) := '1'; end if;
      if SEQ(idx).cs = '1' then v(K_CS) := '1'; end if;
    end if;
    if brk = '1' and not LS and not TR then v(K_CS) := '1'; v(K_SP) := '1'; end if;
    m <= v;
  end process;
  mat <= m;
end architecture;
