-- tmds_enc.vhd: codificador TMDS 8b/10b (DVI 1.0), com equilibrio DC.
-- Fase 1 do Timmy HDMI (Tang Nano 20K).
-- (esp58, 2026-10-26) em 2 andares: 1.o o XOR/XNOR (qm) e a contagem de uns, 2.o a disparidade e a saida.
--   Antes era tudo num ciclo de 13,5 ns e faltavam 0,9 ns (a 85 graus): de vez em quando um simbolo mau e a
--   TV perdia o sinal. O simbolo sai um ciclo mais tarde (o hdmi_tx atrasa os outros o mesmo).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tmds_enc is
  port (
    clk  : in  std_logic;
    de   : in  std_logic;                      -- 1 = pixel activo
    d    : in  std_logic_vector(7 downto 0);   -- cor
    c    : in  std_logic_vector(1 downto 0);   -- controlo (so no canal 0: VSYNC & HSYNC)
    q    : out std_logic_vector(9 downto 0)    -- q(0) sai primeiro
  );
end entity;

architecture rtl of tmds_enc is
  signal disp : signed(4 downto 0) := (others => '0');   -- disparidade acumulada
  -- 1.o andar
  signal qm_r : std_logic_vector(8 downto 0) := (others => '0');
  signal n1q_r : integer range 0 to 8 := 0;
  signal de_r : std_logic := '0';
  signal c_r : std_logic_vector(1 downto 0) := "00";
begin
  -- 1.o passo: minimizar transicoes
  process(clk)
    variable n1d, n1q : integer range 0 to 8;
    variable qm : std_logic_vector(8 downto 0);
  begin
    if rising_edge(clk) then
      n1d := 0;
      for i in 0 to 7 loop
        if d(i) = '1' then n1d := n1d + 1; end if;
      end loop;
      qm(0) := d(0);
      if n1d > 4 or (n1d = 4 and d(0) = '0') then
        for i in 1 to 7 loop qm(i) := qm(i-1) xnor d(i); end loop;
        qm(8) := '0';
      else
        for i in 1 to 7 loop qm(i) := qm(i-1) xor d(i); end loop;
        qm(8) := '1';
      end if;
      n1q := 0;
      for i in 0 to 7 loop
        if qm(i) = '1' then n1q := n1q + 1; end if;
      end loop;
      qm_r <= qm; n1q_r <= n1q; de_r <= de; c_r <= c;
    end if;
  end process;

  -- 2.o passo: equilibrio DC
  process(clk)
    variable dif : integer range -8 to 8;
  begin
    if rising_edge(clk) then
      dif := n1q_r - (8 - n1q_r);
      if de_r = '0' then
        disp <= (others => '0');
        case c_r is
          when "00"   => q <= "1101010100";
          when "01"   => q <= "0010101011";
          when "10"   => q <= "0101010100";
          when others => q <= "1010101011";
        end case;
      else
        if disp = 0 or n1q_r = 4 then
          q(9) <= not qm_r(8);
          q(8) <= qm_r(8);
          if qm_r(8) = '1' then
            q(7 downto 0) <= qm_r(7 downto 0);
            disp <= disp + to_signed(dif, 5);
          else
            q(7 downto 0) <= not qm_r(7 downto 0);
            disp <= disp - to_signed(dif, 5);
          end if;
        elsif (disp > 0 and n1q_r > 4) or (disp < 0 and n1q_r < 4) then
          q(9) <= '1';
          q(8) <= qm_r(8);
          q(7 downto 0) <= not qm_r(7 downto 0);
          if qm_r(8) = '1' then
            disp <= disp - to_signed(dif, 5) + 2;
          else
            disp <= disp - to_signed(dif, 5);
          end if;
        else
          q(9) <= '0';
          q(8) <= qm_r(8);
          q(7 downto 0) <= qm_r(7 downto 0);
          if qm_r(8) = '1' then
            disp <= disp + to_signed(dif, 5);
          else
            disp <= disp + to_signed(dif, 5) - 2;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
