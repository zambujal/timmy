-- som.vhd: do som da maquina (AY + beeper, valor sem sinal) a amostras de 48 kHz.
--   1. Media de 1024 dos 1125 ciclos de 54 MHz de cada amostra (54 MHz / 48 kHz):
--      tira o aliasing das ondas quadradas do AY sem abafar o som.
--   2. Corta-continua (passa-alto de ~7 Hz): o sinal fica centrado no zero.
--   3. Nivel: o AY (0..510) fica em +-8k; o maximo absoluto (1023) em +-16k.
--   Cada amostra nova muda o "tog"; o HDMI (outro relogio) apanha-a por ai'.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity som is
  port (
    clk    : in  std_logic;                       -- 54 MHz
    in_l, in_r : in std_logic_vector(13 downto 0); -- 0..16383 (AY + beeper + GS)
    out_l, out_r : out std_logic_vector(15 downto 0);  -- PCM com sinal
    tog    : out std_logic
  );
end entity;

architecture rtl of som is
  signal cnt : integer range 0 to 1124 := 0;
  signal acc_l, acc_r : unsigned(24 downto 0) := (others => '0');   -- ate' 16383 x 1125
  signal dc_l, dc_r : signed(25 downto 0) := (others => '0');        -- continua, com 10 bits de fraccao
  signal t : std_logic := '0';
  signal ol, orr : std_logic_vector(15 downto 0) := (others => '0');
begin
  process(clk)
    variable xl, xr : signed(15 downto 0);
    variable yl, yr : signed(15 downto 0);
  begin
    if rising_edge(clk) then
      if cnt = 1124 then
        cnt <= 0;
        -- media dos primeiros 1024 ciclos (soma / 1024: sem multiplicador; o DSP no
        -- caminho open source estragava o som)
        acc_l <= (others => '0'); acc_r <= (others => '0');
        xl := signed("0" & std_logic_vector(acc_l(23 downto 10)) & "0");   -- x 2: 0..32766
        xr := signed("0" & std_logic_vector(acc_r(23 downto 10)) & "0");
        -- corta-continua: dc += (x - dc) / 1024
        dc_l <= dc_l + resize(xl, 26) - shift_right(dc_l, 10);
        dc_r <= dc_r + resize(xr, 26) - shift_right(dc_r, 10);
        yl := xl - resize(shift_right(dc_l, 10), 16);
        yr := xr - resize(shift_right(dc_r, 10), 16);
        ol  <= std_logic_vector(yl);                         -- centrado: +-16k para o AY no maximo
        orr <= std_logic_vector(yr);
        t <= not t;
      else
        cnt <= cnt + 1;
        if cnt < 1024 then
          acc_l <= acc_l + unsigned(in_l);
          acc_r <= acc_r + unsigned(in_r);
        end if;
      end if;
    end if;
  end process;
  out_l <= ol; out_r <= orr; tog <= t;
end architecture;
