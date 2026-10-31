-- gs.vhd: General Sound para o Timextenso da Tang (em todas as maquinas).
--   Traducao para VHDL do gs.v do core ZX Spectrum do MiSTer (Sorgelig, GPL), com a memoria
--   toda de fora (na SDRAM: ROM na pagina 0, RAM nas paginas 1-63, 32K cada).
--
--   Lado do Spectrum (com M1 = 1):
--     xxBB escrita: registo de comandos (flag de comando, bit 0, a 1)
--     xxBB leitura: estado (bit 7 flag de dados, bit 0 flag de comando, o resto a 1)
--     xxB3 escrita: dados para o GS (flag de dados a 1); leitura: dados do GS (flag de dados a 0)
--   Portas do GS (A3-A0):
--     0 escrita: pagina de 32K em 8000h-FFFFh (6 bits; 0 = ROM)
--     1 leitura: comando   2 leitura: dados (flag de dados a 0)   3 escrita: dados para o Spectrum (flag a 1)
--     4 leitura: estado    5: flag de comando a 0   6-9 escrita: volume dos canais 1-4 (6 bits)
--     A: flag de dados = nao (bit 0 da porta 0)   B: flag de comando = bit 5 da porta 9 (como o MiSTer)
--   Memoria: 0000-3FFF os primeiros 16K da ROM; 4000-7FFF os primeiros 16K da pagina 1;
--            8000-FFFF a pagina da porta 0. As leituras em 6000h-7FFFh vao tambem para os
--            canais (A9-A8 = canal).
--   INT a 37,5 kHz. Saida: canais 1+2 a' esquerda, 3+4 a' direita (com sinal, 15 bits).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gs is
  generic (CLK_HZ : integer := 54000000);
  port (
    clk     : in  std_logic;
    reset_n : in  std_logic;
    ce      : in  std_logic;                      -- relogio do Z80 do GS
    -- lado do Spectrum
    cs_rd   : in  std_logic;                      -- leitura de xxB3/xxBB (IORQ, M1 = 1)
    cs_wr   : in  std_logic;
    a3      : in  std_logic;                      -- 1 = BB, 0 = B3
    din     : in  std_logic_vector(7 downto 0);
    dout    : out std_logic_vector(7 downto 0);
    -- memoria (endereco de 21 bits: pagina(6) & A14 da pagina & A13-A0)
    m_a     : out std_logic_vector(20 downto 0);
    m_rd    : out std_logic;                      -- acesso em curso (nivel)
    m_wr    : out std_logic;
    m_d     : out std_logic_vector(7 downto 0);
    m_q     : in  std_logic_vector(7 downto 0);
    m_wait  : in  std_logic;                      -- 1 = o acesso ainda nao acabou
    out_l, out_r : out signed(14 downto 0)
  );
end entity;

architecture rtl of gs is
  signal a : std_logic_vector(15 downto 0);
  signal di, do_c : std_logic_vector(7 downto 0);
  signal m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n : std_logic;
  signal int_n : std_logic := '1';
  signal acc : integer range 0 to 2*CLK_HZ := 0;
  signal tick : std_logic := '0';
  signal bit7, bit0 : std_logic := '0';
  signal p_bb, p_b3, p_03 : std_logic_vector(7 downto 0) := (others => '0');
  signal p_00 : std_logic_vector(5 downto 0) := (others => '0');
  signal v6, v7, v8, v9 : std_logic_vector(5 downto 0) := (others => '0');
  signal ch_a, ch_b, ch_c, ch_d : signed(7 downto 0) := (others => '0');
  signal pag : std_logic_vector(5 downto 0);
  signal ler, esc : std_logic;
  signal oa, ob, oc, od : signed(14 downto 0) := (others => '0');
  signal ol, orr : signed(14 downto 0) := (others => '0');
begin
  cpu: entity work.T80se
    generic map (Mode => 0, T2Write => 1, IOWait => 1)
    port map (RESET_n => reset_n, CLK_n => clk, CLKEN => ce and not m_wait,
              WAIT_n => '1', INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
              M1_n => m1_n, MREQ_n => mreq_n, IORQ_n => iorq_n, RD_n => rd_n, WR_n => wr_n,
              RFSH_n => rfsh_n, HALT_n => open, BUSAK_n => open,
              A => a, DI => di, DO => do_c);

  -- INT a 37,5 kHz (37480 Hz como o MiSTer); sai na aceitacao
  process(clk)
  begin
    if rising_edge(clk) then
      tick <= '0';
      if acc + 37480 >= CLK_HZ then acc <= acc + 37480 - CLK_HZ; tick <= '1';
      else acc <= acc + 37480; end if;
      if tick = '1' then int_n <= '0'; end if;
      if iorq_n = '0' and m1_n = '0' then int_n <= '1'; end if;
    end if;
  end process;

  -- flags (o lado do GS primeiro, como no MiSTer)
  process(clk)
  begin
    if rising_edge(clk) then
      if iorq_n = '0' and m1_n = '1' then
        case a(3 downto 0) is
          when x"2" => bit7 <= '0';
          when x"3" => bit7 <= '1';
          when x"5" => bit0 <= '0';
          when x"A" => bit7 <= not p_00(0);
          when x"B" => bit0 <= v9(5);
          when others => null;
        end case;
      elsif cs_rd = '1' or cs_wr = '1' then
        if a3 = '0' and cs_rd = '1' then bit7 <= '0'; end if;
        if a3 = '0' and cs_wr = '1' then bit7 <= '1'; end if;
        if a3 = '1' and cs_wr = '1' then bit0 <= '1'; end if;
      end if;
    end if;
  end process;

  -- registos
  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        p_bb <= (others => '0'); p_b3 <= (others => '0');
        p_00 <= (others => '0'); p_03 <= (others => '0');
      else
        if cs_wr = '1' then
          if a3 = '1' then p_bb <= din; else p_b3 <= din; end if;
        end if;
        if iorq_n = '0' and wr_n = '0' and m1_n = '1' then
          case a(3 downto 0) is
            when x"0" => p_00 <= do_c(5 downto 0);
            when x"3" => p_03 <= do_c;
            when x"6" => v6 <= do_c(5 downto 0);
            when x"7" => v7 <= do_c(5 downto 0);
            when x"8" => v8 <= do_c(5 downto 0);
            when x"9" => v9 <= do_c(5 downto 0);
            when others => null;
          end case;
        end if;
        -- leituras em 6000h-7FFFh: o byte vai para o canal (A9-A8), ja' com sinal
        if ler = '1' and m_wait = '0' and ce = '1' and a(15 downto 13) = "011" then
          case a(9 downto 8) is
            when "00"   => ch_a <= signed((not m_q(7)) & m_q(6 downto 0));
            when "01"   => ch_b <= signed((not m_q(7)) & m_q(6 downto 0));
            when "10"   => ch_c <= signed((not m_q(7)) & m_q(6 downto 0));
            when others => ch_d <= signed((not m_q(7)) & m_q(6 downto 0));
          end case;
        end if;
      end if;
    end if;
  end process;

  dout <= (bit7 & "111111" & bit0) when a3 = '1' else p_03;

  -- memoria
  pag  <= p_00 when a(15) = '1' else "00000" & a(14);
  ler  <= '1' when mreq_n = '0' and rfsh_n = '1' and rd_n = '0' else '0';
  esc  <= '1' when mreq_n = '0' and rfsh_n = '1' and wr_n = '0' and pag /= "000000" else '0';   -- ROM so' de leitura
  m_a  <= pag & (a(15) and a(14)) & a(13 downto 0);
  m_rd <= ler;
  m_wr <= esc;
  m_d  <= do_c;

  di <= m_q when ler = '1' else
        p_bb when iorq_n = '0' and rd_n = '0' and a(3 downto 0) = x"1" else
        p_b3 when iorq_n = '0' and rd_n = '0' and a(3 downto 0) = x"2" else
        (bit7 & "111111" & bit0) when iorq_n = '0' and rd_n = '0' and a(3 downto 0) = x"4" else
        x"FF";

  -- 4 canais: amostra (8 bits com sinal) x volume (0-63)
  process(clk)
  begin
    if rising_edge(clk) then
      if ce = '1' then
        oa <= resize(ch_a * signed('0' & v6), 15);
        ob <= resize(ch_b * signed('0' & v7), 15);
        oc <= resize(ch_c * signed('0' & v8), 15);
        od <= resize(ch_d * signed('0' & v9), 15);
        ol <= oa + ob;
        orr <= oc + od;
      end if;
    end if;
  end process;
  out_l <= ol;
  out_r <= orr;
end architecture;
