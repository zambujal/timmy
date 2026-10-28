-- mcu_spi.vhd: SPI com o FPGA-Companion (BL616 da Tang). Traducao para VHDL do
--   mcu_spi.v do MiSTeryNano (MiSTle-Dev, GPL).
--   O BL616 e' o mestre. SPI modo 1: relogio parado a 0, dados mudam na subida e
--   leem-se na descida. CSN a 0 abre a mensagem.
--   1.o byte da mensagem = alvo: 0 SYS, 1 HID (2 OSD e 3 SDC nao existem aqui).
--   Os bytes seguintes vao para o alvo, com "inicio" no primeiro (o comando).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mcu_spi is
  port (
    clk      : in  std_logic;                      -- relogio do core
    ss       : in  std_logic;                      -- CSN (1 = livre)
    sclk     : in  std_logic;
    mosi     : in  std_logic;
    miso     : out std_logic;
    sys_stb  : out std_logic;                      -- byte para o alvo SYS
    hid_stb  : out std_logic;                      -- byte para o alvo HID
    inicio   : out std_logic;                      -- e' o 1.o byte depois do alvo
    dado     : out std_logic_vector(7 downto 0);   -- byte vindo do BL616
    sys_q    : in  std_logic_vector(7 downto 0);   -- byte a devolver (SYS)
    hid_q    : in  std_logic_vector(7 downto 0)    -- byte a devolver (HID)
  );
end entity;

architecture rtl of mcu_spi is
  -- lado do relogio SPI
  signal cnt   : unsigned(3 downto 0) := (others => '0');
  signal sr    : std_logic_vector(6 downto 0) := (others => '0');
  signal byte  : std_logic_vector(7 downto 0) := (others => '0');
  signal tog   : std_logic := '0';
  -- lado do core
  signal tg    : std_logic_vector(2 downto 0) := (others => '0');
  signal ss_s  : std_logic_vector(1 downto 0) := (others => '1');
  signal n_in  : unsigned(3 downto 0) := (others => '0');
  signal alvo  : std_logic_vector(7 downto 0) := (others => '0');
  signal d_r   : std_logic_vector(7 downto 0) := (others => '0');
  signal q     : std_logic_vector(7 downto 0);
begin
  -- leitura na descida do SCLK
  process(sclk, ss)
  begin
    if ss = '1' then
      cnt <= (others => '0');
    elsif falling_edge(sclk) then
      cnt <= cnt + 1;
      sr  <= sr(5 downto 0) & mosi;
      if cnt(2 downto 0) = "111" then
        byte <= sr & mosi;
        tog  <= not tog;
      end if;
    end if;
  end process;

  -- passa cada byte para o relogio do core (o byte fica parado 8 bits: tempo de sobra)
  process(clk)
  begin
    if rising_edge(clk) then
      tg   <= tg(1 downto 0) & tog;
      ss_s <= ss_s(0) & ss;
      sys_stb <= '0'; hid_stb <= '0';
      if ss_s(1) = '1' then
        n_in <= (others => '0');
      elsif tg(2) /= tg(1) then
        if n_in = 0 then
          alvo <= byte;
        else
          if alvo = x"00" then sys_stb <= '1'; end if;
          if alvo = x"01" then hid_stb <= '1'; end if;
          d_r <= byte;
        end if;
        if n_in /= 15 then n_in <= n_in + 1; end if;
      end if;
    end if;
  end process;
  inicio <= '1' when n_in = 2 else '0';
  dado   <= d_r;

  q <= sys_q when alvo = x"00" else hid_q when alvo = x"01" else x"00";

  -- escrita na subida do SCLK (bit 7 primeiro)
  process(sclk, ss)
  begin
    if ss = '1' then
      miso <= '0';
    elsif rising_edge(sclk) then
      miso <= q(7 - to_integer(cnt(2 downto 0)));
    end if;
  end process;
end architecture;
