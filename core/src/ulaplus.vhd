-- ulaplus.vhd: portas do ULAplus (o mesmo modulo no Timex e no Pentagon).
--   Segue o ula_radas.v do core Spectrum do ZX-UNO (associacao ZXUNO, GPL):
--   BF3B (escrita/leitura): registo de seleccao, 7 bits. Bit 6 = 0: entrada 0-63 da
--     paleta (bits 5-0); bit 6 = 1: registo do modo.
--   FF3B (escrita): dados -> paleta (GGGRRRBB) ou modo (bit 0 = ULAplus ligado).
--   FF3B (leitura): a entrada seleccionada da paleta (so' com o bit 6 a 0).
--   A paleta fica numa RAM de 2 portos (64 x 8): este lado escreve e le' para o CPU,
--   o video le' pelo outro porto.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ulaplus is
  port (
    clk     : in  std_logic;                       -- relogio do core
    reset_n : in  std_logic;
    a       : in  std_logic_vector(15 downto 0);
    d       : in  std_logic_vector(7 downto 0);
    iorq_n, rd_n, wr_n, m1_n : in std_logic;
    e_porta : out std_logic;                       -- leitura de BF3B / FF3B
    q_porta : out std_logic_vector(7 downto 0);
    -- paleta (porto A da RAM de 2 portos)
    pal_a   : out std_logic_vector(5 downto 0);
    pal_we  : out std_logic;
    pal_d   : out std_logic_vector(7 downto 0);
    pal_q   : in  std_logic_vector(7 downto 0);
    ligado  : out std_logic                        -- modo ULAplus
  );
end entity;

architecture rtl of ulaplus is
  signal sel : std_logic_vector(6 downto 0) := (others => '0');
  signal modo : std_logic := '0';
  signal e_sel, e_dat, io_wr, io_rd : std_logic;
begin
  e_sel <= '1' when a = x"BF3B" else '0';
  e_dat <= '1' when a = x"FF3B" else '0';
  io_wr <= '1' when iorq_n = '0' and wr_n = '0' and m1_n = '1' else '0';
  io_rd <= '1' when iorq_n = '0' and rd_n = '0' and m1_n = '1' else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        sel <= (others => '0'); modo <= '0';
      elsif io_wr = '1' then
        if e_sel = '1' then sel <= d(6 downto 0); end if;
        if e_dat = '1' and sel(6) = '1' then modo <= d(0); end if;
      end if;
    end if;
  end process;

  pal_a  <= sel(5 downto 0);
  pal_d  <= d;
  pal_we <= io_wr and e_dat and not sel(6);

  e_porta <= io_rd and (e_sel or (e_dat and not sel(6)));
  q_porta <= '0' & sel when e_sel = '1' else pal_q;
  ligado  <= modo;
end architecture;
