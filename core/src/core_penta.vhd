-- core_penta.vhd: Pentagon 128 / 512 / 1024 (Z80 T80, ROM 32K, RAM ate' 1 MB).
--   Porto 7FFD (A15 = 0, A1 = 0): bits 2-0 banco, bit 3 ecra (banco 5 ou 7), bit 4 ROM,
--     bit 6 = banco bit 3, bit 7 = banco bit 4 (512K), bit 5 = banco bit 5 (1024K).
--   Porto EFF7 (A15-A13 = 111, A12 = 0, A3 = 0): bit 2 = 1 -> modo 128K (so' bancos 0-7 e
--     o bit 5 do 7FFD volta a ser o trinco). (Regras do Pentagon 1024 como no ZEsarUX e
--     no core MiSTer; o bit 3 do EFF7, RAM em 0000, ainda nao esta' feito.)
--   Bancos 5 e 7 (ecras) em BSRAM de dois portos; os outros na SDRAM (banco x 16K).
--   Quadro Pentagon: 71680 T (320 linhas x 224 T), INT de 32 T, sem contencao.
--   Portas sem dono (FF incluida) dao FF, como num Pentagon (sem bus flutuante).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity core_penta is
  generic (DIV : boolean := false);               -- true: DivMMC (esxDOS) com o cartao SD
  port (
    clk      : in  std_logic;                     -- 54 MHz
    vclk     : in  std_logic;
    ce       : in  std_logic;
    ce35     : in  std_logic;
    reset_n  : in  std_logic;
    nmi_n    : in  std_logic;
    mat      : in  std_logic_vector(39 downto 0);
    border   : out std_logic_vector(2 downto 0);
    ecra7    : out std_logic;                     -- 7FFD bit 3: o video mostra o banco 7
    vid_a    : in  std_logic_vector(14 downto 0); -- so' os bits 13-0: ecra capturado (formato hi-colour do Timex)
    vid_q    : out std_logic_vector(7 downto 0);
    ofs      : in  std_logic_vector(2 downto 0);  -- captura: T-states antes do ponto (afinacao)
    fsinc    : out std_logic;                     -- muda quando a linha 0 do ecra foi capturada (acerta o HDMI)
    halt_n   : out std_logic;
    pronta   : out std_logic;
    sd_clk, sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n : out std_logic;
    sd_ba    : out std_logic_vector(1 downto 0);
    sd_addr  : out std_logic_vector(10 downto 0);
    sd_dqm   : out std_logic_vector(3 downto 0);
    sd_dq_i  : in  std_logic_vector(31 downto 0);
    sd_dq_o  : out std_logic_vector(31 downto 0);
    sd_dq_oe : out std_logic;
    mmc_cs_n, mmc_sclk, mmc_mosi : out std_logic;
    mmc_miso : in  std_logic;
    -- som: AY (ABC: A e metade do B a' esquerda, C e metade do B a' direita) + beeper,
    --   sem sinal, 0..510 nos bits 9-0
    aud_l, aud_r : out std_logic_vector(15 downto 0);
    -- ULAplus: paleta (escrita pelo CPU) e o modo
    pal_a    : out std_logic_vector(5 downto 0);
    pal_we   : out std_logic;
    pal_d    : out std_logic_vector(7 downto 0);
    pal_q    : in  std_logic_vector(7 downto 0);
    ulap     : out std_logic
  );
end entity;

architecture rtl of core_penta is
  component T80se
    generic (Mode : integer := 0; T2Write : integer := 0; IOWait : integer := 1);
    port (RESET_n, CLK_n, CLKEN, WAIT_n, INT_n, NMI_n, BUSRQ_n : in std_logic;
          M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, BUSAK_n : out std_logic;
          A : out std_logic_vector(15 downto 0);
          DI : in std_logic_vector(7 downto 0);
          DO : out std_logic_vector(7 downto 0));
  end component;
  component rom_32k
    port (clk : in std_logic; a : in std_logic_vector(14 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  component ram_dp
    generic (AW : integer := 14);
    port (clk : in std_logic;
          a : in std_logic_vector(AW-1 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0);
          clkb : in std_logic;
          b : in std_logic_vector(AW-1 downto 0); bq : out std_logic_vector(7 downto 0));
  end component;

  signal a : std_logic_vector(15 downto 0);
  signal di, do_cpu : std_logic_vector(7 downto 0);
  signal m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n : std_logic;
  signal int_n : std_logic := '1';
  signal wr_mem : std_logic;
  signal q_rom, q_vid, q_sd : std_logic_vector(7 downto 0);
  signal tcnt : integer range 0 to 71679 := 0;
  signal teclas : std_logic_vector(4 downto 0);
  signal brd : std_logic_vector(2 downto 0) := "111";
  signal r7ffd : std_logic_vector(7 downto 0) := (others => '0');
  signal reff7 : std_logic_vector(7 downto 0) := (others => '0');
  signal io_wr : std_logic;
  -- banco no endereco actual
  signal banco : std_logic_vector(5 downto 0);
  signal e_rom, e_vid : std_logic;
  signal e_rom_l, e_vid_l : std_logic := '0';
  signal vid_aa : std_logic_vector(14 downto 0);
  -- captura do ecra ao ritmo do Pentagon: cada byte (bitmap e atributo) e' lido da RAM de
  -- video no T-state em que o Pentagon o leria (1.o ponto a 17988 T do INT, 224 T por linha,
  -- 4 T por byte) e guardado num ecra a parte, com um atributo por linha (como o hi-colour
  -- do Timex). O HDMI mostra esse ecra: o multicolor sai certo.
  signal cap_on, cap_go : std_logic := '0';
  signal lt : integer range 0 to 223 := 0;
  signal ly : unsigned(7 downto 0) := (others => '0');
  signal cx : unsigned(4 downto 0) := (others => '0');
  signal cs : integer range 0 to 7 := 7;
  signal cap_a : std_logic_vector(14 downto 0) := (others => '0');
  signal cap_q : std_logic_vector(7 downto 0);
  signal cw_a : std_logic_vector(13 downto 0) := (others => '0');
  signal cw_d : std_logic_vector(7 downto 0) := (others => '0');
  signal cw_we : std_logic := '0';
  signal boff : std_logic_vector(12 downto 0);
  signal fs_r : std_logic := '0';
  signal trinco : std_logic;
  -- SDRAM
  signal sd_ok, sd_livre, sd_req, sd_we, sd_rf : std_logic;
  signal feito, rf_feito : std_logic := '0';
  signal rf_t : unsigned(8 downto 0) := (others => '0');
  signal sd_a : std_logic_vector(22 downto 0);
  -- DivMMC
  component rom_esx
    port (clk : in std_logic; a : in std_logic_vector(12 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  signal d_mapa, d_eeprom, d_ramwe, d_porta, d_nmi_n : std_logic := '0';
  signal d_pag : std_logic_vector(5 downto 0);
  signal d_q, q_esx : std_logic_vector(7 downto 0);
  signal d_mapa_l, d_eeprom_l : std_logic := '0';
  signal div_ram, e_rom0 : std_logic;
  -- AY (FFFD: registo / leitura, BFFD: dados), 1,75 MHz
  signal ay_en, ay_meio : std_logic := '0';
  signal ay_sel, ay_we, ay_le : std_logic;
  signal ay_q, ay_a, ay_b, ay_c : std_logic_vector(7 downto 0);
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

  -- banco de 16K que esta' no endereco do CPU
  process(a, r7ffd, reff7)
    variable alto : std_logic_vector(2 downto 0);
  begin
    if reff7(2) = '1' then alto := "000";                    -- modo 128K
    else alto := r7ffd(5) & r7ffd(7) & r7ffd(6); end if;
    case a(15 downto 14) is
      when "01"   => banco <= "000101";                      -- 4000: banco 5
      when "10"   => banco <= "000010";                      -- 8000: banco 2
      when others => banco <= alto & r7ffd(2 downto 0);      -- C000: o escolhido
    end case;
  end process;
  e_rom0 <= '1' when a(15 downto 14) = "00" else '0';
  e_rom  <= e_rom0 and not d_mapa;                            -- com o DivMMC mapeado 0000-3FFF e' dele
  div_ram <= '1' when d_mapa = '1' and d_eeprom = '0' and e_rom0 = '1' else '0';
  e_vid <= '1' when a(15 downto 14) /= "00" and banco(5 downto 3) = "000"
                    and banco(2) = '1' and banco(0) = '1' else '0';   -- banco 5 ou 7

  wr_mem <= '1' when mreq_n = '0' and wr_n = '0' and rfsh_n = '1' else '0';

  rom: rom_32k port map (clk => clk, a => r7ffd(4) & a(13 downto 0), q => q_rom);
  -- bancos 5 (0xxx) e 7 (1xxx)
  vid_aa <= banco(1) & a(13 downto 0);
  vram: ram_dp generic map (AW => 15)
    port map (clk => clk, a => vid_aa, we => wr_mem and e_vid, d => do_cpu, q => q_vid,
              clkb => clk, b => cap_a, bq => cap_q);

  -- relogio da captura: linha 0 comeca (17988 - 1 - ofs) T depois do INT
  process(clk)
  begin
    if rising_edge(clk) then
      cap_go <= '0';
      if ce35 = '1' then
        if tcnt = 17987 - to_integer(unsigned(ofs)) then
          cap_on <= '1'; lt <= 0; ly <= (others => '0');
          cap_go <= '1'; cx <= (others => '0');
        elsif cap_on = '1' then
          if lt = 223 then
            lt <= 0;
            if ly = 191 then cap_on <= '0'; else ly <= ly + 1; cap_go <= '1'; cx <= (others => '0'); end if;
          else
            lt <= lt + 1;
            if ly = 0 and lt = 130 then fs_r <= not fs_r; end if;
            if lt mod 4 = 3 and lt < 127 then cap_go <= '1'; cx <= to_unsigned((lt + 1) / 4, 5); end if;
          end if;
        end if;
      end if;
    end if;
  end process;
  fsinc <= fs_r;
  boff <= std_logic_vector(ly(7 downto 6) & ly(2 downto 0) & ly(5 downto 3) & cx);
  -- 2 leituras (bitmap, atributo) e 2 escritas no ecra capturado, a 54 MHz
  process(clk)
  begin
    if rising_edge(clk) then
      cw_we <= '0';
      if cap_go = '1' then
        cap_a <= r7ffd(3) & '0' & boff; cs <= 0;                 -- bitmap
      elsif cs /= 7 then
        cs <= cs + 1;
        case cs is
          when 0 => cap_a <= r7ffd(3) & "0110" & std_logic_vector(ly(7 downto 3) & cx);  -- atributo
          when 1 => cw_a <= '0' & boff; cw_d <= cap_q; cw_we <= '1';                     -- bitmap
          when 2 => cw_a <= '1' & boff; cw_d <= cap_q; cw_we <= '1';                     -- atributo da linha
          when others => cs <= 7;
        end case;
      end if;
    end if;
  end process;
  cap: ram_dp generic map (AW => 14)
    port map (clk => clk, a => cw_a, we => cw_we, d => cw_d, q => open,
              clkb => vclk, b => vid_a(13 downto 0), bq => vid_q);

  -- os outros bancos na SDRAM
  -- bancos ate' 1 MB; RAM do DivMMC (paginas de 8K) a partir de 1 MB
  sd_a <= "001" & '0' & d_pag & a(12 downto 0) when div_ram = '1' else "000" & banco & a(13 downto 0);
  sd_req <= '1' when mreq_n = '0' and rfsh_n = '1' and feito = '0' and
                     ((e_rom0 = '0' and e_vid = '0' and (rd_n = '0' or wr_n = '0')) or
                      (div_ram = '1' and (rd_n = '0' or (wr_n = '0' and d_ramwe = '1')))) else '0';
  sd_we  <= not wr_n;
  sd_rf  <= '1' when (mreq_n = '0' and rfsh_n = '0' and rf_feito = '0') or rf_t = 511 else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      e_rom_l <= e_rom; e_vid_l <= e_vid; d_mapa_l <= d_mapa and e_rom0; d_eeprom_l <= d_eeprom;
      if mreq_n = '1' then feito <= '0';
      elsif sd_req = '1' and sd_livre = '1' and sd_rf = '0' then feito <= '1'; end if;
      if mreq_n = '1' then rf_feito <= '0';
      elsif sd_rf = '1' and sd_livre = '1' then rf_feito <= '1'; end if;
      if sd_rf = '1' and sd_livre = '1' then rf_t <= (others => '0');
      elsif rf_t /= 511 then rf_t <= rf_t + 1; end if;
    end if;
  end process;

  sdr: entity work.sdram
    port map (clk => clk, pronta => sd_ok, req => sd_req, we => sd_we, a => sd_a, d => do_cpu,
              q => q_sd, rf => sd_rf, livre => sd_livre,
              sd_clk => sd_clk, sd_cke => sd_cke, sd_cs_n => sd_cs_n, sd_ras_n => sd_ras_n,
              sd_cas_n => sd_cas_n, sd_we_n => sd_we_n, sd_ba => sd_ba, sd_addr => sd_addr,
              sd_dqm => sd_dqm, sd_dq_i => sd_dq_i, sd_dq_o => sd_dq_o, sd_dq_oe => sd_dq_oe);
  pronta <= sd_ok;

  -- DivMMC: traps do 48K so' com a ROM do 48K (7FFD bit 4); 0066 (NMI) com qualquer ROM
  div_g: if DIV generate
    dmmc: entity work.divmmc
      port map (clk => clk, reset_n => reset_n, a => a, d => do_cpu,
                mreq_n => mreq_n, iorq_n => iorq_n, rd_n => rd_n, wr_n => wr_n, m1_n => m1_n,
                inrom48k => r7ffd(4), modo2068 => '0', exlo => '0', nmi128 => '1', sem38 => '0',
                nmi_bot => not nmi_n, nmi_n => d_nmi_n,
                mapa => d_mapa, e_eeprom => d_eeprom, pagina => d_pag, ram_we => d_ramwe,
                e_porta => d_porta, q_porta => d_q,
                sd_cs_n => mmc_cs_n, sd_sclk => mmc_sclk, sd_mosi => mmc_mosi, sd_miso => mmc_miso);
    esx: rom_esx port map (clk => clk, a => a(12 downto 0), q => q_esx);
  end generate;
  sem_div_g: if not DIV generate
    d_nmi_n <= nmi_n; d_mapa <= '0'; d_eeprom <= '0'; d_ramwe <= '0'; d_porta <= '0';
    d_pag <= (others => '0'); d_q <= x"FF"; q_esx <= x"FF";
    mmc_cs_n <= '1'; mmc_sclk <= '0'; mmc_mosi <= '1';
  end generate;

  -- teclado
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
      di <= x"FF";
    elsif iorq_n = '0' and d_porta = '1' then
      di <= d_q;                                     -- porta EB do DivMMC
    elsif ay_le = '1' then
      di <= ay_q;                                    -- AY (FFFD)
    elsif iorq_n = '0' and u_porta = '1' then
      di <= u_q;                                    -- ULAplus (BF3B / FF3B)
    elsif iorq_n = '0' then
      if a(0) = '0' then di <= "101" & teclas;       -- FE (EAR a 0)
      else di <= x"FF"; end if;                      -- sem bus flutuante
    elsif d_mapa_l = '1' then
      if d_eeprom_l = '1' then di <= q_esx; else di <= q_sd; end if;   -- esxDOS / RAM do DivMMC
    elsif e_rom_l = '1' then di <= q_rom;
    elsif e_vid_l = '1' then di <= q_vid;
    else di <= q_sd;
    end if;
  end process;

  -- portas
  trinco <= r7ffd(5) when reff7(2) = '1' else '0';   -- no 1024K o bit 5 e' banco, sem trinco
  io_wr <= '1' when iorq_n = '0' and wr_n = '0' and m1_n = '1' else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        brd <= "111"; r7ffd <= (others => '0'); reff7 <= (others => '0');
      elsif io_wr = '1' then
        if a(0) = '0' then brd <= do_cpu(2 downto 0); beep <= do_cpu(4); end if;
        if a(15) = '0' and a(1) = '0' and trinco = '0' then r7ffd <= do_cpu; end if;
        if a(15 downto 12) = "1110" and a(3) = '0' then reff7 <= do_cpu; end if;
      end if;
    end if;
  end process;
  border <= brd;

  -- AY: FFFD (A15 = 1, A14 = 1, A1 = 0) e BFFD (A15 = 1, A14 = 0, A1 = 0)
  ay_sel <= '1' when io_wr = '1' and a(15 downto 14) = "11" and a(1) = '0' else '0';
  ay_we  <= '1' when io_wr = '1' and a(15 downto 14) = "10" and a(1) = '0' else '0';
  ay_le  <= '1' when iorq_n = '0' and rd_n = '0' and m1_n = '1' and a(15 downto 14) = "11" and a(1) = '0' else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      ay_en <= '0';
      if ce35 = '1' then ay_meio <= not ay_meio; ay_en <= ay_meio; end if;
    end if;
  end process;
  ay: entity work.YM2149
    port map (CLK => clk, ENA => ay_en, RESET_H => not reset_n, I_SEL_L => '1',
              I_DA => do_cpu, O_DA => ay_q, I_REG => '0',
              busctrl_addr => ay_sel, busctrl_we => ay_we, ctrl_aymode => '1',
              port_a_i => (others => '1'), port_a_o => open, port_b_i => (others => '1'), port_b_o => open,
              O_AUDIO_A => ay_a, O_AUDIO_B => ay_b, O_AUDIO_C => ay_c);
  -- mistura do AY e do beeper (0..510, sem sinal); o som.vhd faz as amostras de 48 kHz
  process(clk)
    variable l, r : unsigned(9 downto 0);
  begin
    if rising_edge(clk) then
      l := ("00" & unsigned(ay_a)) + ("000" & unsigned(ay_b(7 downto 1)));
      r := ("00" & unsigned(ay_c)) + ("000" & unsigned(ay_b(7 downto 1)));
      if beep = '1' then l := l + 128; r := r + 128; end if;
      aud_l <= "000000" & std_logic_vector(l);
      aud_r <= "000000" & std_logic_vector(r);
    end if;
  end process;
  ecra7  <= r7ffd(3);

  -- quadro Pentagon: 71680 T, INT de 32 T
  process(clk)
  begin
    if rising_edge(clk) then
      if ce35 = '1' then
        if tcnt = 71679 then tcnt <= 0; else tcnt <= tcnt + 1; end if;
        if tcnt < 36 then int_n <= '0'; else int_n <= '1'; end if;   -- 36 T, como no Fuse e no SCLD
      end if;
    end if;
  end process;

  ulp: entity work.ulaplus
    port map (clk => clk, reset_n => reset_n, a => a, d => do_cpu,
              iorq_n => iorq_n, rd_n => rd_n, wr_n => wr_n, m1_n => m1_n,
              e_porta => u_porta, q_porta => u_q,
              pal_a => pal_a, pal_we => pal_we, pal_d => pal_d, pal_q => pal_q, ligado => ulap);
end architecture;
