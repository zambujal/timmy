-- top.vhd: Timmy HDMI, fase 1 (Tang Nano 20K, GW2AR-18).
-- Cristal de 27 MHz -> PLL 135 MHz (serie TMDS, DDR) -> /5 = 27 MHz (ponto).
-- Fase 3: Timex TC2068 / TC2048 (Z80, ROM HOME + EXROM, RAM 48K, portas FE/FF/F4), video HDMI.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  generic (MODO720 : boolean := true;      -- false: 576p50 (27 MHz); true: 720p50 (74,25 MHz)
           MODO480 : boolean := false;     -- true: 640x480p60 (25,2 MHz), tem prioridade
           M2068   : boolean := false;      -- true: TC2068; false: TC2048
           VEL     : integer := 1;         -- velocidade do Z80: 1 = 3,5 MHz, 2 = 7, 4 = 14
           SID     : boolean := false;       -- Timmy: os dois SID (xxCF)
           TIMMY   : boolean := true;     -- true: o Timmy inteiro (SCLD v13 + DivTIESUS v13), todas as maquinas
           PENTA   : boolean := false;     -- true: Pentagon 128/512/1024 (em vez do Timex)
           DIVMMC  : boolean := true;
           DIV_BRAM : boolean := false;    -- teste: RAM do DivMMC em BSRAM
           ALTA_BRAM : boolean := false;   -- 8000-FFFF em BSRAM
           BROWSE  : boolean := false;     -- o botao A escreve .browser em vez de .ls
           PEEKT   : boolean := false;
           AUD_TESTE : integer := 0;
           PENTA50 : boolean := false;     -- Pentagon a 3,584 MHz preso aos 50 Hz do HDMI (senao 3,5 MHz certos)
           CAP_OFS : integer := 3;         -- Pentagon: captura do ecra N T-states antes do ponto
           CAP_TESTE : boolean := false);  -- true: o botao A muda o CAP_OFS (0-7), LEDs 4-6 mostram-no      -- som: 0 = da maquina, 1 = silencio, 2 = tom de 1 kHz (teste do HDMI)    -- o botao A escreve PRINT PEEK 23733 (teste da SDRAM)    -- true: DivMMC com o cartao SD (so' no Timex por agora)    -- true: Pentagon 128/512/1024 (em vez do Timex)  
  port (
    I_clk          : in  std_logic;                     -- 27 MHz (pino 4)
    I_reset        : in  std_logic;                     -- botao do pino 88 (1 = carregado): escreve o programa de teste
    I_nmi          : in  std_logic;                     -- botao do pino 87 (1 = carregado): BREAK
    O_tmds_clk_p   : out std_logic;
    O_tmds_clk_n   : out std_logic;
    O_tmds_data_p  : out std_logic_vector(2 downto 0);
    O_tmds_data_n  : out std_logic_vector(2 downto 0);
    O_led          : out std_logic_vector(1 downto 0);  -- activos a 0
    O_led3         : out std_logic;                     -- LED 3 (pino 17): teste DQM da SDRAM
    O_led_ofs      : out std_logic_vector(2 downto 0);  -- LEDs 4-6 (pinos 18-20): CAP_OFS no teste
    -- SDRAM de dentro do GW2AR (o apicula liga estes nomes 'a SDRAM)
    O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n : out std_logic;
    O_sdram_dqm    : out std_logic_vector(3 downto 0);
    O_sdram_addr   : out std_logic_vector(10 downto 0);
    O_sdram_ba     : out std_logic_vector(1 downto 0);
    IO_sdram_dq    : inout std_logic_vector(31 downto 0);
    -- cartao microSD da placa (SPI)
    O_sd_clk, O_sd_mosi, O_sd_cs_n : out std_logic;
    O_sd_dat1, O_sd_dat2 : out std_logic;              -- a 1 em SPI (como no exemplo da Sipeed)
    I_sd_miso      : in  std_logic;
    O_reconfig_n   : out std_logic;                     -- pino 73 -> fio -> TP1 (RECONFIG_N): a 0 carrega o core seguinte
    -- FPGA-Companion no BL616 da placa (teclado USB): SPI modo 1, o BL616 e' o mestre
    I_spi_csn      : in  std_logic;                     -- pino 86
    I_spi_sclk     : in  std_logic;                     -- pino 13
    I_spi_mosi     : in  std_logic;                     -- pino 76
    O_spi_miso     : out std_logic;                     -- pino 75
    O_spi_irqn     : out std_logic;                     -- pino 69
    -- 2026-10-22: ESP32-S3 (SPI octal; ver claude/esp32-shield.md)
    IO_esp_d       : inout std_logic_vector(7 downto 0);  -- pinos 27 28 26 25 29 30 31 42
    I_esp_clk      : in  std_logic;                     -- pino 41
    I_esp_cs       : in  std_logic;                     -- pino 48
    I_esp_dir      : in  std_logic;                     -- pino 49: 1 = o ESP le (a FPGA pode conduzir)
    O_esp_irq      : out std_logic;                     -- pino 55
    -- (esp54) som do ESP por I2S (o ESP e' o mestre)
    I_i2s_bck      : in  std_logic;                     -- pino 71 (J5 18) <- GPIO 8
    I_i2s_ws       : in  std_logic;                     -- pino 53 (J5 19) <- GPIO 9
    I_i2s_d        : in  std_logic                      -- pino 52 (J5 20) <- GPIO 10
  );
end entity;

architecture rtl of top is
  component rPLL
    generic (
      FCLKIN : string := "100.0"; DYN_IDIV_SEL : string := "false"; IDIV_SEL : integer := 0;
      DYN_FBDIV_SEL : string := "false"; FBDIV_SEL : integer := 0;
      DYN_ODIV_SEL : string := "false"; ODIV_SEL : integer := 8;
      PSDA_SEL : string := "0000"; DYN_DA_EN : string := "false"; DUTYDA_SEL : string := "1000";
      CLKOUT_FT_DIR : bit := '1'; CLKOUTP_FT_DIR : bit := '1';
      CLKOUT_DLY_STEP : integer := 0; CLKOUTP_DLY_STEP : integer := 0;
      CLKFB_SEL : string := "internal"; CLKOUT_BYPASS : string := "false";
      CLKOUTP_BYPASS : string := "false"; CLKOUTD_BYPASS : string := "false";
      DYN_SDIV_SEL : integer := 2; CLKOUTD_SRC : string := "CLKOUT"; CLKOUTD3_SRC : string := "CLKOUT";
      DEVICE : string := "GW2AR-18C"
    );
    port (
      CLKOUT, LOCK, CLKOUTP, CLKOUTD, CLKOUTD3 : out std_logic;
      RESET, RESET_P, CLKIN, CLKFB : in std_logic;
      FBDSEL, IDSEL, ODSEL : in std_logic_vector(5 downto 0);
      PSDA, DUTYDA, FDLY : in std_logic_vector(3 downto 0)
    );
  end component;

  component CLKDIV
    generic (DIV_MODE : string := "2"; GSREN : string := "false");
    port (CLKOUT : out std_logic; HCLKIN, RESETN, CALIB : in std_logic);
  end component;

  component OSER10
    generic (GSREN : string := "false"; LSREN : string := "true");
    port (
      Q : out std_logic;
      D0, D1, D2, D3, D4, D5, D6, D7, D8, D9 : in std_logic;
      FCLK, PCLK, RESET : in std_logic
    );
  end component;

  component IOBUF
    port (O : out std_logic; IO : inout std_logic; I, OEN : in std_logic);
  end component;

  component TLVDS_OBUF
    port (O, OB : out std_logic; I : in std_logic);
  end component;

  signal sclk, pclk, lock : std_logic;
  signal rst : std_logic := '1';
  signal arr : unsigned(7 downto 0) := (others => '0');
  signal r, g, b : std_logic_vector(7 downto 0);
  signal de, hs, vs : std_logic;
  signal aud_l, aud_r : std_logic_vector(15 downto 0);
  signal aud_tl, aud_tr : std_logic_vector(15 downto 0);
  -- (esp49) o som do ESP (MP3/WAV, 16 bits a 48 kHz) somado aqui, ja' em 16 bits, a' saida do som.vhd
  signal aud_hl, aud_hr, mp_l, mp_r : std_logic_vector(15 downto 0) := (others => '0');
  signal aud_tog2, aud_tg_d, mp_alto : std_logic := '0';
  signal aud_tog : std_logic;
  signal fsinc : std_logic := '0';
  signal aud_in_l, aud_in_r : std_logic_vector(13 downto 0);
  signal tom_c : integer range 0 to 65535 := 0;
  signal tom : std_logic := '0';
  signal ctl : std_logic_vector(1 downto 0);
  type sym_t is array (0 to 3) of std_logic_vector(9 downto 0);
  signal sym : sym_t;
  signal ser : std_logic_vector(3 downto 0);
  signal pos : std_logic_vector(3 downto 0);
  signal neg : std_logic_vector(3 downto 0);
  signal cnt : unsigned(24 downto 0) := (others => '0');
  signal border : std_logic_vector(2 downto 0);
  signal va : std_logic_vector(13 downto 0);
  signal va2 : std_logic_vector(13 downto 0);
  signal vq2 : std_logic_vector(7 downto 0) := (others => '0');
  signal m16c_c, m16c_v : std_logic := '0';
  signal rato_x, rato_y : std_logic_vector(7 downto 0);
  signal rato_b : std_logic_vector(2 downto 0);
  signal joy_k, joy_usb : std_logic_vector(7 downto 0);
  signal pede_rnmi : std_logic := '0';
  signal vq : std_logic_vector(7 downto 0);
  signal modo, hcor : std_logic_vector(2 downto 0);
  signal mat, mat_auto, mat_usb, mat_arr, mat_fis : std_logic_vector(39 downto 0);
  signal k_cap, k_turbo : std_logic := '0';
  signal arr_segura, arr_pisca, arr_nmi : std_logic;
  signal arr_esc : std_logic_vector(3 downto 0);
  signal mcu_sys_stb, mcu_hid_stb, mcu_ini, usb_f11 : std_logic;
  signal usb_cad : std_logic := '0';
  signal mp_on : std_logic := '0';
  signal i2s_on, mp_som : std_logic := '0';   -- (esp54)
  signal mp_rate, mp_idx : std_logic_vector(15 downto 0) := (others => '0');
  signal cad_t : unsigned(22 downto 0) := (others => '0');   -- (esp44b) o reset dura pelo menos ~150 ms
  signal irqn_s : std_logic;
  signal dbg_ss, dbg_hid, dbg_sys : std_logic := '0';   -- diagnostico do teclado USB (LEDs)
  signal ss_d : std_logic_vector(1 downto 0) := "11";
  signal irq_t : unsigned(24 downto 0) := (others => '0');
  signal mcu_d, mcu_sys_q, mcu_hid_q : std_logic_vector(7 downto 0);
  signal clk54, clk54p, lock54, sd_pronta : std_logic;
  signal sd_teste, sd_teste2 : std_logic := '0';
  signal nmi_core : std_logic;
  signal dq_i, dq_o : std_logic_vector(31 downto 0);
  signal dq_oe, dq_oen : std_logic;
  signal border_c, modo_c, hcor_c : std_logic_vector(2 downto 0);
  signal s1, s2 : std_logic_vector(11 downto 0) := (others => '0');
  component ram_dp
    generic (AW : integer := 14);
    port (clk : in std_logic;
          a : in std_logic_vector(AW-1 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0);
          clkb : in std_logic;
          b : in std_logic_vector(AW-1 downto 0); bq : out std_logic_vector(7 downto 0));
  end component;
  -- ULAplus: paleta de 64 cores (o core escreve, o video le')
  signal pal_wa, pal_ra : std_logic_vector(5 downto 0);
  signal pal_we, ulap_c, ulap_v : std_logic := '0';
  signal pal_wd, pal_wq, pal_rq : std_logic_vector(7 downto 0);
  signal ecra7_c, ecra7_v : std_logic := '0';
  signal ofs_r : unsigned(2 downto 0) := to_unsigned(CAP_OFS, 3);
  signal rdeb_d : std_logic := '0';
  signal auto_ini : std_logic := '0';
  signal auto_t : integer range 0 to 216000000 := 0;
  signal ce, ce35 : std_logic := '0';
  signal acc35 : integer range 0 to 8191 := 0;
  signal acc : integer range 0 to 8191 := 0;
  signal vel_r : integer range 1 to 8 := VEL;          -- Timmy: muda com a escolha 15 dos botoes
  signal arr_turbo, turbo_c : std_logic := '0';
  signal pisca_t : unsigned(24 downto 0) := (others => '0');
  signal halt_n, cpu_rst_n : std_logic := '0';
  signal arranque : unsigned(26 downto 0) := (others => '0');   -- ate' 108 000 000 = 2 s a 54 MHz
  signal rs, ns : std_logic_vector(2 downto 0) := (others => '0');   -- sincronizacao dos botoes
  signal rdeb, ndeb : std_logic := '0';
  signal mb_cnt : unsigned(27 downto 0) := (others => '0');          -- tempo com o botao A carregado
  signal mb_rn  : std_logic := '1';                              -- botoes sem ressaltos
  signal tdeb : unsigned(19 downto 0) := (others => '0');            -- ~39 ms a 27 MHz
  signal ndeb_d : std_logic := '0';
  signal nmi_n : std_logic := '1';
  signal nmi_t : integer range 0 to 255 := 0;
  constant Z6 : std_logic_vector(5 downto 0) := (others => '0');
  constant Z4 : std_logic_vector(3 downto 0) := (others => '0');
  function sel(c : boolean; a, b : integer) return integer is
  begin
    if c then return a; else return b; end if;
  end function;
  -- escolhe pelo modo: 480p, 720p, 576p
  function to_std(x : boolean) return std_logic is begin if x then return '1'; else return '0'; end if; end function;
  function m(a480, a720, a576 : integer) return integer is
  begin
    if MODO480 then return a480; elsif MODO720 then return a720; else return a576; end if;
  end function;
  -- ponte do ESP32 -> core (escritas na RAM de video / SDRAM)
  signal esp_req, esp_vram, esp_ack : std_logic;
  signal esp_wreq, esp_wack : std_logic;
  signal esp_wa : std_logic_vector(22 downto 0);
  signal esp_wd : std_logic_vector(31 downto 0);
  signal esp_wbe : std_logic_vector(3 downto 0);
  signal esp_a : std_logic_vector(22 downto 0);
  signal esp_d : std_logic_vector(7 downto 0);
  -- camada do ESP: imagem de 640x480 x 2 bits na SDRAM, misturada a' saida do HDMI
  signal rv, gv, bv : std_logic_vector(7 downto 0);
  signal dev, hsv, vsv : std_logic;
  signal ovl_pede_l, ovl_pede_w, c_lig, c_sel, c_selq, c_jan, lb_we : std_logic := '0';
  signal c_2x : std_logic := '0';
  signal atalho : std_logic_vector(20 downto 0) := (others => '0');
  signal at_d : std_logic_vector(1 downto 0) := "00";
  signal vel_cod : std_logic_vector(3 downto 0);
  -- cassete (2026-10-24)
  signal cs_wr, cs_limpa, cs_ativa, cs_ear, ce_t, dv_lento : std_logic := '0';
  signal ay_vis : std_logic_vector(191 downto 0) := (others => '0');
  signal cs_d : std_logic_vector(15 downto 0);
  signal cs_livres : std_logic_vector(7 downto 0);
  signal k_gspara, k_ay3 : std_logic := '0';
  signal alt_k : std_logic := '0';
  signal maq_st : std_logic_vector(15 downto 0) := (others => '0');
  signal jcru : std_logic_vector(31 downto 0) := (others => '0');
  signal c_meio : std_logic_vector(2 downto 0) := "000";
  signal c_w16 : std_logic := '0';
  signal c_wsep, c_wsepq : std_logic := '0';
  signal c_widx, c_widxq : std_logic_vector(1 downto 0) := "00";
  signal ovl_lin_l : std_logic_vector(9 downto 0);
  signal ovl_lin_w : std_logic_vector(7 downto 0);
  signal c_wx : std_logic_vector(10 downto 0);
  signal c_wy : std_logic_vector(9 downto 0);
  signal c_cor1, c_cor2, c_cor3 : std_logic_vector(23 downto 0);
  signal lb_a, lb_ra : std_logic_vector(8 downto 0) := (others => '0');
  signal lb_d, lb_q : std_logic_vector(31 downto 0) := (others => '0');
  -- (v3) cartao SD partilhado, leitura da RAM de video, teclas / reset / NMI do ESP
  signal esp_rreq, esp_rv, sd_meu, esp_cs_n, esp_sclk, esp_mosi, k_rst, k_nmi : std_logic := '0';
  signal esp_rd : std_logic_vector(7 downto 0);
  signal mb_wr, mb_rd, mb_sel : std_logic := '0';
  signal mb_d, mb_q : std_logic_vector(7 downto 0) := x"FF";
  signal ua_wr, ua_rd, ua_dat : std_logic := '0';
  signal ua_q : std_logic_vector(7 downto 0) := x"FF";
  signal k_mat : std_logic_vector(39 downto 0) := (others => '0');
  signal c_sd_cs_n, c_sd_clk, c_sd_mosi, c_sd_miso : std_logic;
begin
  -- 480p: 27 x 14 / 3 = 126 MHz (VCO 504).
  -- 576p: 27 x 5 / 1 = 135 MHz (VCO 540).  720p: 27 x 55 / 4 = 371,25 MHz (VCO 742,5).
  -- (valores confirmados com o gowin_pll do apicula)
  -- 2.o PLL: 54 MHz para o core e a SDRAM (27 x 2, VCO 864; gowin_pll do apicula)
  pll54: rPLL
    generic map (FCLKIN => "27", IDIV_SEL => 0, FBDIV_SEL => 1, ODIV_SEL => 16, DEVICE => "GW2AR-18C",
                 PSDA_SEL => "1000", DUTYDA_SEL => "1000")   -- CLKOUTP: 54 MHz a 180 graus (SDRAM)
    port map (CLKOUT => clk54, LOCK => lock54, CLKOUTP => clk54p, CLKOUTD => open, CLKOUTD3 => open,
              RESET => '0', RESET_P => '0', CLKIN => I_clk, CLKFB => '0',
              FBDSEL => Z6, IDSEL => Z6, ODSEL => Z6, PSDA => Z4, DUTYDA => Z4, FDLY => Z4);

  pll: rPLL
    generic map (FCLKIN => "27",
                 IDIV_SEL  => m(2, 3, 0),
                 FBDIV_SEL => m(13, 54, 4),
                 ODIV_SEL  => m(4, 2, 4),
                 DEVICE => "GW2AR-18C")
    port map (CLKOUT => sclk, LOCK => lock, CLKOUTP => open, CLKOUTD => open, CLKOUTD3 => open,
              RESET => '0', RESET_P => '0', CLKIN => I_clk, CLKFB => '0',
              FBDSEL => Z6, IDSEL => Z6, ODSEL => Z6, PSDA => Z4, DUTYDA => Z4, FDLY => Z4);

  div: CLKDIV
    generic map (DIV_MODE => "5", GSREN => "false")
    port map (CLKOUT => pclk, HCLKIN => sclk, RESETN => '1', CALIB => '0');

  -- reset dos serializadores: so' umas centenas de ciclos depois do arranque
  -- (nao depende do LOCK do PLL)
  process(pclk)
  begin
    if rising_edge(pclk) then
      if arr /= 255 then arr <= arr + 1; rst <= '1'; else rst <= '0'; end if;
    end if;
  end process;

  vid: entity work.video_timex
    generic map (
      H_ACT => m(640, 1280, 720), H_FP => m(16, 440, 12),
      H_SY  => m(96, 40, 64),     H_TOT => m(800, 1980, 864),
      V_ACT => m(480, 720, 576),  V_FP => m(10, 5, 5), V_SY => m(2, 5, 5),
      V_TOT => m(525, 750, 625),
      ESC   => m(2, 3, 2),
      SYNC_POS => MODO720 and not MODO480)
    port map (clk => pclk, border => border, r => rv, g => gv, b => bv, de => dev, hs => hsv, vs => vsv,
              modo => modo, hcor => hcor, va => va, vq => vq, sinc => fsinc and to_std(PENTA50),
              ulap => ulap_v, pal_a => pal_ra, pal_q => pal_rq, m16c => m16c_v, va2 => va2, vq2 => vq2,
              m2068 => maq_st(9));   -- (62) bit 9 = modo TC2068 (quase estatico; passa de relogio sem mal)
  -- paleta da ULAplus em LUTs (2026-10-22: o bloco de BSRAM ficou para o buffer de linhas da camada do ESP)
  pal: entity work.ram_lut generic map (AW => 6)
    port map (clk => clk54, a => pal_wa, we => pal_we, d => pal_wd, q => pal_wq,
              clkb => pclk, b => pal_ra, bq => pal_rq);
  cam: entity work.camada_esp
    generic map (H_ACT => m(640, 1280, 720), V_ACT => m(480, 720, 576), SYNC_POS => MODO720 and not MODO480)
    port map (clk => pclk, ligada => c_lig, janela => c_jan, dobro => c_2x, meio => c_meio, w16 => c_w16, wx => c_wx, wy => c_wy, sel_in => c_sel, sel_out => c_selq, wsep_in => c_wsep, widx_in => c_widx, wsep_out => c_wsepq, widx_out => c_widxq, cor1 => c_cor1, cor2 => c_cor2, cor3 => c_cor3,
              ri => rv, gi => gv, bi => bv, dei => dev, hsi => hsv, vsi => vsv,
              ro => r, go => g, bo => b, deo => de, hso => hs, vso => vs,
              pede_l => ovl_pede_l, lin_l => ovl_lin_l, pede_w => ovl_pede_w, lin_w => ovl_lin_w, lb_a => lb_ra, lb_q => lb_q);
  linhas: entity work.ram_linha generic map (AW => 9)
    port map (clka => clk54, wea => lb_we, aa => lb_a, da => lb_d, clkb => pclk, ab => lb_ra, qb => lb_q);

  -- O core (Z80, memoria, portas, SDRAM) corre a 54 MHz (2.o PLL: 27 x 2), em qualquer
  -- modo HDMI. O video le a RAM pelo outro porto, no relogio do ponto.
  -- Relogio do Z80: 3,5 MHz exactos = 54 x 7/108 (1 ciclo de ce por T-state).
  -- Turbo (VEL): o Z80 corre a 3,5 x VEL MHz; o quadro e a INT ficam sempre a 3,5 MHz (ce35).
  process(clk54)
    -- 3,5 MHz certos. Com PENTA50: Pentagon a 3,584 MHz = 54 x 224/3375 -> quadro de
    -- 71680 T = 20 ms, preso ao HDMI de 50 Hz e em fase (video_timex "sinc").
    -- (O salto que se via no Scroller era da TV.)
    constant N1  : integer := sel(PENTA and PENTA50, 224, 7);
    variable NUM : integer range 0 to 1023;
    constant DEN : integer := sel(PENTA and PENTA50, 3375, 108);
  begin
    if rising_edge(clk54) then
      -- (2026-10-24) a 27 MHz, com a DivMMC mapeada (esxDOS, NAV, cargas do cartao) vai a 14 MHz: o SPI e as
      -- traps da DivMMC foram feitos para 3,5 MHz; o programa, depois de arrancar, corre a 27
      if k_turbo = '1' or (vel_r = 8 and dv_lento = '1') then NUM := N1 * 4; elsif vel_r = 8 then NUM := 0; else NUM := N1 * vel_r; end if;
      if arr_turbo = '1' then
        if vel_r = 8 then vel_r <= 1; else vel_r <= vel_r * 2; end if;
      end if;
      -- Win+'+' / Win+'-' (teclado USB): 3,5 -> 7 -> 14 MHz e de volta
      -- (esp56) a velocidade do Z80 passou para o F10 (sobe) e o F9 (desce); o Win + / Win - e' o volume do ESP
      at_d <= atalho(19) & atalho(20);
      if atalho(20) = '1' and at_d(0) = '0' and vel_r /= 8 then vel_r <= vel_r * 2; end if;
      if atalho(19) = '1' and at_d(1) = '0' and vel_r /= 1 then vel_r <= vel_r / 2; end if;
      -- (2026-10-24) 8 x = 27 MHz: um ce de 2 em 2 ciclos certos (nunca dois seguidos: o .sdc da' 2 ciclos ao Z80)
      if vel_r = 8 and k_turbo = '0' and dv_lento = '0' then ce <= not ce;
      elsif acc + NUM >= DEN and ce = '0' then acc <= acc + NUM - DEN; ce <= '1';   -- nunca dois ce seguidos
      else acc <= acc + NUM; ce <= '0'; end if;
      if acc35 + N1 >= DEN then acc35 <= acc35 + N1 - DEN; ce35 <= '1';
      else acc35 <= acc35 + N1; ce35 <= '0'; end if;
    end if;
  end process;

  -- botoes: sincronizar e tirar ressaltos (le-se o nivel a cada ~14 ms)
  process(clk54)
  begin
    if rising_edge(clk54) then
      rs <= rs(1 downto 0) & I_reset;
      ns <= ns(1 downto 0) & I_nmi;
      tdeb <= tdeb + 1;
      if tdeb = 0 then rdeb <= rs(2); ndeb <= ns(2); end if;
    end if;
  end process;

  -- reset do Z80: ~2 s depois de ligar e com a SDRAM pronta (o cartao SD tambem tem de acordar)
  process(clk54)
  begin
    if rising_edge(clk54) then
      if usb_cad = '1' then cad_t <= to_unsigned(8000000, 23); elsif cad_t /= 0 then cad_t <= cad_t - 1; end if;
      if sd_pronta = '0' then arranque <= (others => '0'); cpu_rst_n <= '0';
      elsif arranque /= 108000000 then arranque <= arranque + 1; cpu_rst_n <= '0';
      elsif arr_segura = '1' then cpu_rst_n <= '0';   -- menu de arranque (core Timmy)
      elsif k_rst = '1' then cpu_rst_n <= '0';        -- reset pedido pelo ESP (registo 65 bit 0)
      elsif usb_cad = '1' or cad_t /= 0 then cpu_rst_n <= '0';   -- Ctrl+Alt+Del
      else cpu_rst_n <= '1'; end if;
    end if;
  end process;

  -- NMI: um impulso de ~200 T-states por cada vez que se carrega no botao
  process(clk54)
  begin
    if rising_edge(clk54) then
      ndeb_d <= ndeb;
      if ndeb = '1' and ndeb_d = '0' then nmi_t <= 255; nmi_n <= '0';
      elsif nmi_t /= 0 then
        if ce = '1' then nmi_t <= nmi_t - 1; end if;
      else nmi_n <= '1'; end if;
    end if;
  end process;

  timex_g: if not PENTA and not TIMMY generate
    core: entity work.core_timex
      generic map (M2068 => M2068, DIV => DIVMMC, DIV_BRAM => DIV_BRAM, ALTA_BRAM => ALTA_BRAM)
      port map (clk => clk54, vclk => pclk, ce => ce, ce35 => ce35, reset_n => cpu_rst_n, nmi_n => nmi_core, mat => mat,
                border => border_c, modo => modo_c, hcor => hcor_c, vid_a => va, vid_q => vq, halt_n => halt_n,
                pronta => sd_pronta, sd_teste => sd_teste, sd_teste2 => sd_teste2,
                sd_clk => open, sd_cke => O_sdram_cke, sd_cs_n => O_sdram_cs_n,
                sd_ras_n => O_sdram_ras_n, sd_cas_n => O_sdram_cas_n, sd_we_n => O_sdram_wen_n,
                sd_ba => O_sdram_ba, sd_addr => O_sdram_addr, sd_dqm => O_sdram_dqm,
                sd_dq_i => dq_i, sd_dq_o => dq_o, sd_dq_oe => dq_oe,
                mmc_cs_n => O_sd_cs_n, mmc_sclk => O_sd_clk, mmc_mosi => O_sd_mosi, mmc_miso => I_sd_miso,
                aud_l => aud_l, aud_r => aud_r,
                pal_a => pal_wa, pal_we => pal_we, pal_d => pal_wd, pal_q => pal_wq, ulap => ulap_c);
    ecra7_c <= '0'; fsinc <= '0';
  end generate;

  -- Timmy: SCLD v13 + DivTIESUS v13 (TC2048, 128K, Pentagon 128/256 pelas portas, como o clone)
  timmy_g: if TIMMY generate
    core: entity work.core_timmy generic map (COM_SID => SID)
      port map (clk => clk54, clk_div => I_clk, vclk => pclk, ce => ce, ce35 => ce35, reset_n => cpu_rst_n,
                nmi_n => nmi_core, mat => mat,
                border => border_c, modo => modo_c, hcor => hcor_c, ecra7 => ecra7_c,
                vid_a => ecra7_v & va, vid_q => vq, vid_a2 => va2, vid_q2 => vq2, m16c => m16c_c, turbo => turbo_c, ear_in => cs_ear, mp_on => '0', mp_rate => mp_rate, mp_idx => mp_idx, mp_l => open, mp_r => open, ce_t => ce_t, dv_lento => dv_lento, ay_vis => ay_vis, rato_x => rato_x, rato_y => rato_y, rato_b => rato_b, joy => joy_k, pede_rnmi => pede_rnmi, halt_n => halt_n,
                pronta => sd_pronta, sd_teste => sd_teste, sd_teste2 => sd_teste2,
                sd_clk => open, sd_cke => O_sdram_cke, sd_cs_n => O_sdram_cs_n,
                sd_ras_n => O_sdram_ras_n, sd_cas_n => O_sdram_cas_n, sd_we_n => O_sdram_wen_n,
                sd_ba => O_sdram_ba, sd_addr => O_sdram_addr, sd_dqm => O_sdram_dqm,
                sd_dq_i => dq_i, sd_dq_o => dq_o, sd_dq_oe => dq_oe,
                mmc_cs_n => c_sd_cs_n, mmc_sclk => c_sd_clk, mmc_mosi => c_sd_mosi, mmc_miso => c_sd_miso,
                aud_l => aud_l, aud_r => aud_r,
                pal_a => pal_wa, pal_we => pal_we, pal_d => pal_wd, pal_q => pal_wq, ulap => ulap_c,
                esp_req => esp_req, esp_vram => esp_vram, esp_a => esp_a, esp_d => esp_d, esp_ack => esp_ack,
                esp_wreq => esp_wreq, esp_wa => esp_wa, esp_wd => esp_wd, esp_wbe => esp_wbe, esp_wack => esp_wack,
                esp_rreq => esp_rreq, esp_rv => esp_rv, esp_rd => esp_rd,
                mb_wr => mb_wr, mb_rd => mb_rd, mb_sel => mb_sel, mb_d => mb_d, mb_q => mb_q, ua_wr => ua_wr, ua_rd => ua_rd, ua_dat => ua_dat, ua_q => ua_q, maq_st => maq_st, gs_parar => k_gspara, ay3_lig => k_ay3,
                ovl_pede_l => ovl_pede_l, ovl_lin_l => ovl_lin_l, ovl_pede_w => ovl_pede_w, ovl_lin_w => ovl_lin_w, ovl_sel => c_selq, ovl_w16 => c_w16, ovl_wsep => c_wsepq, ovl_widx => c_widxq, lb_we => lb_we, lb_a => lb_a, lb_d => lb_d);
    fsinc <= '0';
    -- o cartao SD: do DivMMC do Z80 ou do ESP (registo 50 bit 0); com o ESP, o Z80 ve' o MISO a 1
    O_sd_cs_n <= esp_cs_n when sd_meu = '1' else c_sd_cs_n;
    O_sd_clk  <= esp_sclk when sd_meu = '1' else c_sd_clk;
    O_sd_mosi <= esp_mosi when sd_meu = '1' else c_sd_mosi;
    c_sd_miso <= '1' when sd_meu = '1' else I_sd_miso;
    arr: entity work.teclas_arranque port map (clk => clk54, pronta => sd_pronta, rst_n => cpu_rst_n,
        bot_a => rdeb, bot_b => ndeb, segura => arr_segura, escolha => arr_esc, led_pisca => arr_pisca, nmi_rst => arr_nmi, turbo_t => arr_turbo, rnmi_t => pede_rnmi, mat => mat_arr);
  end generate;
  sem_arr_g: if not TIMMY generate
    mat_arr <= (others => '0'); arr_segura <= '0'; arr_esc <= "0000"; arr_pisca <= '0'; arr_nmi <= '0';
  end generate;

  -- Pentagon 128/512/1024: o video le o banco 5 ou o 7 (7FFD bit 3); sem modos Timex
  penta_g: if PENTA generate
    core: entity work.core_penta
      generic map (DIV => DIVMMC)
      port map (clk => clk54, vclk => pclk, ce => ce, ce35 => ce35, reset_n => cpu_rst_n, nmi_n => nmi_core, mat => mat,
                border => border_c, ecra7 => ecra7_c, vid_a => ecra7_v & va, vid_q => vq, ofs => std_logic_vector(ofs_r), fsinc => fsinc, halt_n => halt_n,
                pronta => sd_pronta,
                sd_clk => open, sd_cke => O_sdram_cke, sd_cs_n => O_sdram_cs_n,
                sd_ras_n => O_sdram_ras_n, sd_cas_n => O_sdram_cas_n, sd_we_n => O_sdram_wen_n,
                sd_ba => O_sdram_ba, sd_addr => O_sdram_addr, sd_dqm => O_sdram_dqm,
                sd_dq_i => dq_i, sd_dq_o => dq_o, sd_dq_oe => dq_oe,
                mmc_cs_n => O_sd_cs_n, mmc_sclk => O_sd_clk, mmc_mosi => O_sd_mosi, mmc_miso => I_sd_miso,
                aud_l => aud_l, aud_r => aud_r,
                pal_a => pal_wa, pal_we => pal_we, pal_d => pal_wd, pal_q => pal_wq, ulap => ulap_c);
    modo_c <= "010"; hcor_c <= "000";     -- o ecra capturado tem um atributo por linha (hi-colour)
  end generate;

  -- relogio da SDRAM: saida do PLL desfasada 180 graus (caminho dedicado, atraso conhecido)
  O_sdram_clk <= clk54p;

  -- dados da SDRAM: um IOBUF por bit (OEN a 0 = sai)
  dq_g: for i in 0 to 31 generate
    b: IOBUF port map (O => dq_i(i), IO => IO_sdram_dq(i), I => dq_o(i), OEN => dq_oen);
  end generate;
  dq_oen <= not dq_oe;

  -- botao A: escreve o programa de teste; botao B: BREAK
  -- com o DivMMC o botao B e' o NMI (o navegador do esxDOS) e o A escreve .ls
  -- Timmy: o B so' e' o NMI com a escolha 0 (LEDs 4-6 apagados); as outras escrevem um comando
  nmi_core <= not ((ndeb and not (arr_esc(3) or arr_esc(2) or arr_esc(1) or arr_esc(0))) or arr_nmi or k_nmi) when DIVMMC else '1';
  O_sd_dat1 <= '1'; O_sd_dat2 <= '1';
  -- no Timmy as teclas automaticas nunca arrancam (inicio/brk presos a 0): nem as sintetiza
  auto_g: if not TIMMY generate
    auto: entity work.teclas_auto generic map (M128 => PENTA, LS => DIVMMC, BR => BROWSE, PK => PEEKT, TR => PENTA and DIVMMC) port map (clk => clk54, inicio => rdeb and cpu_rst_n and not to_std(TIMMY), brk => ndeb and not to_std(TIMMY), mat => mat_auto);
  end generate;
  sem_auto_g: if TIMMY generate mat_auto <= (others => '0'); end generate;

  -- teclado USB pelo FPGA-Companion (BL616)
  mcu: entity work.mcu_spi port map (clk => clk54, ss => I_spi_csn, sclk => I_spi_sclk, mosi => I_spi_mosi,
      miso => O_spi_miso, sys_stb => mcu_sys_stb, hid_stb => mcu_hid_stb, inicio => mcu_ini, dado => mcu_d,
      sys_q => mcu_sys_q, hid_q => mcu_hid_q);
  sysc: entity work.sysctrl port map (clk => clk54, reset => '0', stb => mcu_sys_stb, inicio => mcu_ini,
      d => mcu_d, q => mcu_sys_q, botoes => ndeb & rdeb, int_n => irqn_s);
  -- Se a interrupcao estiver pendente e o BL616 nao falar durante ~0,6 s, solta-a
  -- ~1 ms e volta a puxa'-la: da' uma descida nova (caso o BL616 so' veja flancos,
  -- por exemplo se arrancou antes de a FPGA estar configurada).
  process(clk54)
  begin
    if rising_edge(clk54) then
      if irqn_s = '1' or ss_d(1) = '0' then
        irq_t <= (others => '0');
      else
        irq_t <= irq_t + 1;
      end if;
    end if;
  end process;
  O_spi_irqn <= '1' when irqn_s = '1' or irq_t(24 downto 16) = "111111111" else '0';
  hidk: entity work.hid_teclado port map (clk => clk54, reset => '0', stb => mcu_hid_stb, inicio => mcu_ini,
      d => mcu_d, q => mcu_hid_q, mat => mat_usb, f11 => usb_f11, cad => usb_cad,
      rato_x => rato_x, rato_y => rato_y, rato_b => rato_b, joy => joy_usb, atalho => atalho, alt => alt_k, jcru => jcru);
  joy_k <= joy_usb when k_cap = '0' else x"00";   -- menu do ESP aberto: o joystick so' para o ESP
  -- k_mat: teclas carregadas pelo ESP; com k_cap = 1 o teclado so' vai para o ESP (menu do ESP aberto)
  mat_fis <= mat_auto or mat_usb or mat_arr;
  mat <= (mat_fis or k_mat) when k_cap = '0' else k_mat;
  -- diagnostico: LED 4 = o BL616 ja' falou (CSN a 0); LED 5 = chegou um byte ao alvo SYS;
  -- LED 6 = chegou um byte ao alvo HID; LED 3 = IRQ pendente; LED 2 = tecla USB carregada
  process(clk54)
  begin
    if rising_edge(clk54) then
      ss_d <= ss_d(0) & I_spi_csn;
      if ss_d(1) = '0' then dbg_ss <= '1'; end if;
      if mcu_sys_stb = '1' then dbg_sys <= '1'; end if;
      if mcu_hid_stb = '1' then dbg_hid <= '1'; end if;
    end if;
  end process;

  -- (contador sem uso)
  process(clk54)
  begin
    if rising_edge(clk54) then
      auto_ini <= '0';
      if cpu_rst_n = '0' then auto_t <= 0;
      elsif auto_t /= 216000000 then
        auto_t <= auto_t + 1;
        null;
      end if;
    end if;
  end process;

  -- teste da captura: o botao A carrega o teste.trd e, a cada vez, soma 1 ao CAP_OFS
  -- (dentro do demo as teclas que ele escreve nao fazem nada)
  process(clk54)
  begin
    if rising_edge(clk54) then
      rdeb_d <= rdeb;
      if CAP_TESTE and rdeb = '1' and rdeb_d = '0' then ofs_r <= ofs_r + 1; end if;
    end if;
  end process;
  -- menu de arranque: LED3 pisca, LED4/LED5 = maquina escolhida. Depois: LED5 = o teclado USB ja' falou
  O_led_ofs <= not std_logic_vector(ofs_r) when CAP_TESTE else
               not (arr_esc(3 downto 1) or atalho(2 downto 0)) when TIMMY else "11" & not dbg_hid;   -- LEDs 4-6: Win+J, Win+S, Win+C

  turbo_c <= '0' when vel_r = 1 and k_turbo = '0' else '1';
  vel_cod <= "0100" when k_turbo = '1' else std_logic_vector(to_unsigned(vel_r, 4));

  -- borda e modo passam para o relogio do ponto (2 registos; mudam raramente)
  process(pclk)
  begin
    if rising_edge(pclk) then
      s1 <= m16c_c & ulap_c & ecra7_c & border_c & modo_c & hcor_c;
      s2 <= s1;
      m16c_v <= s2(11);
      ulap_v <= s2(10);
      ecra7_v <= s2(9);
      border <= s2(8 downto 6); modo <= s2(5 downto 3); hcor <= s2(2 downto 0);
    end if;
  end process;

  -- canal 0 leva C0 = HSYNC, C1 = VSYNC (o video_spec ja' da' a polaridade do fio)
  ctl <= vs & hs;

  -- som: media por amostra, corta-continua, 48 kHz (som.vhd)
  -- AUD_TESTE = 2: em vez da maquina, uma quadrada de 440 Hz (0 / 255), pelo mesmo caminho
  process(clk54)
  begin
    if rising_edge(clk54) then
      if tom_c = 61363 then tom_c <= 0; tom <= not tom; else tom_c <= tom_c + 1; end if;
    end if;
  end process;
  -- 14 bits: o Timmy da' 14 bits (com o GS); os outros cores 10 bits (x 16)
  aud_in_l <= ("000000" & x"FF") when AUD_TESTE = 2 and tom = '1' else (others => '0') when AUD_TESTE = 2 else
              aud_l(13 downto 0) when TIMMY else aud_l(9 downto 0) & "0000";
  aud_in_r <= aud_in_l when AUD_TESTE = 2 else aud_r(13 downto 0) when TIMMY else aud_r(9 downto 0) & "0000";
  -- (esp49) a cada amostra nova do som.vhd: soma a do ESP (metade ou toda) com saturacao; o "tog" para o HDMI
  -- muda um ciclo depois (os dados ja' estao estaveis quando o HDMI os apanha)
  process(clk54)
    variable xl, xr : signed(17 downto 0);
  begin
    if rising_edge(clk54) then
      aud_tg_d <= aud_tog;
      if aud_tog /= aud_tg_d then
        if mp_som = '1' and mp_alto = '1' then
          xl := resize(signed(aud_tl), 18) + resize(signed(mp_l), 18);
          xr := resize(signed(aud_tr), 18) + resize(signed(mp_r), 18);
        elsif mp_som = '1' then
          xl := resize(signed(aud_tl), 18) + resize(shift_right(signed(mp_l), 1), 18);
          xr := resize(signed(aud_tr), 18) + resize(shift_right(signed(mp_r), 1), 18);
        else
          xl := resize(signed(aud_tl), 18); xr := resize(signed(aud_tr), 18);
        end if;
        if xl > 32767 then xl := to_signed(32767, 18); elsif xl < -32768 then xl := to_signed(-32768, 18); end if;
        if xr > 32767 then xr := to_signed(32767, 18); elsif xr < -32768 then xr := to_signed(-32768, 18); end if;
        aud_hl <= std_logic_vector(xl(15 downto 0)); aud_hr <= std_logic_vector(xr(15 downto 0));
      end if;
      aud_tog2 <= aud_tg_d;
    end if;
  end process;
  -- (esp54) o som do ESP chega por I2S (antes: o anel na SDRAM, lido pelo core). O registo 2A continua a
  -- ligar (bit 0) e a escolher o volume (bit 1); sem BCLK nao se soma nada
  i2s: entity work.i2s_rx port map (clk => clk54, bck => I_i2s_bck, ws => I_i2s_ws, d => I_i2s_d,
                                    l => mp_l, r => mp_r, ativo => i2s_on, n_mas => open);
  mp_som <= mp_on and i2s_on;
  snd: entity work.som port map (clk => clk54, in_l => aud_in_l, in_r => aud_in_r,
                                 out_l => aud_tl, out_r => aud_tr, tog => aud_tog);

  -- HDMI com som (ilhas de dados: AVI, Audio InfoFrame, ACR e amostras a 48 kHz)
  tx: entity work.hdmi_tx
    generic map (FREQ => m(25200000, 74250000, 27000000), VIC => m(1, 19, 17),
                 LARGO => MODO720 and not MODO480, SYNC_POS => MODO720 and not MODO480)
    port map (clk => pclk, r => r, g => g, b => b, de => de, hs => hs, vs => vs,
              aud_l => aud_hl, aud_r => aud_hr, aud_tog => aud_tog2, q0 => sym(0), q1 => sym(1), q2 => sym(2));
  sym(3) <= "0000011111";                      -- canal do relogio

  ser_g: for i in 0 to 3 generate
    s: OSER10
      generic map (GSREN => "false", LSREN => "true")
      port map (Q => ser(i),
                D0 => sym(i)(0), D1 => sym(i)(1), D2 => sym(i)(2), D3 => sym(i)(3), D4 => sym(i)(4),
                D5 => sym(i)(5), D6 => sym(i)(6), D7 => sym(i)(7), D8 => sym(i)(8), D9 => sym(i)(9),
                FCLK => sclk, PCLK => pclk, RESET => rst);
    o: TLVDS_OBUF port map (I => ser(i), O => pos(i), OB => neg(i));
  end generate;

  O_tmds_data_p <= pos(2 downto 0);
  O_tmds_data_n <= neg(2 downto 0);
  O_tmds_clk_p  <= pos(3);
  O_tmds_clk_n  <= neg(3);

  -- LED 0 pisca (~1 Hz a 27 MHz); LED 1 aceso com o PLL travado
  process(pclk)
  begin
    if rising_edge(pclk) then cnt <= cnt + 1; end if;
  end process;
  -- LED 1: SDRAM ok; no Timmy pisca com o turbo (devagar = 7 MHz, depressa = 14 MHz)
  process(clk54)
  begin
    if rising_edge(clk54) then pisca_t <= pisca_t + 1; end if;
  end process;
  O_led(0) <= not (sd_teste and pisca_t(24)) when TIMMY and vel_r = 2 else
              not (sd_teste and pisca_t(22)) when TIMMY and vel_r = 4 else
              not (sd_teste and pisca_t(20)) when TIMMY and vel_r = 8 else
              not sd_teste;
  -- Troca de core (multiboot): botao A carregado 3 s -> RECONFIG_N a 0. A FPGA carrega o
  -- bitstream do endereco gravado neste (multiboot_spi_flash_address, 0x100000 = Next).
  process(clk54)
  begin
    if rising_edge(clk54) then
      if usb_f11 = '1' then
        mb_rn <= '0';                                -- Ctrl+Alt+F11: troca logo
      elsif rdeb = '1' then
        if mb_cnt = to_unsigned(162000000, 28) then mb_rn <= '0'; else mb_cnt <= mb_cnt + 1; end if;
      else
        mb_cnt <= (others => '0');
      end if;
    end if;
  end process;
  O_reconfig_n <= '0' when mb_rn = '0' else 'Z';   -- dreno aberto (o TP1 tem pull-up de 4,7k)

  O_led3   <= not (arr_esc(0) or alt_k) when TIMMY else not sd_teste2;   -- Timmy: LED 3 tambem = uma tecla Windows carregada  -- Timmy: LEDs dos pinos 17-20 = escolha bits 0-3           -- LED 3 aceso = 4 bytes na mesma palavra (DQM) certos
  O_led(1) <= O_sd_cs_n;               -- aceso enquanto o cartao SD esta' seleccionado
  -- 2026-10-22: ponte para o ESP32-S3 (por agora so' registos de teste)
  esp: entity work.ponte_esp port map (clk => clk54, esp_clk => I_esp_clk, esp_cs => I_esp_cs, esp_dir => I_esp_dir,
                                       esp_d => IO_esp_d, esp_irq => O_esp_irq,
                                       p_req => esp_req, p_vram => esp_vram, p_a => esp_a, p_d => esp_d, p_ack => esp_ack,
                                       p_wreq => esp_wreq, p_wa => esp_wa, p_wd => esp_wd, p_wbe => esp_wbe, p_wack => esp_wack,
                                       c_lig => c_lig, c_sel => c_sel, c_jan => c_jan, c_2x => c_2x, c_meio => c_meio, c_w16 => c_w16, c_wsep => c_wsep, c_widx => c_widx, c_wmostra => c_widxq, mp_on => mp_on, mp_alto => mp_alto, mp_rate => mp_rate, mp_idx => mp_idx, c_wx => c_wx, c_wy => c_wy, c_ativa => c_selq, c_cor1 => c_cor1, c_cor2 => c_cor2, c_cor3 => c_cor3,
                                       p_rreq => esp_rreq, p_rv => esp_rv, p_rd => esp_rd,
                                       sd_meu => sd_meu, sd_cs_n => esp_cs_n, sd_sclk => esp_sclk, sd_mosi => esp_mosi, sd_miso => I_sd_miso,
                                       k_mat => k_mat, k_rst => k_rst, k_nmi => k_nmi,
                                       z_wr => mb_wr, z_rd => mb_rd, z_sel => mb_sel, z_d => mb_d, z_q => mb_q, u_wr => ua_wr, u_rd => ua_rd, u_dat => ua_dat, u_q => ua_q,
                                       k_in => mat_fis, k_cap => k_cap, k_turbo => k_turbo, k_gspara => k_gspara, k_ay3 => k_ay3, k_vel => vel_cod, cs_wr => cs_wr, cs_d => cs_d, cs_limpa => cs_limpa, cs_livres => cs_livres, cs_ativa => cs_ativa, k_joy => joy_usb, k_atal => atalho, k_ay => ay_vis, k_jcru => jcru, k_maq => maq_st);
  sem_timmy_g: if not TIMMY generate esp_ack <= '0'; esp_wack <= '0'; end generate;
  cas: entity work.cassete port map (clk => clk54, t_ce => ce_t, limpa => cs_limpa, wr => cs_wr, d => cs_d,
                                     livres => cs_livres, ativa => cs_ativa, ear => cs_ear);
end architecture;
