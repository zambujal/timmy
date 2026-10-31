-- cassete.vhd - leitor de cassete do Timextenso (2026-10-24)
-- O ESP manda impulsos (palavras de 16 bits) para uma fila de 256; aqui o EAR muda no tempo certo,
-- contado em T-states do Z80 (t_ce = um T do Z80 sem espera): em turbo a cassete anda com o Z80.
--   bit 15 = 0         : espera bits 14-0 T e depois vira o EAR (impulso)
--   bit 15-14 = 10     : espera bits 13-0 x 64 T sem virar (pausas)
--   bit 15-14 = 11     : poe o EAR = bit 13, logo
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cassete is
  port (
    clk    : in  std_logic;
    t_ce   : in  std_logic;
    limpa  : in  std_logic;                       -- 1 = pára e esvazia a fila (EAR a 0)
    wr     : in  std_logic;                       -- 1 ciclo: mete d na fila
    d      : in  std_logic_vector(15 downto 0);
    livres : out std_logic_vector(7 downto 0);    -- lugares livres na fila (0-255)
    ativa  : out std_logic;                       -- 1 = ha' impulsos por tocar
    ear    : out std_logic
  );
end entity;

architecture rtl of cassete is
  type fila_t is array (0 to 255) of std_logic_vector(15 downto 0);
  signal fila : fila_t;
  signal wp, rp : unsigned(7 downto 0) := (others => '0');
  signal n : unsigned(8 downto 0) := (others => '0');
  signal q : std_logic_vector(15 downto 0) := (others => '0');
  signal q_ok, ocupado, vira, ear_r : std_logic := '0';
  signal cnt : unsigned(19 downto 0) := (others => '0');
begin
  n <= ('0' & wp) - ('0' & rp) when wp >= rp else ('1' & wp) - ('0' & rp);
  livres <= std_logic_vector(to_unsigned(255, 8) - n(7 downto 0));
  ativa <= '1' when n /= 0 or ocupado = '1' else '0';
  ear <= ear_r;

  process(clk)
  begin
    if rising_edge(clk) then
      if wr = '1' and n(7 downto 0) /= 255 then
        fila(to_integer(wp)) <= d; wp <= wp + 1;
      end if;
      q <= fila(to_integer(rp));
      q_ok <= '0';
      if limpa = '1' then
        rp <= wp; ocupado <= '0'; ear_r <= '0'; cnt <= (others => '0');
      elsif ocupado = '0' then
        if n /= 0 and q_ok = '0' then
          q_ok <= '1';                              -- o q do rp actual chega no ciclo seguinte
        elsif q_ok = '1' then
          rp <= rp + 1;
          if q(15) = '0' then
            cnt <= "00000" & unsigned(q(14 downto 0)); vira <= '1'; ocupado <= '1';
          elsif q(14) = '0' then
            cnt <= unsigned(q(13 downto 0)) & "000000"; vira <= '0'; ocupado <= '1';
          else
            ear_r <= q(13);
          end if;
        end if;
      elsif t_ce = '1' then
        if cnt <= 1 then
          ocupado <= '0';
          if vira = '1' then ear_r <= not ear_r; end if;
        else
          cnt <= cnt - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
