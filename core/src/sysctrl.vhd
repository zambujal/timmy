-- sysctrl.vhd: alvo SYS do FPGA-Companion (so' o que o Timextenso precisa).
--   A partir do sysctrl.v do MiSTeryNano (MiSTle-Dev, GPL). Comandos:
--     0 estado: devolve 5C 42 00 (core generico)    5 IRQ: confirma / pendentes
--     3 botoes da Tang                              6 origem do IRQ (arranque a frio)
--     8 le a configuracao XML (menu do OSD)         outros: ignorados
--   int_n fica a 0 depois de ligar, ate' o BL616 confirmar o arranque (bit 0).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sysctrl is
  port (
    clk     : in  std_logic;
    reset   : in  std_logic;
    stb     : in  std_logic;
    inicio  : in  std_logic;
    d       : in  std_logic_vector(7 downto 0);
    q       : out std_logic_vector(7 downto 0);
    botoes  : in  std_logic_vector(1 downto 0);
    int_n   : out std_logic
  );
end entity;

architecture rtl of sysctrl is
  type rom_t is array(0 to 511) of std_logic_vector(7 downto 0);
  constant XML : rom_t := (
    x"3C", x"3F", x"78", x"6D", x"6C", x"20", x"76", x"65", x"72", x"73", x"69", x"6F", x"6E", x"3D", x"22", x"31",
    x"2E", x"30", x"22", x"20", x"65", x"6E", x"63", x"6F", x"64", x"69", x"6E", x"67", x"3D", x"22", x"75", x"74",
    x"66", x"2D", x"38", x"22", x"3F", x"3E", x"0A", x"3C", x"21", x"2D", x"2D", x"20", x"54", x"69", x"6D", x"6D",
    x"79", x"20", x"28", x"54", x"69", x"6D", x"65", x"78", x"2F", x"53", x"70", x"65", x"63", x"74", x"72", x"75",
    x"6D", x"20", x"6E", x"61", x"20", x"54", x"61", x"6E", x"67", x"20", x"4E", x"61", x"6E", x"6F", x"20", x"32",
    x"30", x"4B", x"29", x"20", x"2D", x"2D", x"3E", x"0A", x"3C", x"63", x"6F", x"6E", x"66", x"69", x"67", x"20",
    x"6E", x"61", x"6D", x"65", x"3D", x"22", x"54", x"69", x"6D", x"6D", x"79", x"22", x"20", x"76", x"65", x"72",
    x"73", x"69", x"6F", x"6E", x"3D", x"22", x"30", x"22", x"3E", x"0A", x"20", x"20", x"3C", x"61", x"63", x"74",
    x"69", x"6F", x"6E", x"73", x"3E", x"0A", x"20", x"20", x"20", x"20", x"3C", x"61", x"63", x"74", x"69", x"6F",
    x"6E", x"20", x"6E", x"61", x"6D", x"65", x"3D", x"22", x"69", x"6E", x"69", x"74", x"22", x"3E", x"0A", x"20",
    x"20", x"20", x"20", x"20", x"20", x"3C", x"73", x"65", x"74", x"20", x"69", x"64", x"3D", x"22", x"52", x"22",
    x"20", x"76", x"61", x"6C", x"75", x"65", x"3D", x"22", x"30", x"22", x"2F", x"3E", x"0A", x"20", x"20", x"20",
    x"20", x"3C", x"2F", x"61", x"63", x"74", x"69", x"6F", x"6E", x"3E", x"0A", x"20", x"20", x"20", x"20", x"3C",
    x"61", x"63", x"74", x"69", x"6F", x"6E", x"20", x"6E", x"61", x"6D", x"65", x"3D", x"22", x"72", x"65", x"61",
    x"64", x"79", x"22", x"3E", x"0A", x"20", x"20", x"20", x"20", x"20", x"20", x"3C", x"73", x"65", x"74", x"20",
    x"69", x"64", x"3D", x"22", x"52", x"22", x"20", x"76", x"61", x"6C", x"75", x"65", x"3D", x"22", x"30", x"22",
    x"2F", x"3E", x"0A", x"20", x"20", x"20", x"20", x"3C", x"2F", x"61", x"63", x"74", x"69", x"6F", x"6E", x"3E",
    x"0A", x"20", x"20", x"3C", x"2F", x"61", x"63", x"74", x"69", x"6F", x"6E", x"73", x"3E", x"0A", x"20", x"20",
    x"3C", x"6D", x"65", x"6E", x"75", x"20", x"6C", x"61", x"62", x"65", x"6C", x"3D", x"22", x"54", x"69", x"6D",
    x"6D", x"79", x"22", x"3E", x"0A", x"20", x"20", x"20", x"20", x"3C", x"6C", x"69", x"73", x"74", x"20", x"6C",
    x"61", x"62", x"65", x"6C", x"3D", x"22", x"54", x"65", x"63", x"6C", x"61", x"64", x"6F", x"3A", x"22", x"20",
    x"69", x"64", x"3D", x"22", x"4B", x"22", x"20", x"64", x"65", x"66", x"61", x"75", x"6C", x"74", x"3D", x"22",
    x"30", x"22", x"3E", x"0A", x"20", x"20", x"20", x"20", x"20", x"20", x"3C", x"6C", x"69", x"73", x"74", x"65",
    x"6E", x"74", x"72", x"79", x"20", x"6C", x"61", x"62", x"65", x"6C", x"3D", x"22", x"53", x"70", x"65", x"63",
    x"74", x"72", x"75", x"6D", x"22", x"20", x"76", x"61", x"6C", x"75", x"65", x"3D", x"22", x"30", x"22", x"2F",
    x"3E", x"0A", x"20", x"20", x"20", x"20", x"3C", x"2F", x"6C", x"69", x"73", x"74", x"3E", x"0A", x"20", x"20",
    x"3C", x"2F", x"6D", x"65", x"6E", x"75", x"3E", x"0A", x"3C", x"2F", x"63", x"6F", x"6E", x"66", x"69", x"67",
    x"3E", x"0A", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
    x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
    x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
    x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
    x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00"
  );
  signal cmd     : std_logic_vector(7 downto 0) := (others => '0');
  signal st      : unsigned(3 downto 0) := (others => '0');
  signal q_r     : std_logic_vector(7 downto 0) := (others => '0');
  signal frio    : std_logic := '1';   -- arranque a frio por anunciar
  signal sys_int : std_logic := '1';
  signal ra      : unsigned(8 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        frio <= '1'; sys_int <= '1'; st <= (others => '0');
      elsif stb = '1' then
        if inicio = '1' then
          st <= (others => '0'); cmd <= d; ra <= (others => '0'); q_r <= x"00";
        else
          if st /= 15 then st <= st + 1; end if;
          case cmd is
            when x"00" =>
              -- como o NextNano (que funciona com este Companion): 7C 42 0A e sem XML
              if st = 0 then q_r <= x"7C"; elsif st = 1 then q_r <= x"42"; elsif st = 2 then q_r <= x"0A"; else q_r <= x"00"; end if;
            when x"03" =>
              q_r <= "000000" & botoes;
            when x"05" =>
              if st = 0 and d(0) = '1' then sys_int <= '0'; end if;
              q_r <= "0000000" & sys_int;
            when x"06" =>
              q_r <= "0000000" & frio;
              if st = 0 then frio <= '0'; end if;
            when x"08" =>
              q_r <= x"00";                     -- sem configuracao (XML desligado)
              -- q_r <= XML(to_integer(ra));
              if ra /= 511 then ra <= ra + 1; end if;
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;
  q     <= q_r;
  int_n <= not sys_int;
end architecture;
