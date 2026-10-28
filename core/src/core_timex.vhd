-- core_timex.vhd: Z80 (T80) + memoria e portas do Timex TC2048 / TC2068.
--   Portas como no SCLD do Timmy (v13), descodificadas pelo byte baixo:
--     FE  escrita: borda (bits 2-0)   leitura: 0 & EAR & 0 & teclas
--     FF  escrita/leitura: bit 7 EXROM(1)/DOCK(0), bit 6 INT desligada,
--         bits 5-3 cor do hi-res, bits 2-0 modo do ecra
--     F4  (so' TC2068) escrita/leitura: blocos de 8K para o DOCK/EXROM (1) ou HOME (0)
--   Bloco com o bit do F4 a 1: com o FF bit 7 a 1 le-se a EXROM (8K, repetida);
--   a 0 e' o DOCK, que esta' vazio (le FF). Nesses blocos nao se escreve na RAM.
--   Quadro de 69888 T (312 linhas x 224 T, 50 Hz), INT de 32 T, sem contencao (para ja').
--   Em turbo o quadro e a INT continuam a 50 Hz (contam com o ce35).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity core_timex is
  generic (M2068 : boolean := true;               -- false: TC2048 (sem F4 nem EXROM)
           DIV   : boolean := false;              -- true: DivMMC (esxDOS) com o cartao SD
           DIV_BRAM : boolean := false;           -- true: RAM do DivMMC em BSRAM (32K, 4 paginas) e nao na SDRAM
           ALTA_BRAM : boolean := false);         -- true: 8000-FFFF em BSRAM (a SDRAM fica so' para o DivMMC)
  port (
    clk      : in  std_logic;                     -- relogio do core e da SDRAM (54 MHz)
    vclk     : in  std_logic;                     -- relogio do video (le o porto B da RAM)
    ce       : in  std_logic;                     -- 1 ciclo em cada T-state do Z80 (3,5 MHz ou turbo)
    ce35     : in  std_logic;                     -- sempre a 3,5 MHz: conta o quadro (INT a 50 Hz)
    reset_n  : in  std_logic;
    nmi_n    : in  std_logic;
    mat      : in  std_logic_vector(39 downto 0); -- teclado 8 x 5, bit fila*5+coluna, 1 = carregada
    border   : out std_logic_vector(2 downto 0);
    modo     : out std_logic_vector(2 downto 0);  -- FF bits 2-0
    hcor     : out std_logic_vector(2 downto 0);  -- FF bits 5-3
    vid_a    : in  std_logic_vector(13 downto 0); -- RAM do ecra desde 4000 (4000-7FFF)
    vid_q    : out std_logic_vector(7 downto 0);
    halt_n   : out std_logic;
    pronta   : out std_logic;                     -- SDRAM inicializada (antes disso o Z80 fica em reset)
    sd_teste : out std_logic;                     -- 1 = a SDRAM passou o teste do arranque
    sd_teste2 : out std_logic;                    -- 1 = passou o teste dos bytes na mesma palavra (DQM)
    -- SDRAM (8000-FFFF por agora)
    sd_clk, sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n : out std_logic;
    sd_ba    : out std_logic_vector(1 downto 0);
    sd_addr  : out std_logic_vector(10 downto 0);
    sd_dqm   : out std_logic_vector(3 downto 0);
    sd_dq_i  : in  std_logic_vector(31 downto 0);
    sd_dq_o  : out std_logic_vector(31 downto 0);
    sd_dq_oe : out std_logic;
    -- cartao SD (DivMMC)
    mmc_cs_n, mmc_sclk, mmc_mosi : out std_logic;
    mmc_miso : in  std_logic;
    aud_l, aud_r : out std_logic_vector(15 downto 0);
    -- ULAplus: paleta (escrita pelo CPU) e o modo
    pal_a    : out std_logic_vector(5 downto 0);
    pal_we   : out std_logic;
    pal_d    : out std_logic_vector(7 downto 0);
    pal_q    : in  std_logic_vector(7 downto 0);
    ulap     : out std_logic   -- som (por agora so' o beeper)
  );
end entity;

architecture rtl of core_timex is
  component T80se
    generic (Mode : integer := 0; T2Write : integer := 0; IOWait : integer := 1);
    port (RESET_n, CLK_n, CLKEN, WAIT_n, INT_n, NMI_n, BUSRQ_n : in std_logic;
          M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, BUSAK_n : out std_logic;
          A : out std_logic_vector(15 downto 0);
          DI : in std_logic_vector(7 downto 0);
          DO : out std_logic_vector(7 downto 0));
  end component;
  component rom_home
    port (clk : in std_logic; a : in std_logic_vector(13 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  component rom_esx
    port (clk : in std_logic; a : in std_logic_vector(12 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  component rom_ex
    port (clk : in std_logic; a : in std_logic_vector(12 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  component ram_dp
    generic (AW : integer := 14);
    port (clk : in std_logic;
          a : in std_logic_vector(AW-1 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0);
          clkb : in std_logic;
          b : in std_logic_vector(AW-1 downto 0); bq : out std_logic_vector(7 downto 0));
  end component;
  component ram_sp
    generic (AW : integer := 15);
    port (clk : in std_logic; a : in std_logic_vector(AW-1 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0));
  end component;

  signal a, a_l : std_logic_vector(15 downto 0);
  signal di, di_c, do_cpu : std_logic_vector(7 downto 0);
  signal m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n : std_logic;
  signal int_n : std_logic := '1';
  signal wr_mem, home, home_l : std_logic;
  signal we_scr : std_logic;
  signal q_rom, q_ex, q_scr, q_alta : std_logic_vector(7 downto 0);
  -- pedidos 'a SDRAM
  signal sd_ok, sd_livre, sd_req, sd_we, sd_rf : std_logic;
  signal feito, rf_feito : std_logic := '0';
  -- DivMMC
  signal d_mapa, d_eeprom, d_ramwe, d_porta, d_nmi_n : std_logic := '0';
  signal d_pag : std_logic_vector(5 downto 0);
  signal d_q, q_esx : std_logic_vector(7 downto 0);
  signal d_mapa_l, d_eeprom_l : std_logic := '0';
  signal sd_a : std_logic_vector(22 downto 0);
  signal div_ram : std_logic;
  signal m68, exlo : std_logic;
  signal q_dram : std_logic_vector(7 downto 0) := x"FF";
  signal q_abr: std_logic_vector(7 downto 0) := x"FF";
  signal rf_t : unsigned(8 downto 0) := (others => '0');   -- ~9,5 us sem refresh -> refresh
  signal tcnt : integer range 0 to 69887 := 0;
  signal teclas : std_logic_vector(4 downto 0);
  -- registos
  signal brd     : std_logic_vector(2 downto 0) := "111";
  signal regff   : std_logic_vector(7 downto 0) := (others => '0');
  signal banksel : std_logic_vector(7 downto 0) := (others => '0');
  signal io_wr, io_rd : std_logic;
  signal beep : std_logic := '0';
  signal u_porta : std_logic;
  signal u_q : std_logic_vector(7 downto 0);
begin
  cpu: T80se
    generic map (Mode => 0, T2Write => 1, IOWait => 1)
    port map (RESET_n => reset_n, CLK_n => clk, CLKEN => ce,
              WAIT_n => '1', INT_n => int_n, NMI_n => d_nmi_n, BUSRQ_n => '1',
              M1_n => m1_n, MREQ_n => mreq_n, IORQ_n => iorq_n, RD_n => rd_n, WR_n => wr_n,
              RFSH_n => rfsh_n, HALT_n => halt_n, BUSAK_n => open,
              A => a, DI => di, DO => do_cpu);

  -- bloco de 8K na HOME (bit do F4 a 0)
  home <= not banksel(to_integer(unsigned(a(15 downto 13))));

  wr_mem  <= '1' when mreq_n = '0' and wr_n = '0' and rfsh_n = '1' else '0';
  we_scr  <= wr_mem and home when a(15 downto 14) = "01" else '0';

  rom: rom_home port map (clk => clk, a => a(13 downto 0), q => q_rom);
  exr: rom_ex   port map (clk => clk, a => a(12 downto 0), q => q_ex);
  scr: ram_dp generic map (AW => 14)
    port map (clk => clk, a => a(13 downto 0), we => we_scr, d => do_cpu, q => q_scr,
              clkb => vclk, b => vid_a, bq => vid_q);
  -- 8000-FFFF na SDRAM. Um pedido por cada acesso do Z80 (leitura logo com o RD,
  -- escrita com o WR, quando o dado ja' esta' no barramento). Refresh nos ciclos de
  -- refresh do Z80 (RFSH) ou, se o Z80 parar (reset), por tempo.
  -- RAM do DivMMC (2000-3FFF, ou a pagina 3 em 0000) a partir de 1 MB na SDRAM
  div_ram <= '1' when d_mapa = '1' and d_eeprom = '0' and a(15 downto 14) = "00" else '0';
  sd_a <= "001" & '0' & d_pag & a(12 downto 0) when div_ram = '1'
          else "00000000" & a(14 downto 0);
  sd_req <= '1' when mreq_n = '0' and rfsh_n = '1' and feito = '0' and
                     ((a(15) = '1' and not ALTA_BRAM and (rd_n = '0' or (wr_n = '0' and home = '1'))) or
                      (div_ram = '1' and not DIV_BRAM and (rd_n = '0' or (wr_n = '0' and d_ramwe = '1')))) else '0';
  sd_we  <= not wr_n;
  sd_rf  <= '1' when (mreq_n = '0' and rfsh_n = '0' and rf_feito = '0') or rf_t = 511 else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if mreq_n = '1' then feito <= '0';
      elsif sd_req = '1' and sd_livre = '1' and sd_rf = '0' then feito <= '1'; end if;
      if mreq_n = '1' then rf_feito <= '0';
      elsif sd_rf = '1' and sd_livre = '1' then rf_feito <= '1'; end if;
      if sd_rf = '1' and sd_livre = '1' then rf_t <= (others => '0');
      elsif rf_t /= 511 then rf_t <= rf_t + 1; end if;
    end if;
  end process;

  sdr: entity work.sdram
    port map (clk => clk, pronta => sd_ok, teste_ok => sd_teste, teste_ok2 => sd_teste2, req => sd_req, we => sd_we,
              a => sd_a, d => do_cpu, q => q_alta,
              rf => sd_rf, livre => sd_livre,
              sd_clk => sd_clk, sd_cke => sd_cke, sd_cs_n => sd_cs_n, sd_ras_n => sd_ras_n,
              sd_cas_n => sd_cas_n, sd_we_n => sd_we_n, sd_ba => sd_ba, sd_addr => sd_addr,
              sd_dqm => sd_dqm, sd_dq_i => sd_dq_i, sd_dq_o => sd_dq_o, sd_dq_oe => sd_dq_oe);
  pronta <= sd_ok;

  -- 8000-FFFF em BSRAM (32K)
  alta_g: if ALTA_BRAM generate
    alta: ram_sp generic map (AW => 15)
      port map (clk => clk, a => a(14 downto 0),
                we => wr_mem and home and a(15), d => do_cpu, q => q_abr);
  end generate;

  -- a leitura sai 1 ciclo rapido depois do endereco
  process(clk)
  begin
    if rising_edge(clk) then a_l <= a; home_l <= home; d_mapa_l <= d_mapa; d_eeprom_l <= d_eeprom; end if;
  end process;

  m68  <= '1' when M2068 else '0';
  exlo <= '1' when M2068 and banksel(0) = '1' and regff(7) = '1' else '0';  -- EXROM em 0000-1FFF

  div_g: if DIV generate
    dmmc: entity work.divmmc
      port map (clk => clk, reset_n => reset_n, a => a, d => do_cpu,
                mreq_n => mreq_n, iorq_n => iorq_n, rd_n => rd_n, wr_n => wr_n, m1_n => m1_n,
                inrom48k => '1', modo2068 => m68, exlo => exlo,
                nmi_bot => not nmi_n, nmi_n => d_nmi_n,
                mapa => d_mapa, e_eeprom => d_eeprom, pagina => d_pag, ram_we => d_ramwe,
                e_porta => d_porta, q_porta => d_q,
                sd_cs_n => mmc_cs_n, sd_sclk => mmc_sclk, sd_mosi => mmc_mosi, sd_miso => mmc_miso);
    esx: rom_esx port map (clk => clk, a => a(12 downto 0), q => q_esx);
    -- teste: RAM do DivMMC em BSRAM (paginas 0-3, as outras repetem-se)
    bram_g: if DIV_BRAM generate
      dram: ram_sp generic map (AW => 15)
        port map (clk => clk, a => d_pag(1 downto 0) & a(12 downto 0),
                  we => wr_mem and div_ram and d_ramwe, d => do_cpu, q => q_dram);
    end generate;
  end generate;
  sem_div_g: if not DIV generate
    d_nmi_n <= nmi_n; d_mapa <= '0'; d_eeprom <= '0'; d_ramwe <= '0'; d_porta <= '0';
    d_pag <= (others => '0'); d_q <= x"FF"; q_esx <= x"FF";
    mmc_cs_n <= '1'; mmc_sclk <= '0'; mmc_mosi <= '1';
  end generate;

  -- matriz do teclado: as filas escolhem-se com A8-A15 a 0; no porto, 0 = carregada
  process(a, mat)
    variable v : std_logic_vector(4 downto 0);
  begin
    v := (others => '0');
    for f in 0 to 7 loop
      if a(8 + f) = '0' then v := v or mat(f*5 + 4 downto f*5); end if;
    end loop;
    teclas <= not v;
  end process;

  process(all)
  begin
    if iorq_n = '0' and m1_n = '0' then
      di_c <= x"FF";                                   -- aceitacao da INT
    elsif iorq_n = '0' and d_porta = '1' then
      di_c <= d_q;                                     -- porta EB do DivMMC
    elsif iorq_n = '0' and u_porta = '1' then
      di_c <= u_q;                                    -- ULAplus (BF3B / FF3B)
    elsif iorq_n = '0' then
      case a(7 downto 0) is
        when x"FE" => di_c <= "000" & teclas;          -- EAR a 0 (sem cassete)
        when x"FF" => di_c <= regff;
        when x"F4" => if M2068 then di_c <= banksel; else di_c <= x"FF"; end if;
        when others => di_c <= x"FF";
      end case;
    elsif d_mapa_l = '1' and a_l(15 downto 14) = "00" then
      if d_eeprom_l = '1' then di_c <= q_esx;          -- esxDOS
      elsif DIV_BRAM then di_c <= q_dram;              -- RAM do DivMMC (BSRAM, teste)
      else di_c <= q_alta; end if;                     -- RAM do DivMMC (SDRAM)
    elsif home_l = '0' then
      if regff(7) = '1' then di_c <= q_ex;             -- EXROM
      else di_c <= x"FF"; end if;                      -- DOCK vazio
    else
      case a_l(15 downto 14) is
        when "00"   => di_c <= q_rom;
        when "01"   => di_c <= q_scr;
        when others => if ALTA_BRAM then di_c <= q_abr; else di_c <= q_alta; end if;
      end case;
    end if;
  end process;

  -- com o core a 27 MHz o caminho RAM -> Z80 cabe num ciclo: sem registo (precisa-se
  -- disto no turbo, em que o Z80 le o dado poucos ciclos depois do endereco)
  di <= di_c;

  aud_l <= x"0080" when beep = '1' else x"0000";   -- sem sinal, na escala do AY (0..510)
  aud_r <= x"0080" when beep = '1' else x"0000";

  io_wr <= '1' when iorq_n = '0' and wr_n = '0' and m1_n = '1' else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        brd <= "111"; regff <= (others => '0'); banksel <= (others => '0');
      elsif io_wr = '1' then
        case a(7 downto 0) is
          when x"FE" => brd <= do_cpu(2 downto 0); beep <= do_cpu(4);
          when x"FF" => regff <= do_cpu;
          when x"F4" => if M2068 then banksel <= do_cpu; end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;
  border <= brd;
  modo   <= regff(2 downto 0);
  hcor   <= regff(5 downto 3);

  -- quadro de 69888 T, INT durante os primeiros 32 (FF bit 6 desliga-a)
  process(clk)
  begin
    if rising_edge(clk) then
      if ce35 = '1' then
        if tcnt = 69887 then tcnt <= 0; else tcnt <= tcnt + 1; end if;
        if tcnt < 32 and regff(6) = '0' then int_n <= '0'; else int_n <= '1'; end if;
      end if;
    end if;
  end process;

  ulp: entity work.ulaplus
    port map (clk => clk, reset_n => reset_n, a => a, d => do_cpu,
              iorq_n => iorq_n, rd_n => rd_n, wr_n => wr_n, m1_n => m1_n,
              e_porta => u_porta, q_porta => u_q,
              pal_a => pal_a, pal_we => pal_we, pal_d => pal_d, pal_q => pal_q, ligado => ulap);
end architecture;
