-- core_timextenso.vhd: o Timextenso (clone do TC2048) inteiro na Tang: Z80 + SCLD v13 + DivTIESUS v13.
--   DivTIESUS: os ficheiros Verilog do v13 (divt/*.v), via divtiesus_tang.v. A SRAM de 512K
--     e' a SDRAM a partir de 1 MB (pagina fisica de 8K = sram_hiaddr); a EEPROM e' o rom_esx.
--   SCLD: a parte do scld.vhd v13 que nao e' DRAM, reescrita para o relogio do core:
--     FE (borda, beeper, teclado), FF (modos de ecra, EXROM/DOCK, INT), F4 (blocos de 8K),
--     F3 (configuracao: bit 0 AY 128, 1 preto unico, 2 tempos do 128K, 3 contencao 1/3 /
--     Pentagon 256, 4 E/S, 5 barramento flutuante, 6 sombra, 7 Pentagon),
--     7FFD com F4 = F0 (scld_128: banco, ecra, trinco, bit 6), bancos 5/7 em C000 na RAM de
--     video (BNK), o ecra 7 no video, tempos e INT do 48K / 128K / Pentagon, AY (FFFD/BFFD
--     com o F3 bit 0; F5/F6 so' nos modos Timex).
--   RAM de video: 32K em BSRAM (banco 5 = 4000-7FFF, banco 7). RAM 8000-FFFF: SDRAM.
--   (esp61) As ROMs vem do cartao SD ao ligar: o rom_home e o rom_esx passaram a RAM (ram_home, ram_esx);
--   o ram_esx arranca com o programa de arranque (arranque.hex, nosso) no lugar do esxDOS. A DivTIESUS
--   mapeia-o em 0000-1FFF ao ligar (automap), ele le /SYS/ROMS/TC2048.ROM e /SYS/ROMS/ESXMMC.BIN
--   do cartao para a RAM e escreve-os nas duas memorias pelo registo ZX-UNO A4h (bit 0 = alvo:
--   0 home, 1 esxDOS; bit 7 = fim: sai do modo de carga e reinicia o Z80 e a DivTIESUS).
--   So' no modo de carga (carga = 1, desde a configuracao da FPGA) e' que as escritas do Z80 em
--   0000-3FFF entram nessas memorias.
--   (esp60) HDMI: ECC dos pacotes bit a bit e a camada do ESP com mais um andar (folga no pclk).
--   (esp59) barramento flutuante na FF com o F3 bit 5 (48K, 128K, Pentagon), como o SCLD float6 do CPLD.
--   Ainda nao: contencao, sombra
--   (bit 6: as leituras vem da SRAM da DivTIESUS, que ja' as faz; o video continua igual).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity core_timextenso is
  generic (COM_SID : boolean := true);              -- false: sem os dois SID (xxCF)
  port (
    clk      : in  std_logic;                     -- 54 MHz (core e SDRAM)
    clk_div  : in  std_logic;                     -- 27 MHz: o relogio do CPLD da DivTIESUS
    vclk     : in  std_logic;
    ce       : in  std_logic;
    ce35     : in  std_logic;
    reset_n  : in  std_logic;
    nmi_n    : in  std_logic;                     -- botao do NMI (0 = carregado)
    mat      : in  std_logic_vector(39 downto 0);
    border   : out std_logic_vector(2 downto 0);
    modo     : out std_logic_vector(2 downto 0);
    hcor     : out std_logic_vector(2 downto 0);
    ecra7    : out std_logic;                     -- o video mostra o banco 7
    vid_a    : in  std_logic_vector(14 downto 0); -- bit 14 = banco 7
    vid_q    : out std_logic_vector(7 downto 0);
    vid_a2   : in  std_logic_vector(13 downto 0) := (others => '0');  -- modo 16C: bancos 4/6 (12K)
    vid_q2   : out std_logic_vector(7 downto 0);
    m16c     : out std_logic;                     -- modo 16C do Pentagon (EFF7 bit 0)
    turbo    : in  std_logic := '0';               -- 1 = Z80 a 7/14/27 MHz: espera (WAIT) pela SDRAM
    sd_esp   : in  std_logic := '0';               -- (63) 1 = o cartao e' do ESP: um IN/OUT a E7h/EBh espera (WAIT)
    ear_in   : in  std_logic := '0';               -- (2026-10-24) cassete do ESP: EAR (porta FE bit 6 e som)
    ce_t     : out std_logic;                      -- um T do Z80 sem espera (relogio da cassete)
    dv_lento : out std_logic;
    -- (esp46) som do ESP (MP3): amostras de 32 bits (esquerda nos bits 15-0, direita 31-16, com sinal) num anel de
    -- 64K na SDRAM em 7C0000h; tocadas a mp_rate amostras por segundo; mp_idx = a amostra seguinte a tocar
    mp_on    : in  std_logic := '0';
    mp_rate  : in  std_logic_vector(15 downto 0) := (others => '0');
    mp_idx   : out std_logic_vector(15 downto 0);
    mp_l, mp_r : out std_logic_vector(15 downto 0);   -- (esp49) a amostra do ESP (16 bits), somada no top depois do som.vhd
    ay_vis   : out std_logic_vector(191 downto 0);   -- (esp46: tambem o 3.o AY, bytes 16-23)   -- (2026-10-24) copia dos registos dos AY 1 e 2 (barras do ESP)                      -- (2026-10-24) a DivMMC esta' mapeada (esxDOS/NAV): no maximo 14 MHz
    rato_x, rato_y : in std_logic_vector(7 downto 0) := (others => '0');   -- rato USB (Kempston)
    rato_b   : in  std_logic_vector(2 downto 0) := (others => '0');
    joy      : in  std_logic_vector(7 downto 0) := (others => '0');   -- joystick USB (Kempston, 1F)
    pede_rnmi : out std_logic;                     -- impulso: ZXUNO A2h = 52h (o NAV pede RESET+NMI)
    halt_n   : out std_logic;
    pronta   : out std_logic;
    sd_teste : out std_logic;
    sd_teste2 : out std_logic;
    sd_clk, sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n : out std_logic;
    sd_ba    : out std_logic_vector(1 downto 0);
    sd_addr  : out std_logic_vector(10 downto 0);
    sd_dqm   : out std_logic_vector(3 downto 0);
    sd_dq_i  : in  std_logic_vector(31 downto 0);
    sd_dq_o  : out std_logic_vector(31 downto 0);
    sd_dq_oe : out std_logic;
    mmc_cs_n, mmc_sclk, mmc_mosi : out std_logic;
    mmc_miso : in  std_logic;
    aud_l, aud_r : out std_logic_vector(15 downto 0);
    pal_a    : out std_logic_vector(5 downto 0);
    pal_we   : out std_logic;
    pal_d    : out std_logic_vector(7 downto 0);
    pal_q    : in  std_logic_vector(7 downto 0);
    ulap     : out std_logic;
    -- 2026-10-22: escritas do ESP32 pela ponte (ponte_esp): RAM de video ou SDRAM, um byte de cada vez
    esp_req  : in  std_logic := '0';
    esp_vram : in  std_logic := '0';                     -- 1 = RAM de video (15 bits), 0 = SDRAM (23 bits)
    esp_a    : in  std_logic_vector(22 downto 0) := (others => '0');
    esp_d    : in  std_logic_vector(7 downto 0) := (others => '0');
    esp_ack  : out std_logic;                             -- 1 no ciclo em que o byte e' aceite (so' RAM de video)
    -- (esp43) escritas do ESP na SDRAM em palavras de 32 bits: os bytes de esp_wbe (o byte 0 nos bits 7-0)
    esp_wreq : in  std_logic := '0';
    esp_wa   : in  std_logic_vector(22 downto 0) := (others => '0');   -- endereco da palavra (bits 1-0 ignorados)
    esp_wd   : in  std_logic_vector(31 downto 0) := (others => '0');
    esp_wbe  : in  std_logic_vector(3 downto 0) := "0000";
    esp_wack : out std_logic;
    esp_rreq : in  std_logic := '0';                      -- (v3) leitura da RAM de video (endereco em esp_a)
    esp_rv   : out std_logic;                             -- 1 = esp_rd tem o byte lido
    esp_rd   : out std_logic_vector(7 downto 0);
    -- (2026-10-22) caixa de correio Z80 <-> ESP: portos EE3Bh (comando / estado) e EF3Bh (dados)
    mb_wr    : out std_logic;                             -- OUT a um dos dois portos (enquanto dura)
    mb_rd    : out std_logic;                             -- IN de um dos dois portos (enquanto dura)
    mb_sel   : out std_logic;                             -- 0 = EE3Bh, 1 = EF3Bh
    mb_d     : out std_logic_vector(7 downto 0);
    mb_q     : in  std_logic_vector(7 downto 0) := x"FF";
    -- (2026-10-23) UART do ZX-UNO (registos C6h dados / C7h estado pelas FC3B/FD3B), ligada ao ESP
    ua_wr    : out std_logic;                             -- OUT FD3B com o registo C6 (enquanto dura; dado em mb_d)
    ua_rd    : out std_logic;                             -- IN FD3B com o registo C6 ou C7 (enquanto dura)
    ua_dat   : out std_logic;                             -- 1 = C6 (dados), 0 = C7 (estado)
    ua_q     : in  std_logic_vector(7 downto 0) := x"FF";
    -- (2026-10-22) a maquina, para o ESP: bit 15 = GS a correr, 9 = TC2068 (DivTIESUS), 8 = modo 128 (F4 = F0),
    -- 7-0 = registo F3 (bit 7 Pentagon, bit 5 ZX)
    maq_st   : out std_logic_vector(15 downto 0);
    gs_parar : in  std_logic := '0';                      -- (2026-10-22) o ESP para o General Sound
    ay3_lig  : in  std_logic := '0';                      -- (2026-10-23) placa do 3.o AY (o ESP liga-a)
    -- camada do ESP (camada_esp): leitura de uma linha da imagem (160 bytes = 40 palavras) da SDRAM
    -- (v2) pedidos da camada_esp, no relogio do HDMI (mudam de valor): linha da camada L (320 bytes) e
    -- linha da janela W (1024 bytes), lidas em rajadas de 8 palavras para o buffer de linhas
    ovl_pede_l : in  std_logic := '0';
    ovl_lin_l  : in  std_logic_vector(9 downto 0) := (others => '0');
    ovl_pede_w : in  std_logic := '0';
    ovl_lin_w  : in  std_logic_vector(7 downto 0) := (others => '0');
    ovl_w16   : in  std_logic := '0';
    ovl_wsep  : in  std_logic := '0';                     -- (esp44) a janela na imagem ovl_widx: 0 680000h, 1 6C0000h, 2 780000h
    ovl_widx  : in  std_logic_vector(1 downto 0) := "00";                     -- (esp43) janela a 16 bits: 512 bytes por linha, 16 rajadas
    ovl_sel   : in  std_logic := '0';                     -- 0: L em 600000h e W em 680000h; 1: 640000h e 6C0000h
    lb_we     : out std_logic;
    lb_a      : out std_logic_vector(8 downto 0);
    lb_d      : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of core_timextenso is
  component T80se
    generic (Mode : integer := 0; T2Write : integer := 0; IOWait : integer := 1);
    port (RESET_n, CLK_n, CLKEN, WAIT_n, INT_n, NMI_n, BUSRQ_n : in std_logic;
          M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, BUSAK_n : out std_logic;
          A : out std_logic_vector(15 downto 0);
          DI : in std_logic_vector(7 downto 0);
          DO : out std_logic_vector(7 downto 0));
  end component;
  component ram_home
    port (clk : in std_logic; a : in std_logic_vector(13 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  component ram_esx
    port (clk : in std_logic; a : in std_logic_vector(12 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0));
  end component;
  component sid_timextenso
    port (clk, reset, ce_1m : in std_logic; cs : in std_logic_vector(1 downto 0); we : in std_logic;
          addr : in std_logic_vector(4 downto 0); din : in std_logic_vector(7 downto 0);
          dout : out std_logic_vector(7 downto 0); mode : in std_logic_vector(1 downto 0);
          audio_l, audio_r : out std_logic_vector(17 downto 0));
  end component;
  component ram_dp12k
    port (clk : in std_logic; a : in std_logic_vector(13 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0);
          clkb : in std_logic; b : in std_logic_vector(13 downto 0); bq : out std_logic_vector(7 downto 0));
  end component;
  component ram_dp
    generic (AW : integer := 14);
    port (clk : in std_logic;
          a : in std_logic_vector(AW-1 downto 0); we : in std_logic;
          d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0);
          clkb : in std_logic;
          b : in std_logic_vector(AW-1 downto 0); bq : out std_logic_vector(7 downto 0));
  end component;
  component divtiesus_tang
    port (clk : in std_logic; rst_n : in std_logic; a : in std_logic_vector(15 downto 0);
          mreq_n, iorq_n, rd_n, wr_n, m1_n : in std_logic;
          din : in std_logic_vector(7 downto 0); dout : out std_logic_vector(7 downto 0); doe : out std_logic;
          zxromcs, be_n, nmi_n : out std_logic; nmi_button_n : in std_logic;
          sclk, mosi : out std_logic; miso : in std_logic; sd_cs0 : out std_logic;
          eeprom_oe_n, sram_oe_n, sram_we_n : out std_logic;
          sram_hiaddr : out std_logic_vector(5 downto 0);
          modo128, modo2068 : out std_logic; p1024 : in std_logic);
  end component;

  signal a, a_l : std_logic_vector(15 downto 0);
  signal di, do_cpu : std_logic_vector(7 downto 0);
  signal m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n : std_logic;
  signal int_n : std_logic := '1';
  signal cpu_nmi_n : std_logic;
  -- DivTIESUS
  signal dv_q : std_logic_vector(7 downto 0);
  signal dv_oe, dv_romcs, dv_be_n, dv_ee_n, dv_oe_n, dv_we_n, dv_m128, dv_m2068 : std_logic;
  signal dv_hi : std_logic_vector(5 downto 0);
  signal dv_ee_l, dv_oe_l, dv_romcs_l : std_logic := '0';
  -- SCLD
  signal brd     : std_logic_vector(2 downto 0) := "111";
  signal beep    : std_logic := '0';
  signal regff   : std_logic_vector(7 downto 0) := (others => '0');
  signal banksel : std_logic_vector(7 downto 0) := (others => '0');   -- F4 (sem reset, como no SCLD)
  signal regf3   : std_logic_vector(7 downto 0) := (others => '0');   -- F3 (sem reset)
  signal modo128, penta, t128 : std_logic;
  signal b7ffd   : std_logic_vector(2 downto 0) := "000";
  signal scr7, lock7, ext7 : std_logic := '0';
  -- Pentagon 1024: 7FFD bits 7 e 5 (bits 4 e 5 do banco); ZXUNO DDh bit 2 (.go1024); EFF7 bit 2 (1 = 128K)
  signal pg4, pg5, dd1024, eff7b2, eff7b0 : std_logic := '0';
  -- modo 16C: copia dos bancos 4/6 (SDRAM) para o cap2 (12K), uma leitura cada ~48 ciclos
  signal m16c_i, v_req, v_vez, v_fim, cw2_we : std_logic := '0';
  signal v_k : integer range 0 to 12287 := 0;
  signal v_cnt : integer range 0 to 63 := 0;
  signal v_off : std_logic_vector(13 downto 0);
  signal v_sa : std_logic_vector(22 downto 0);
  signal q_v, cw2_d : std_logic_vector(7 downto 0) := (others => '0');
  signal cw2_a : std_logic_vector(13 downto 0) := (others => '0');
  signal dono2 : std_logic_vector(2 downto 0) := "000";      -- 000 Z80, 001 GS, 010 copia do 16C, 011 ESP, 100 camada
  -- ecra para o HDMI (captura ao ritmo do Z80 / copia nos modos do Timex)
  constant CAP_OFS : integer := 3;                                  -- T antes do ponto (afinado no core Pentagon)
  signal cap_zx, cap_zx_l, cap_on, cap_go, cw_we, ecra7_i, cp_ok : std_logic := '0';
  signal t0cap : integer range 0 to 71679;
  signal ltfim : integer range 0 to 227;
  signal lt : integer range 0 to 227 := 0;
  signal ly : unsigned(7 downto 0) := (others => '0');
  signal cx : unsigned(4 downto 0) := (others => '0');
  signal cs : integer range 0 to 7 := 7;
  signal cap_a : std_logic_vector(14 downto 0) := (others => '0');
  signal cap_q, cw_d : std_logic_vector(7 downto 0) := (others => '0');
  -- (esp59) barramento flutuante (F3 bit 5), como o float6 do SCLD do CPLD: o ultimo atributo lido pelo
  -- video (o da coluna impar de cada grupo de 8 T) na metade seguinte do grupo; FFh na outra metade e fora do paper
  signal fl_at   : std_logic_vector(7 downto 0) := x"FF";
  signal fl_byte : std_logic_vector(7 downto 0);
  signal cw_a, cp_1 : std_logic_vector(13 downto 0) := (others => '0');
  signal cp_n : unsigned(13 downto 0) := (others => '0');
  signal boff : std_logic_vector(12 downto 0);
  signal zx_reg : std_logic_vector(7 downto 0) := (others => '0');
  -- (esp61) carga das ROMs do cartao ao ligar
  signal carga : std_logic := '1';                              -- 1 = modo de carga (ate' ao "fim")
  signal carga_alvo : std_logic := '0';                         -- 0 = ram_home, 1 = ram_esx
  signal carga_rst : unsigned(16 downto 0) := (others => '0');  -- reset do Z80 e da DivTIESUS no fim
  signal rst_n_i : std_logic;                                   -- reset_n da placa e o do fim da carga
  signal home_we, esx_we : std_logic;
  signal rnmi_p : std_logic := '0';
  signal m1024, alto, big, big_l : std_logic := '0';
  signal banco6 : std_logic_vector(5 downto 0);
  signal idle    : unsigned(10 downto 0) := (others => '0');
  signal home, vram, vram128, bnk, interna : std_logic;
  signal home_l, vram_l, interna_l, bnk_l : std_logic := '0';
  signal io_wr, io_rd : std_logic;
  signal mb_cs : std_logic;
  signal ua_cs : std_logic;
  signal teclas  : std_logic_vector(4 downto 0);
  signal q_rom, q_esx, q_scr, q_sd : std_logic_vector(7 downto 0);
  -- SDRAM
  signal sd_ok, sd_livre, sd_req, sd_we, sd_rf : std_logic;
  signal feito, rf_feito : std_logic := '0';
  signal rf_t : unsigned(8 downto 0) := (others => '0');
  signal sd_a : std_logic_vector(22 downto 0);
  signal sd_be : std_logic_vector(3 downto 0);
  -- SDRAM com dois clientes: o Z80 (m_*, com prioridade) e o General Sound (g_*)
  signal m_sd_req, m_sd_we, sd_req_t, sd_we_t, g_req, g_ok, g_vez, dono, pend, livre_d : std_logic := '0';
  signal a_req, a_vez, a_acc, a_fim : std_logic := '0';
  signal a_acc_c : unsigned(26 downto 0) := (others => '0');
  signal a_i : unsigned(15 downto 0) := (others => '0');
  signal mpl, mpr : signed(15 downto 0) := (others => '0');
  -- (esp48) 16 amostras lidas adiantadas: a SDRAM as vezes demora (o Z80 a 27 MHz, a imagem) e o tique da
  -- amostra perdia-se (soluços)
  type mpf_t is array (0 to 15) of std_logic_vector(31 downto 0);
  signal mpf : mpf_t;
  signal mp_fw, mp_fr : unsigned(4 downto 0) := (others => '0');
  signal a_voo : std_logic := '0';
  signal a_sa : std_logic_vector(22 downto 0);
  signal m_sd_a, g_sa : std_logic_vector(22 downto 0);
  signal sd_d, g_sd : std_logic_vector(7 downto 0);
  signal q_m, q_g : std_logic_vector(7 downto 0) := (others => '0');
  signal q_sd32 : std_logic_vector(31 downto 0);
  signal q_g32 : std_logic_vector(31 downto 0) := (others => '0');
  -- cache do GS: 64 linhas de 4 bytes (mapeamento directo), escrita directa na SDRAM
  type c_dat_t is array (0 to 63) of std_logic_vector(31 downto 0);
  type c_tag_t is array (0 to 63) of std_logic_vector(10 downto 0);
  signal c_dat : c_dat_t;
  signal c_tag : c_tag_t;
  signal c_val : std_logic_vector(63 downto 0) := (others => '0');
  signal c_idx : integer range 0 to 63;
  signal c_hit, c_ler : std_logic;
  signal c_byte : std_logic_vector(7 downto 0);
  signal g_feito, g_emcurso, g_fim : std_logic := '0';
  signal fase : integer range 0 to 63 := 0;
  -- turbo: o Z80 espera (WAIT no T2) ate' a SDRAM acabar; a 3,5 MHz nunca espera
  signal cpu_wait_n, m_acc : std_logic;
  -- (2026-10-24) SPI da DivMMC (porta EBh): cada byte leva ~0,65 us (16 ciclos de 27 MHz + o arranque).
  -- A 27 MHz o esxDOS faz o OUT/IN seguinte antes de o SPI acabar (a DivMMC ignora-o e o byte vem errado):
  -- em turbo, um IN/OUT a EBh espera (WAIT) ate' ~0,8 us depois do anterior
  signal spi_t : integer range 0 to 63 := 0;
  type ay_copia_t is array (0 to 10) of std_logic_vector(7 downto 0);
  signal ayc1, ayc2, ayc3 : ay_copia_t := (others => (others => '0'));
  signal ay1_r, ay2_r, ay3_r : unsigned(3 downto 0) := (others => '0');
  -- (2026-10-24) o nivel real de cada canal (o maximo da saida do AY em cada 20 ms): ja' conta com o mixer,
  -- o envelope e o ruido, por isso as barras batem com o que se ouve
  signal pico, pico_m : std_logic_vector(71 downto 0) := (others => '0');   -- 9 canais x 8 bits
  signal pico_t20 : integer range 0 to 1080000 := 0;
  signal eb_io, eb_d, e7_io : std_logic := '0';
  signal m_lido : std_logic := '0';
  -- cache do Z80 principal (v3, 21/10/2026): so' actua em turbo. 64 linhas de 4 bytes, mapeamento
  -- directo pelo endereco da SDRAM (indice 7-2, etiqueta 22-8), escrita directa.
  -- Os pedidos a' SDRAM saem exactamente como sem cache; um acerto so' liberta o WAIT mais cedo
  -- (q_m = byte da cache). A procura e' registada em dois andares (endereco, depois acerto).
  type z_tag_t is array (0 to 63) of std_logic_vector(14 downto 0);
  signal z_dat : c_dat_t;
  signal z_tag : z_tag_t;
  signal z_val : std_logic_vector(63 downto 0) := (others => '0');
  signal z_a_r, z_fa, z_wa : std_logic_vector(22 downto 0) := (others => '0');
  signal z_hit_r, z_ler, z_enche, z_wv, z_voo, z_desc : std_logic := '0';
  signal z_byte_r, z_wd : std_logic_vector(7 downto 0) := (others => '0');
  signal z_mc : integer range 0 to 3 := 0;
  signal q_mz : std_logic_vector(7 downto 0);         -- o dado do Z80: o byte da cache no acerto, senao q_m
  -- SID (como o ZX-TSid: xxCF, registo = A12-A8); SID 2 com A13 = 1 (nosso)
  signal sid_cs : std_logic_vector(1 downto 0);
  signal sid_q : std_logic_vector(7 downto 0);
  signal sid_l, sid_r : std_logic_vector(17 downto 0);
  signal sid_ce, sid_on, sid_rst : std_logic := '0';
  signal sid_div : integer range 0 to 53 := 0;             -- leitura do Z80 ja' em q_m
  -- General Sound
  signal gs_rst : std_logic := '1';                                 -- ZX-UNO A0h bit 0: GS parado (ate' haver ROM)
  signal gs_lp : unsigned(14 downto 0) := (others => '0');           -- carga da ROM (ZX-UNO A1h)
  signal ld_pend, io_wr_d : std_logic := '0';
  signal ld_d : std_logic_vector(7 downto 0) := (others => '0');
  signal gs_ce : std_logic := '0';
  signal gs_cnt : unsigned(1 downto 0) := (others => '0');
  signal gs_cs_rd, gs_cs_wr, gs_rd, gs_wr, gs_wait, gs_acc : std_logic;
  signal gs_ma, gs_ma_c : std_logic_vector(20 downto 0);
  signal gs_md, gs_md_c, gs_q : std_logic_vector(7 downto 0);
  signal gs_rd_c, gs_wr_c : std_logic;
  signal gs_l, gs_r : signed(14 downto 0);
  signal gs_alto : std_logic;
  signal gs_mq : std_logic_vector(7 downto 0);
  signal sram_rd, sram_wr, int_rd, int_wr : std_logic;
  -- quadro
  signal tcnt : integer range 0 to 71679 := 0;
  signal tfim : integer range 0 to 71679;
  signal tint : integer range 0 to 63;
  -- AY
  signal ay_sel, ay_we, ay_le, ay_en, ay_meio : std_logic := '0';
  signal ay_q, ay_a, ay_b, ay_c : std_logic_vector(7 downto 0);
  signal ay2_sel, ay2_we, p_sel, p_dat, ts_cmd : std_logic;
  signal ts : std_logic_vector(1 downto 0) := "00";                  -- o FFFD vai para: 00 AY 2, 01 AY 1, 10 AY 3
  signal ay2_q, ay2_a, ay2_b, ay2_c, ay_qm : std_logic_vector(7 downto 0);
  signal ay3_sel, ay3_we, ay3_on : std_logic := '0';                 -- (2026-10-23) 3.o AY (TurboSound Next: FD)
  signal ay3_q, ay3_a, ay3_b, ay3_c : std_logic_vector(7 downto 0);
  -- ULAplus
  signal u_porta : std_logic;
  signal u_q : std_logic_vector(7 downto 0);
  -- ESP: na RAM de video entra num ciclo em que o Z80 nao esta' a aceder a ela;
  -- na SDRAM e' o ultimo cliente (depois do Z80, da copia do 16C e do GS)
  signal e_vgo, e_req, e_vez, e_acc, scr_we, e_rgo : std_logic;
  signal e_rvoo : std_logic := '0';
  signal scr_a : std_logic_vector(14 downto 0);
  signal scr_d : std_logic_vector(7 downto 0);
  -- camada do ESP: 40 leituras de 32 bits por linha, logo a seguir ao Z80 na prioridade
  signal ol_s, ow_s : std_logic_vector(2 downto 0) := "000";
  signal ol_req, ow_req, o_req, o_vez, o_acc, z_acc, lb_we_r : std_logic := '0';
  signal ol_lin : unsigned(9 downto 0) := (others => '0');
  signal ol_k : unsigned(3 downto 0) := (others => '0');      -- 10 rajadas por linha da camada L
  signal ow_k : unsigned(4 downto 0) := (others => '0');
  signal ow16_s : std_logic_vector(1 downto 0) := "00";
  signal ow_off : unsigned(22 downto 0);
  signal ow_ult : unsigned(4 downto 0) := to_unsigned(31, 5);      -- 32 rajadas por linha da janela
  signal ol_base, ow_base : unsigned(22 downto 0) := (others => '0');
  signal f_w, f_half : std_logic := '0';                         -- rajada em curso: 1 = janela; metade da camada L
  signal f_k : unsigned(4 downto 0) := (others => '0');
  signal o_sa : std_logic_vector(22 downto 0);
  signal lb_a_r : std_logic_vector(8 downto 0) := (others => '0');
  signal lb_d_r : std_logic_vector(31 downto 0) := (others => '0');
  signal sd_qr : std_logic_vector(31 downto 0);
  signal sd_qr_v : std_logic;
  signal sd_qr_i : unsigned(2 downto 0);
begin
  rst_n_i <= reset_n and not carga_rst(16);
  cpu: T80se
    generic map (Mode => 0, T2Write => 1, IOWait => 1)
    port map (RESET_n => rst_n_i, CLK_n => clk, CLKEN => ce,
              WAIT_n => cpu_wait_n, INT_n => int_n, NMI_n => cpu_nmi_n, BUSRQ_n => '1',
              M1_n => m1_n, MREQ_n => mreq_n, IORQ_n => iorq_n, RD_n => rd_n, WR_n => wr_n,
              RFSH_n => rfsh_n, HALT_n => halt_n, BUSAK_n => open,
              A => a, DI => di, DO => do_cpu);

  ---------------------------------------------------------------------------
  -- DivTIESUS v13
  dv: divtiesus_tang
    port map (clk => clk_div, rst_n => rst_n_i, a => a,
              mreq_n => mreq_n, iorq_n => iorq_n, rd_n => rd_n, wr_n => wr_n, m1_n => m1_n,
              din => do_cpu, dout => dv_q, doe => dv_oe,
              zxromcs => dv_romcs, be_n => dv_be_n, nmi_n => cpu_nmi_n, nmi_button_n => nmi_n,
              sclk => mmc_sclk, mosi => mmc_mosi, miso => mmc_miso, sd_cs0 => mmc_cs_n,
              eeprom_oe_n => dv_ee_n, sram_oe_n => dv_oe_n, sram_we_n => dv_we_n,
              sram_hiaddr => dv_hi, modo128 => dv_m128, modo2068 => dv_m2068, p1024 => m1024);

  ---------------------------------------------------------------------------
  -- SCLD: portas (amostradas como no scld_regs: escrita do Z80 a meio do ciclo de E/S)
  io_wr <= '1' when iorq_n = '0' and wr_n = '0' and m1_n = '1' else '0';
  io_rd <= '1' when iorq_n = '0' and rd_n = '0' and m1_n = '1' else '0';
  mb_cs  <= '1' when a(15 downto 9) = "1110111" and a(7 downto 0) = x"3B" else '0';   -- EE3Bh / EF3Bh
  mb_wr  <= io_wr and mb_cs;
  mb_rd  <= io_rd and mb_cs;
  mb_sel <= a(8);
  mb_d   <= do_cpu;
  ua_cs  <= '1' when a = x"FD3B" and (zx_reg = x"C6" or zx_reg = x"C7") else '0';
  ua_wr  <= io_wr and ua_cs and not zx_reg(0);
  ua_rd  <= io_rd and ua_cs;
  ua_dat <= not zx_reg(0);                           -- C6 = ...0, C7 = ...1
  maq_st <= (not gs_rst) & ay3_lig & "000" & m1024 & dv_m2068 & modo128 & regf3;   -- (62) bit 2 do 79 = 1024K (DDh bit 2 e EFF7 bit 2 a 0)
  process(clk)
  begin
    if rising_edge(clk) then
      rnmi_p <= '0';
      if io_wr = '1' then
        case a(7 downto 0) is
          when x"FE" => brd <= do_cpu(2 downto 0); beep <= do_cpu(4);
          when x"FF" => if regf3(5) = '0' then regff <= do_cpu; end if;   -- F3 bit 5: FF ignorada
          when x"F4" => banksel <= do_cpu;
          when x"F3" => regf3 <= do_cpu;
          when others => null;
        end case;
        if a = x"FC3B" then zx_reg <= do_cpu; end if;
        if a = x"FD3B" and zx_reg = x"DD" then dd1024 <= do_cpu(2); end if;
        if a = x"EFF7" then eff7b2 <= do_cpu(2); eff7b0 <= do_cpu(0); end if;
        if a = x"FD3B" and zx_reg = x"A0" and io_wr_d = '0' then gs_rst <= do_cpu(0); end if;
        if a = x"FD3B" and zx_reg = x"A4" and carga = '1' then      -- (esp61) programa de arranque
          carga_alvo <= do_cpu(0);
          if do_cpu(7) = '1' then carga <= '0'; carga_rst <= (others => '1'); end if;
        end if;
        -- (2026-10-20: o A2h = 52h ja' nao faz o RESET+NMI: a DivTIESUS faz o master reset dos
        --  registos, como no clone, e o navegador arranca o TC2048 com jp 0)
      end if;
      if gs_parar = '1' then gs_rst <= '1'; end if;   -- o ESP para o General Sound (fora do OUT do Z80)
      if carga_rst(16) = '1' then carga_rst <= carga_rst - 1; end if;   -- (esp61) ~1,2 ms de reset no fim da carga
      if rst_n_i = '0' then brd <= "111"; regff <= (others => '0'); dd1024 <= '0'; eff7b2 <= '0'; eff7b0 <= '0'; end if;   -- F4 e F3 sem reset
    end if;
  end process;
  border <= brd;
  -- ecra normal: o HDMI mostra o ecra capturado, com um atributo por linha (hi-colour)
  modo   <= "010" when cap_zx = '1' or m16c_i = '1' else regff(2 downto 0);
  hcor   <= regff(5 downto 3);

  -- scld_128: F4 = F0 e' o modo 128K; 7FFD (A15 = 0, A1 = 0) com o trinco no bit 5.
  -- Sai do modo (e limpa o 7FFD) com F4 /= F0 ou com o MREQ parado 2048 ciclos (reset).
  modo128 <= '1' when banksel = x"F0" else '0';
  penta   <= modo128 and regf3(7);
  t128    <= modo128 and regf3(2) and not penta;
  -- Pentagon 1024 (.go1024): Pentagon 256 (F3 bits 7 e 3) + DDh bit 2, com o EFF7 bit 2 a 0.
  -- Banco = 7FFD bits 5,7,6,2,1,0 (64 x 16K); o bit 5 nao e' trinco. Os bancos de C000h
  -- (menos 5 e 7 na RAM de video) sao todos servidos aqui: a copia do 7FFD da DivTIESUS
  -- nao conhece os bits 5 e 7. Bancos 0-15 nas mesmas paginas que a DivTIESUS usa.
  m1024  <= modo128 and regf3(7) and regf3(3) and dd1024 and not eff7b2;
  banco6 <= (pg5 and m1024) & (pg4 and m1024) & ext7 & b7ffd;
  alto   <= '1' when regf3(7) = '1' and regf3(3) = '1' and (ext7 = '1' or (m1024 = '1' and (pg4 = '1' or pg5 = '1'))) else '0';
  big    <= '1' when m1024 = '1' and a(15 downto 14) = "11" and vram128 = '0' and mreq_n = '0' and rfsh_n = '1' else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if mreq_n = '0' then idle <= (others => '0');
      elsif ce = '1' and idle /= (idle'range => '1') then idle <= idle + 1; end if;
      if modo128 = '0' or idle = (idle'range => '1') then
        b7ffd <= "000"; scr7 <= '0'; lock7 <= '0'; ext7 <= '0'; pg4 <= '0'; pg5 <= '0';
      elsif io_wr = '1' and a(15) = '0' and a(1) = '0' and (lock7 = '0' or m1024 = '1') then
        b7ffd <= do_cpu(2 downto 0); scr7 <= do_cpu(3); lock7 <= do_cpu(5) and not m1024; ext7 <= do_cpu(6);
        pg4 <= do_cpu(7); pg5 <= do_cpu(5);
      end if;
    end if;
  end process;
  ecra7 <= modo128 and scr7;

  -- mapa (como o SCLD v13)
  home    <= not banksel(to_integer(unsigned(a(15 downto 13))));
  vram128 <= '1' when modo128 = '1' and a(15 downto 14) = "11" and b7ffd(2) = '1' and b7ffd(0) = '1'
                      and alto = '0' else '0';
  vram    <= '1' when a(15 downto 14) = "01" or vram128 = '1' else '0';
  bnk     <= vram128 and b7ffd(1);                      -- 0 = banco 5, 1 = banco 7
  -- RAM interna 8000-FFFF: so' com o bloco na HOME e sem a DivTIESUS a servir (BE)
  interna <= '1' when a(15) = '1' and vram128 = '0' and home = '1' and dv_be_n = '1' else '0';

  ---------------------------------------------------------------------------
  -- memorias
  -- (esp61) as duas ROMs sao RAM, escritas pelo programa de arranque (escritas do Z80 em 0000-3FFF no modo de carga)
  home_we <= '1' when carga = '1' and carga_alvo = '0' and mreq_n = '0' and wr_n = '0' and rfsh_n = '1' and a(15 downto 14) = "00" else '0';
  esx_we  <= '1' when carga = '1' and carga_alvo = '1' and mreq_n = '0' and wr_n = '0' and rfsh_n = '1' and a(15 downto 13) = "000" else '0';
  rom: ram_home port map (clk => clk, a => a(13 downto 0), we => home_we, d => do_cpu, q => q_rom);
  esx: ram_esx  port map (clk => clk, a => a(12 downto 0), we => esx_we, d => do_cpu, q => q_esx);    -- a "EEPROM" da DivTIESUS
  -- o ESP so' usa o porto A num ciclo sem acesso do Z80 a' RAM de video: o Z80 so' le' o dado
  -- 3 ou mais ciclos depois de o MREQ descer, e o porto A ja' voltou ao endereco dele
  e_vgo  <= '1' when esp_req = '1' and esp_vram = '1' and not (mreq_n = '0' and rfsh_n = '1' and vram = '1') else '0';
  -- leitura pelo ESP: como a escrita, num ciclo sem acesso do Z80; o byte sai no ciclo seguinte
  e_rgo  <= '1' when esp_rreq = '1' and e_vgo = '0' and e_rvoo = '0' and not (mreq_n = '0' and rfsh_n = '1' and vram = '1') else '0';
  scr_a  <= esp_a(14 downto 0) when e_vgo = '1' or e_rgo = '1' else bnk & a(13 downto 0);
  process(clk) begin if rising_edge(clk) then e_rvoo <= e_rgo; end if; end process;
  esp_rv <= e_rvoo; esp_rd <= q_scr;
  scr_we <= '1' when e_vgo = '1' or (mreq_n = '0' and wr_n = '0' and rfsh_n = '1' and vram = '1') else '0';
  scr_d  <= esp_d when e_vgo = '1' else do_cpu;
  scr: ram_dp generic map (AW => 15)
    port map (clk => clk, a => scr_a,
              we => scr_we, d => scr_d, q => q_scr,
              clkb => clk, b => cap_a, bq => cap_q);

  ---------------------------------------------------------------------------
  -- Ecra para o HDMI (como no core Pentagon): o HDMI le' um ecra a parte (cap, 16K).
  --  - Ecra normal (FF modo 000, ou a FF escondida pelo F3 bit 5): cada byte (bitmap e
  --    atributo) e' copiado da RAM de video no T em que o ULA/Pentagon o leria (1.o ponto a
  --    14336 T do INT no 48K, 14362 no 128K, 17988 no Pentagon; 224 ou 228 T por linha,
  --    4 T por byte), com um atributo por linha (como o hi-colour): o multicolor sai certo.
  --  - Modos do Timex (hi-colour, hi-res, ecra 2): copia a RAM de video toda sem parar
  --    (16K a 27 MHz, ~0,6 ms), como se o HDMI a lesse directamente.
  -- modo 16C do Pentagon: EFF7 bit 0 (so' no Pentagon); os bancos 5/7 vao pela copia continua
  -- 2026-10-21: um modo do Timex na FF (o navegador em hi-res) passa a' frente do 16C; os programas do
  -- Pentagon nao mexem na FF (escondida pelo F3 bit 5), so' o navegador, que a volta a por a 0 ao sair
  m16c_i <= penta and eff7b0 when regff(2 downto 0) = "000" else '0';
  m16c   <= m16c_i;
  cap_zx <= '1' when (regff(2 downto 0) = "000" or regf3(5) = '1') and m16c_i = '0' else '0';
  t0cap  <= 17988 - 1 - CAP_OFS when penta = '1' else 14362 - 1 - CAP_OFS when t128 = '1' else 14336 - 1 - CAP_OFS;
  ltfim  <= 227 when t128 = '1' else 223;
  process(clk)
  begin
    if rising_edge(clk) then
      cap_go <= '0';
      if ce35 = '1' then
        if tcnt = t0cap then
          cap_on <= '1'; lt <= 0; ly <= (others => '0');
          cap_go <= '1'; cx <= (others => '0');
        elsif cap_on = '1' then
          if lt >= ltfim then
            lt <= 0;
            if ly = 191 then cap_on <= '0'; else ly <= ly + 1; cap_go <= '1'; cx <= (others => '0'); end if;
          else
            lt <= lt + 1;
            if lt mod 4 = 3 and lt < 127 then cap_go <= '1'; cx <= to_unsigned((lt + 1) / 4, 5); end if;
          end if;
        end if;
      end if;
    end if;
  end process;
  boff <= std_logic_vector(ly(7 downto 6) & ly(2 downto 0) & ly(5 downto 3) & cx);
  process(clk)
  begin
    if rising_edge(clk) then
      cw_we <= '0';
      cap_zx_l <= cap_zx;
      if cap_zx_l = '1' then
        -- 2 leituras (bitmap, atributo) e 2 escritas por byte do ecra
        if cap_go = '1' then
          cap_a <= ecra7_i & '0' & boff; cs <= 0;                                 -- bitmap
        elsif cs /= 7 then
          cs <= cs + 1;
          case cs is
            when 0 => cap_a <= ecra7_i & "0110" & std_logic_vector(ly(7 downto 3) & cx);  -- atributo
            when 1 => cw_a <= '0' & boff; cw_d <= cap_q; cw_we <= '1';                -- bitmap
            when 2 => cw_a <= '1' & boff; cw_d <= cap_q; cw_we <= '1';                -- atributo da linha
                      if cx(0) = '1' then fl_at <= cap_q; end if;                     -- (esp59) barramento flutuante
            when others => cs <= 7;
          end case;
        end if;
      else
        -- modos do Timex: copia tudo, um byte por ciclo (endereco -> dado 1 ciclo depois)
        cs <= 7;
        cp_n <= cp_n + 1;
        cap_a <= ecra7_i & std_logic_vector(cp_n);
        cp_1 <= cap_a(13 downto 0);
        cw_a <= cp_1; cw_d <= cap_q; cw_we <= cp_ok;
        cp_ok <= '1';
      end if;
    end if;
  end process;
  ecra7_i <= modo128 and scr7;
  -- (esp59) o grupo k le' as colunas 2k (lt = 8k-1) e 2k+1 (lt = 8k+3); de 8k+4 a 8k+7 a FF da' o atributo da 2k+1
  fl_byte <= fl_at when cap_zx_l = '1' and cap_on = '1' and lt < 128 and (lt mod 8) >= 4 else x"FF";
  pede_rnmi <= rnmi_p;
  cap: ram_dp generic map (AW => 14)
    port map (clk => clk, a => cw_a, we => cw_we, d => cw_d, q => open,
              clkb => vclk, b => vid_a(13 downto 0), bq => vid_q);

  -- modo 16C: os bancos 4/6 (os 2 x 6K que o 16C usa: 0000-17FF e 2000-37FF) copiados da SDRAM
  -- para o cap2 (0..6143 e 6144..12287), sem parar, uma leitura e uma pausa de ~48 ciclos
  -- (o GS fica com as outras vagas). Banco 4, ou 6 com o 7FFD bit 3.
  v_off <= std_logic_vector(to_unsigned(v_k, 14)) when v_k < 6144 else
           std_logic_vector(to_unsigned(v_k - 6144 + 8192, 14));
  v_sa  <= "001" & '0' & '1' & '0' & '1' & scr7 & '0' & v_off;
  process(clk)
  begin
    if rising_edge(clk) then
      cw2_we <= '0';
      if m16c_i = '0' then
        v_req <= '0'; v_cnt <= 0;
      else
        if v_vez = '1' and sd_livre = '1' and sd_rf = '0' then v_req <= '0';
        elsif v_req = '0' and v_cnt = 0 and pend = '0' then v_req <= '1'; end if;
        if v_cnt /= 0 then v_cnt <= v_cnt - 1; end if;
        if v_fim = '1' then
          cw2_a <= std_logic_vector(to_unsigned(v_k, 14)); cw2_d <= q_v; cw2_we <= '1';
          if v_k = 12287 then v_k <= 0; else v_k <= v_k + 1; end if;
          v_cnt <= 48;
        end if;
      end if;
    end if;
  end process;
  cap2: ram_dp12k
    port map (clk => clk, a => cw2_a, we => cw2_we, d => cw2_d,
              clkb => vclk, b => vid_a2, bq => vid_q2);

  -- SDRAM: a SRAM da DivTIESUS (1 MB + pagina x 8K) ou a RAM interna (0-7FFF)
  sram_rd <= (not dv_oe_n) and not big;
  sram_wr <= (not dv_we_n) and (not wr_n) and not big;
  int_rd  <= interna and not rd_n;
  int_wr  <= interna and not wr_n;
  m_sd_a <= "001" & '0' & (not banco6(3)) & '0' & banco6(2 downto 0) & a(13 downto 0) when big = '1' and banco6(5 downto 4) = "00"
          else "010" & banco6 & a(13 downto 0) when big = '1'
          else "001" & '0' & dv_hi & a(12 downto 0) when (sram_rd = '1' or sram_wr = '1')
          else "00000000" & a(14 downto 0);
  m_sd_req <= '1' when mreq_n = '0' and rfsh_n = '1' and feito = '0' and
                     (sram_rd = '1' or sram_wr = '1' or int_rd = '1' or int_wr = '1' or
                      (big = '1' and (rd_n = '0' or wr_n = '0'))) else '0';
  m_sd_we <= not wr_n;
  m_acc <= '1' when mreq_n = '0' and rfsh_n = '1' and
                    (sram_rd = '1' or sram_wr = '1' or int_rd = '1' or int_wr = '1' or
                     (big = '1' and (rd_n = '0' or wr_n = '0'))) else '0';
  -- acerto na cache: o endereco ja' estava estavel 3 ciclos (z_mc = 3) e a procura e' desse endereco
  -- v3b: o MREQ sai do T80 logo a seguir a um flanco do clk, por isso o m_sd_a ja' e' valido no
  -- primeiro flanco com o MREQ em baixo (z_a_r) e o acerto no segundo (z_mc >= 2)
  z_ler <= '1' when turbo = '1' and m_acc = '1' and rd_n = '0' and wr_n = '1' and z_mc >= 2 and z_hit_r = '1' else '0';
  process(clk)
    variable i : integer range 0 to 63;
    variable w : std_logic_vector(31 downto 0);
    variable b : integer range 0 to 3;
  begin
    if rising_edge(clk) then
      -- andar 1: o endereco; andar 2: o acerto e o byte
      z_a_r <= m_sd_a;
      i := to_integer(unsigned(z_a_r(7 downto 2)));
      if z_val(i) = '1' and z_tag(i) = z_a_r(22 downto 8) then z_hit_r <= '1'; else z_hit_r <= '0'; end if;
      case z_a_r(1 downto 0) is
        when "00"   => z_byte_r <= z_dat(i)(7 downto 0);
        when "01"   => z_byte_r <= z_dat(i)(15 downto 8);
        when "10"   => z_byte_r <= z_dat(i)(23 downto 16);
        when others => z_byte_r <= z_dat(i)(31 downto 24);
      end case;
      if mreq_n = '0' and rfsh_n = '1' then
        if z_mc /= 3 then z_mc <= z_mc + 1; end if;
      else
        z_mc <= 0;
      end if;
      -- pedido do Z80 aceite pela SDRAM: leitura -> enche a linha quando o dado chegar;
      -- escrita -> no ciclo seguinte actualiza o byte se a linha estiver na cache
      if pend = '1' and sd_livre = '1' and livre_d = '0' and dono2 = "000" and z_enche = '1' then
        i := to_integer(unsigned(z_fa(7 downto 2)));
        z_dat(i) <= q_sd32; z_tag(i) <= z_fa(22 downto 8); z_val(i) <= '1';
        z_enche <= '0';
      end if;
      z_wv <= '0';
      if z_acc = '1' then
        z_fa <= m_sd_a; z_enche <= not m_sd_we;
        if m_sd_we = '1' then z_wv <= '1'; z_wa <= m_sd_a; z_wd <= do_cpu; end if;
      end if;
      if z_wv = '1' then
        i := to_integer(unsigned(z_wa(7 downto 2)));
        if z_val(i) = '1' and z_tag(i) = z_wa(22 downto 8) then
          w := z_dat(i); b := to_integer(unsigned(z_wa(1 downto 0)));
          w(b*8 + 7 downto b*8) := z_wd;
          z_dat(i) <= w;
        end if;
      end if;
      -- escrita do ESP na SDRAM: a linha da cache desse endereco deixa de valer
      if e_acc = '1' then z_val(to_integer(unsigned(esp_wa(7 downto 2)))) <= '0'; end if;
    end if;
  end process;
  -- v3c: no acerto o byte da cache vai logo para o barramento (no mesmo ciclo em que o WAIT se
  -- liberta); antes ia para o q_m um ciclo depois e, num T de 3 ciclos, o Z80 lia o byte anterior
  q_mz <= z_byte_r when z_ler = '1' else q_m;
  ce_t <= ce and cpu_wait_n;
  dv_lento <= dv_romcs;
  eb_io <= '1' when iorq_n = '0' and m1_n = '1' and a(7 downto 0) = x"EB" else '0';
  e7_io <= '1' when iorq_n = '0' and m1_n = '1' and a(7 downto 0) = x"E7" else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      eb_d <= eb_io;
      if eb_d = '1' and eb_io = '0' then spi_t <= 44;      -- acabou um IN/OUT a EBh: o SPI comeca agora
      elsif spi_t /= 0 then spi_t <= spi_t - 1; end if;
    end if;
  end process;
  -- (63) com o cartao no ESP, o Z80 fica parado no IN/OUT ao cartao ate' o ESP o largar (antes lia lixo a meio
  -- de um TRD e o esxDOS ficava sem cartao ate' ao reset); o resto do programa continua a correr
  cpu_wait_n <= '0' when sd_esp = '1' and (eb_io = '1' or e7_io = '1') else
                '0' when turbo = '1' and eb_io = '1' and spi_t /= 0 else
                '0' when turbo = '1' and m_acc = '1' and
                         not ((wr_n = '0' and feito = '1') or (wr_n = '1' and (m_lido = '1' or z_ler = '1'))) else '1';
  -- o GS so' entra com o Z80 sem pedido e longe do refresh forcado (o Z80 nunca espera
  -- mais do que um acesso do GS: ~8 ciclos, dentro da folga do ciclo de memoria)
  -- O Z80 so' tem o MREQ em baixo 1 T (o T80 le' o dado no fim do T1->T2): o GS so' comeca
  -- nos primeiros 4 ciclos de cada T do Z80; o acesso dele (~8 ciclos) acaba antes do T seguinte.
  -- (o GS acaba ~8 ciclos depois de comecar: com fase <= 6 esta' livre antes do T seguinte)
  -- camada do ESP (v2): rajadas de 8 palavras (~15 ciclos). A 3,5 MHz so' no inicio de um T sem pedido do
  -- Z80 (acaba antes do T seguinte, como os outros clientes); em turbo passa a' frente do Z80 (que espera)
  o_req    <= ol_req or ow_req;
  ow_off   <= to_unsigned(16#040000#, 23) when (ovl_wsep = '1' and ovl_widx = "01") or (ovl_wsep = '0' and ovl_sel = '1') else
              to_unsigned(16#100000#, 23) when ovl_wsep = '1' and ovl_widx(1) = '1' else (others => '0');
  o_vez    <= '1' when o_req = '1' and (m_sd_req = '0' or turbo = '1') and rf_t < 380 and fase < 2 else '0';
  o_acc    <= '1' when o_vez = '1' and sd_livre = '1' and sd_rf = '0' else '0';
  z_acc    <= '1' when m_sd_req = '1' and o_vez = '0' and sd_livre = '1' and sd_rf = '0' else '0';
  o_sa     <= std_logic_vector(ol_base + (ol_k & "00000")) when ol_req = '1' else std_logic_vector(ow_base + (ow_k & "00000"));
  v_vez    <= '1' when m_sd_req = '0' and o_vez = '0' and v_req = '1' and rf_t < 380 and fase < 7 else '0';
  g_vez    <= '1' when m_sd_req = '0' and o_vez = '0' and v_vez = '0' and g_req = '1' and rf_t < 380 and fase < 7 else '0';
  e_req    <= esp_wreq;
  -- (esp46) o som do ESP: uma palavra a cada amostra (~1 por 1200 ciclos), antes das escritas do ESP
  a_vez    <= '1' when m_sd_req = '0' and o_vez = '0' and v_vez = '0' and g_vez = '0' and a_req = '1' and rf_t < 380 and fase < 7 else '0';
  a_acc    <= '1' when a_vez = '1' and sd_livre = '1' and sd_rf = '0' else '0';
  a_sa     <= "11111" & std_logic_vector(a_i) & "00";
  mp_idx   <= std_logic_vector(a_i);
  mp_l <= std_logic_vector(mpl); mp_r <= std_logic_vector(mpr);
  e_vez    <= '1' when m_sd_req = '0' and o_vez = '0' and v_vez = '0' and g_vez = '0' and a_vez = '0' and e_req = '1' and rf_t < 380 and fase < 7 else '0';
  e_acc    <= '1' when e_vez = '1' and sd_livre = '1' and sd_rf = '0' else '0';
  esp_ack  <= e_vgo;
  esp_wack <= e_acc;
  sd_be    <= esp_wbe when e_vez = '1' else "0000";
  sd_req_t <= m_sd_req or o_vez or v_vez or g_vez or a_vez or e_vez;
  sd_a     <= o_sa when o_vez = '1' else m_sd_a when m_sd_req = '1' else v_sa when v_vez = '1' else a_sa when a_vez = '1' else esp_wa(22 downto 2) & "00" when e_vez = '1' else g_sa;
  sd_we_t  <= '0' when o_vez = '1' else m_sd_we when m_sd_req = '1' else '0' when v_vez = '1' else '0' when a_vez = '1' else '1' when e_vez = '1' else g_ok;
  sd_d     <= do_cpu when m_sd_req = '1' else esp_d when e_vez = '1' else g_sd;
  -- refresh so' pelo tempo (8192 por 64 ms = 1 a cada ~7,8 us = 421 ciclos): a partir dos 380
  -- ciclos numa vaga segura (Z80 sem pedido, inicio do T), aos 511 de qualquer maneira
  sd_rf  <= '1' when (rf_t >= 380 and m_sd_req = '0' and fase < 4) or rf_t = 511 else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if mreq_n = '1' then feito <= '0'; m_lido <= '0';
      elsif z_acc = '1' then feito <= '1'; end if;
      if mreq_n = '0' and z_ler = '1' and m_lido = '0' then m_lido <= '1'; q_m <= z_byte_r; end if;  -- acerto na cache
      -- cache: um pedido do Z80 que ainda esta' na SDRAM quando o acesso acaba (o acerto ja' o
      -- libertou) e' descartado ao chegar: nao toca no q_m nem no m_lido do acesso seguinte
      if mreq_n = '1' and z_voo = '1' and turbo = '1' then z_desc <= '1'; end if;   -- a 3,5 MHz como antes
      -- dono do acesso em curso e o dado de cada um (o q da SDRAM so' fica ate' ao pedido seguinte)
      livre_d <= sd_livre;
      if ce = '1' then fase <= 0; elsif fase /= 63 then fase <= fase + 1; end if;
      -- o acesso acabou (a SDRAM voltou a ficar livre): guarda o dado de quem o pediu.
      -- Pode ser no mesmo ciclo em que a SDRAM aceita o pedido seguinte: os dois ifs sao
      -- independentes (o pend do pedido novo ganha, o dono antigo e' o que conta aqui).
      g_fim <= '0'; v_fim <= '0'; lb_we_r <= '0'; a_fim <= '0';
      -- (esp46) o relogio das amostras do ESP: mp_rate por segundo (54 MHz)
      if mp_on = '0' then
        a_acc_c <= (others => '0'); a_i <= (others => '0'); a_req <= '0'; a_voo <= '0';
        mpl <= (others => '0'); mpr <= (others => '0'); mp_fw <= (others => '0'); mp_fr <= (others => '0');
      else
        -- tocar: a cada tique sai a amostra seguinte da fila (se a fila estiver vazia fica a anterior)
        if a_acc_c + unsigned(mp_rate) >= 54000000 then
          a_acc_c <= a_acc_c + unsigned(mp_rate) - 54000000;
          if mp_fw /= mp_fr then
            mpl <= signed(mpf(to_integer(mp_fr(3 downto 0)))(15 downto 0));
            mpr <= signed(mpf(to_integer(mp_fr(3 downto 0)))(31 downto 16));
            mp_fr <= mp_fr + 1;
          end if;
        else
          a_acc_c <= a_acc_c + unsigned(mp_rate);
        end if;
        -- ler: enquanto houver lugar na fila, uma palavra de cada vez
        if a_acc = '1' then a_req <= '0'; a_voo <= '1'; a_i <= a_i + 1;
        elsif a_voo = '0' and a_req = '0' and (mp_fw - mp_fr) < 14 then a_req <= '1'; end if;
        if a_fim = '1' then a_voo <= '0'; end if;
      end if;
      -- palavras das rajadas da camada (so' a camada usa rajadas) para o buffer de linhas
      if sd_qr_v = '1' then
        lb_d_r <= sd_qr; lb_we_r <= '1';
        if f_w = '1' then lb_a_r <= '1' & std_logic_vector(f_k) & std_logic_vector(sd_qr_i);
        else lb_a_r <= '0' & f_half & std_logic_vector(f_k(3 downto 0)) & std_logic_vector(sd_qr_i); end if;
      end if;
      if pend = '1' and sd_livre = '1' and livre_d = '0' then
        pend <= '0';
        case dono2 is
          when "000"  =>
            z_voo <= '0'; z_desc <= '0';
            if z_desc = '0' and not (turbo = '1' and mreq_n = '1' and z_voo = '1') then q_m <= q_sd; m_lido <= '1'; end if;
          when "010"  => q_v <= q_sd; v_fim <= '1';
          when "011"  => null;                                   -- escrita do ESP: nada a guardar
          when "101"  =>                                       -- (esp46/48) som do ESP: para a fila
            if mp_on = '1' then mpf(to_integer(mp_fw(3 downto 0))) <= q_sd32; mp_fw <= mp_fw + 1; end if;
            a_fim <= '1';
          when "100"  => null;                                   -- rajada da camada: as palavras ja' foram
          when others => q_g <= q_sd; q_g32 <= q_sd32; g_fim <= '1';
        end case;
      end if;
      if sd_req_t = '1' and sd_livre = '1' and sd_rf = '0' then
        pend <= '1';
        if o_vez = '1' then dono2 <= "100"; elsif m_sd_req = '1' then dono2 <= "000"; z_voo <= '1';
        elsif v_vez = '1' then dono2 <= "010"; elsif a_vez = '1' then dono2 <= "101"; elsif e_vez = '1' then dono2 <= "011"; else dono2 <= "001"; end if;
      end if;
      if sd_rf = '1' and sd_livre = '1' then rf_t <= (others => '0');
      elsif rf_t /= 511 then rf_t <= rf_t + 1; end if;
    end if;
  end process;

  -- camada do ESP (v2): os pedidos vem do relogio do HDMI (mudam de valor); a linha fica estavel ate' ao
  -- pedido seguinte. Primeiro a camada L (prazo mais curto), depois a janela. Um pedido novo recomeca.
  process(clk)
  begin
    if rising_edge(clk) then
      ol_s <= ol_s(1 downto 0) & ovl_pede_l;
      ow_s <= ow_s(1 downto 0) & ovl_pede_w;
      ow16_s <= ow16_s(0) & ovl_w16;
      if o_acc = '1' then
        if ol_req = '1' then
          f_w <= '0'; f_half <= ol_lin(0); f_k <= '0' & ol_k;
          if ol_k = 9 then ol_req <= '0'; else ol_k <= ol_k + 1; end if;
        else
          f_w <= '1'; f_k <= ow_k;
          if ow_k = ow_ult then ow_req <= '0'; else ow_k <= ow_k + 1; end if;
        end if;
      end if;
      if ol_s(2) /= ol_s(1) then
        ol_lin <= unsigned(ovl_lin_l);
        -- 600000h (ou 640000h) + linha x 320
        ol_base <= to_unsigned(16#600000#, 23) + (unsigned'("0000") & ovl_sel & "000000000000000000")
                   + (unsigned'("00000") & unsigned(ovl_lin_l) & "00000000") + (unsigned'("0000000") & unsigned(ovl_lin_l) & "000000");
        ol_k <= (others => '0'); ol_req <= '1';
      end if;
      if ow_s(2) /= ow_s(1) then
        -- 680000h (ou 6C0000h) + linha x 1024 (a 16 bits: linha x 512, so' 16 rajadas)
        if ow16_s(1) = '1' then
          ow_base <= to_unsigned(16#680000#, 23) + ow_off
                     + (unsigned'("000000") & unsigned(ovl_lin_w) & "000000000");
          ow_ult <= to_unsigned(15, 5);
        else
          ow_base <= to_unsigned(16#680000#, 23) + ow_off
                     + (unsigned'("00000") & unsigned(ovl_lin_w) & "0000000000");
          ow_ult <= to_unsigned(31, 5);
        end if;
        ow_k <= (others => '0'); ow_req <= '1';
      end if;
    end if;
  end process;
  lb_we <= lb_we_r; lb_a <= lb_a_r; lb_d <= lb_d_r;

  sdr: entity work.sdram
    port map (clk => clk, pronta => sd_ok, teste_ok => sd_teste, teste_ok2 => sd_teste2, req => sd_req_t, we => sd_we_t,
              a => sd_a, d => sd_d, d32 => esp_wd, be => sd_be, q => q_sd, q32 => q_sd32, rf => sd_rf, livre => sd_livre,
              rajada => o_vez, qr => sd_qr, qr_v => sd_qr_v, qr_i => sd_qr_i,
              sd_clk => sd_clk, sd_cke => sd_cke, sd_cs_n => sd_cs_n, sd_ras_n => sd_ras_n,
              sd_cas_n => sd_cas_n, sd_we_n => sd_we_n, sd_ba => sd_ba, sd_addr => sd_addr,
              sd_dqm => sd_dqm, sd_dq_i => sd_dq_i, sd_dq_o => sd_dq_o, sd_dq_oe => sd_dq_oe);
  pronta <= sd_ok;

  -- as ROM/RAM de bloco dao o dado 1 ciclo depois do endereco
  process(clk)
  begin
    if rising_edge(clk) then
      a_l <= a; big_l <= big; home_l <= home; vram_l <= vram; interna_l <= interna;
      dv_ee_l <= not dv_ee_n; dv_oe_l <= not dv_oe_n; dv_romcs_l <= dv_romcs;
    end if;
  end process;

  -- teclado: filas com A8-A15 a 0, 0 = carregada
  process(a, mat)
    variable v : std_logic_vector(4 downto 0);
  begin
    v := (others => '0');
    for f in 0 to 7 loop
      if a(8 + f) = '0' then v := v or mat(f*5 + 4 downto f*5); end if;
    end loop;
    teclas <= not v;
  end process;

  -- leituras do Z80
  process(all)
  begin
    if iorq_n = '0' and m1_n = '0' then
      di <= x"FF";                                     -- aceitacao da INT
    elsif iorq_n = '0' then
      if ua_cs = '1' then di <= ua_q;                  -- UART do ZX-UNO (C6/C7), pelo ESP
      elsif dv_oe = '1' then di <= dv_q;               -- DivTIESUS: EB (SPI), FD3B (registo DF)
      elsif mb_cs = '1' then di <= mb_q;               -- caixa de correio do ESP (EE3B / EF3B)
      elsif u_porta = '1' then di <= u_q;              -- ULAplus
      elsif gs_cs_rd = '1' then di <= gs_q;             -- General Sound
      elsif ay_le = '1' then di <= ay_qm;              -- AY 1 (F6) ou o AY do FFFD
      else
        case a(7 downto 0) is
          when x"FE" => di <= '1' & ear_in & '1' & teclas;          -- (2026-10-23) bits 7 e 5 a 1, EAR (6) a 0: BF sem teclas, como no 48K
          when x"FF" => if regf3(5) = '1' then di <= fl_byte; else di <= regff; end if;   -- (esp59) barramento flutuante
          when x"F4" => di <= banksel;
          when x"CF" => di <= sid_q;                   -- SID (ZX-TSid)
          when x"1F" => di <= joy;                     -- Kempston (comando USB / Xbox)
          -- rato Kempston: FBDF = X, FFDF = Y, FADF = botoes (0 = carregado: bit 0 direito, 1 esquerdo, 2 meio)
          when x"DF" =>
            if a(15 downto 8) = x"FB" then di <= rato_x;
            elsif a(15 downto 8) = x"FF" then di <= rato_y;
            elsif a(15 downto 8) = x"FA" then di <= "11111" & not rato_b(2) & not rato_b(0) & not rato_b(1);
            else di <= x"FF"; end if;
          when others => di <= x"FF";
        end case;
      end if;
    elsif big_l = '1' then
      di <= q_mz;                                     -- Pentagon 1024: bancos de C000h
    elsif dv_oe_l = '1' then
      di <= q_mz;                                     -- SRAM da DivTIESUS (RAM do DivMMC, bancos, ROM em RAM)
    elsif dv_ee_l = '1' then
      di <= q_esx;                                     -- EEPROM (esxDOS)
    elsif a_l(15 downto 14) = "00" then
      if dv_romcs_l = '1' then di <= x"FF";            -- a DivTIESUS calou a ROM e nao serve nada
      elsif home_l = '1' then di <= q_rom;             -- HOME
      else di <= x"FF"; end if;                        -- DOCK / EXROM: o Timextenso nao tem
    elsif vram_l = '1' then
      di <= q_scr;
    elsif interna_l = '1' then
      di <= q_mz;
    else
      di <= x"FF";
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Dois AY (Tang: sem 245 nem esperas), sem se atropelarem:
  --   AY 1 = o do Timex: F5 (registo) / F6 (dado), sempre;
  --   AY 2 = o do 128: FFFD (registo, A15 = 1, A14 = 1, A1 = 0) / BFFD (dado, A15 = 1, A14 = 0).
  --   TurboSound: OUT FFFD,FE passa o FFFD/BFFD para o AY 1; OUT FFFD,FF volta ao AY 2 (o normal);
  --   OUT FFFD,FD para o AY 3 (como o TurboSound Next do ZX Next; so' entra na mistura depois de escolhido).
  --   F5 e F4 (tambem com o A1 a 0) nunca contam como FFFD: OUT (C) com BC = FFF4 e' o HSR.
  p_sel <= '1' when a(15 downto 14) = "11" and a(1) = '0' and a(7 downto 0) /= x"F5" and a(7 downto 0) /= x"F4" else '0';
  p_dat <= '1' when a(15 downto 14) = "10" and a(1) = '0' else '0';
  -- (o FD so' com a placa do 3.o AY ligada; sem ela e' um OUT normal para o AY 2, como antes)
  ts_cmd <= '1' when io_wr = '1' and p_sel = '1' and do_cpu(7 downto 2) = "111111" and
                     (do_cpu(1) = '1' or (do_cpu(1 downto 0) = "01" and ay3_lig = '1')) else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_n_i = '0' or (ay3_lig = '0' and ts = "10") then ts <= "00"; ay3_on <= '0';
      elsif ts_cmd = '1' then
        case do_cpu(1 downto 0) is
          when "11"   => ts <= "00";                                -- FF -> AY 2
          when "10"   => ts <= "01";                                -- FE -> AY 1
          when others => ts <= "10"; ay3_on <= '1';                 -- FD -> AY 3
        end case;
      end if;
    end if;
  end process;
  ay_sel  <= '1' when io_wr = '1' and (a(7 downto 0) = x"F5" or (p_sel = '1' and ts = "01" and ts_cmd = '0')) else '0';
  ay_we   <= '1' when io_wr = '1' and (a(7 downto 0) = x"F6" or (p_dat = '1' and ts = "01")) else '0';
  ay2_sel <= '1' when io_wr = '1' and p_sel = '1' and ts = "00" and ts_cmd = '0' else '0';
  ay2_we  <= '1' when io_wr = '1' and p_dat = '1' and ts = "00" else '0';
  ay3_sel <= '1' when io_wr = '1' and p_sel = '1' and ts = "10" and ts_cmd = '0' else '0';
  ay3_we  <= '1' when io_wr = '1' and p_dat = '1' and ts = "10" else '0';
  ay_le   <= '1' when io_rd = '1' and (a(7 downto 0) = x"F6" or p_sel = '1') else '0';
  ay_qm   <= ay2_q when p_sel = '1' and ts = "00" and a(7 downto 0) /= x"F6" else
             ay3_q when p_sel = '1' and ts = "10" and a(7 downto 0) /= x"F6" else ay_q;
  process(clk)
  begin
    if rising_edge(clk) then
      ay_en <= '0';
      if ce35 = '1' then ay_meio <= not ay_meio; ay_en <= ay_meio; end if;
    end if;
  end process;
  -- (2026-10-24) copia dos registos 0-5 (periodos) e 8-10 (volumes) dos AY 1 e 2, para o ESP desenhar barras
  process(clk)
  begin
    if rising_edge(clk) then
      if ay_sel = '1' then ay1_r <= unsigned(do_cpu(3 downto 0)); end if;
      if ay_we = '1' and ay1_r < 11 then ayc1(to_integer(ay1_r)) <= do_cpu; end if;
      if ay2_sel = '1' then ay2_r <= unsigned(do_cpu(3 downto 0)); end if;
      if ay2_we = '1' and ay2_r < 11 then ayc2(to_integer(ay2_r)) <= do_cpu; end if;
      if ay3_sel = '1' then ay3_r <= unsigned(do_cpu(3 downto 0)); end if;
      if ay3_we = '1' and ay3_r < 11 then ayc3(to_integer(ay3_r)) <= do_cpu; end if;
    end if;
  end process;
  process(clk)
    variable v : std_logic_vector(71 downto 0);
  begin
    if rising_edge(clk) then
      if ay3_on = '1' and ay3_lig = '1' then v := ay3_c & ay3_b & ay3_a & ay2_c & ay2_b & ay2_a & ay_c & ay_b & ay_a;
      else v := x"000000" & ay2_c & ay2_b & ay2_a & ay_c & ay_b & ay_a; end if;
      if pico_t20 = 1079999 then
        pico_t20 <= 0; pico <= pico_m; pico_m <= v;
      else
        pico_t20 <= pico_t20 + 1;
        for i in 0 to 8 loop
          if unsigned(v(i * 8 + 7 downto i * 8)) > unsigned(pico_m(i * 8 + 7 downto i * 8)) then
            pico_m(i * 8 + 7 downto i * 8) <= v(i * 8 + 7 downto i * 8);
          end if;
        end loop;
      end if;
    end if;
  end process;
  -- 8 bytes por AY: A baixo, B baixo, C baixo, A alto | B alto << 4, C alto, nivel A, B, C (0-255, o real)
  ay_vis <= pico(71 downto 48) & "0000" & ayc3(5)(3 downto 0) & ayc3(3)(3 downto 0) & ayc3(1)(3 downto 0) & ayc3(4) & ayc3(2) & ayc3(0) &
            pico(47 downto 24) & "0000" & ayc2(5)(3 downto 0) & ayc2(3)(3 downto 0) & ayc2(1)(3 downto 0) & ayc2(4) & ayc2(2) & ayc2(0) &
            pico(23 downto 0) & "0000" & ayc1(5)(3 downto 0) & ayc1(3)(3 downto 0) & ayc1(1)(3 downto 0) & ayc1(4) & ayc1(2) & ayc1(0);
  ay: entity work.YM2149
    port map (CLK => clk, ENA => ay_en, RESET_H => not rst_n_i, I_SEL_L => '1',
              I_DA => do_cpu, O_DA => ay_q, I_REG => '0',
              busctrl_addr => ay_sel, busctrl_we => ay_we, ctrl_aymode => '1',
              port_a_i => (others => '1'), port_a_o => open, port_b_i => (others => '1'), port_b_o => open,
              O_AUDIO_A => ay_a, O_AUDIO_B => ay_b, O_AUDIO_C => ay_c);
  ay2: entity work.YM2149
    port map (CLK => clk, ENA => ay_en, RESET_H => not rst_n_i, I_SEL_L => '1',
              I_DA => do_cpu, O_DA => ay2_q, I_REG => '0',
              busctrl_addr => ay2_sel, busctrl_we => ay2_we, ctrl_aymode => '1',
              port_a_i => (others => '1'), port_a_o => open, port_b_i => (others => '1'), port_b_o => open,
              O_AUDIO_A => ay2_a, O_AUDIO_B => ay2_b, O_AUDIO_C => ay2_c);
  ay3: entity work.YM2149
    port map (CLK => clk, ENA => ay_en, RESET_H => not rst_n_i, I_SEL_L => '1',
              I_DA => do_cpu, O_DA => ay3_q, I_REG => '0',
              busctrl_addr => ay3_sel, busctrl_we => ay3_we, ctrl_aymode => '1',
              port_a_i => (others => '1'), port_a_o => open, port_b_i => (others => '1'), port_b_o => open,
              O_AUDIO_A => ay3_a, O_AUDIO_B => ay3_b, O_AUDIO_C => ay3_c);
  -- SID: relogio de 1 MHz (54 MHz / 54), dois 8580
  process(clk)
  begin
    if rising_edge(clk) then
      sid_ce <= '0';
      if sid_div = 53 then sid_div <= 0; sid_ce <= '1'; else sid_div <= sid_div + 1; end if;
      if rst_n_i = '0' then sid_on <= '0';
      elsif sid_cs /= "00" and io_wr = '1' then sid_on <= '1'; end if;     -- so' entra na mistura depois de usado
    end if;
  end process;
  sid_cs(0) <= '1' when (io_rd = '1' or io_wr = '1') and a(7 downto 0) = x"CF" and a(13) = '0' else '0';
  sid_cs(1) <= '1' when (io_rd = '1' or io_wr = '1') and a(7 downto 0) = x"CF" and a(13) = '1' else '0';
  sid_rst <= not rst_n_i;
  g_sid: if COM_SID generate
    sid: sid_timextenso port map (clk => clk, reset => sid_rst, ce_1m => sid_ce, cs => sid_cs, we => io_wr,
                             addr => a(12 downto 8), din => do_cpu, dout => sid_q, mode => "11",
                             audio_l => sid_l, audio_r => sid_r);
  end generate;
  g_semsid: if not COM_SID generate
    sid_q <= x"FF"; sid_l <= (others => '0'); sid_r <= (others => '0');
  end generate;

  -- som: ABC nos dois AY (A e metade do B a' esquerda, C e metade do B a' direita), mais o beeper
  process(clk)
    variable l, r : unsigned(10 downto 0);
    variable gl, gr : unsigned(14 downto 0);
    variable sl, sr : signed(17 downto 0);
  begin
    if rising_edge(clk) then
      l := ("000" & unsigned(ay_a)) + ("0000" & unsigned(ay_b(7 downto 1))) +
           ("000" & unsigned(ay2_a)) + ("0000" & unsigned(ay2_b(7 downto 1)));
      r := ("000" & unsigned(ay_c)) + ("0000" & unsigned(ay_b(7 downto 1))) +
           ("000" & unsigned(ay2_c)) + ("0000" & unsigned(ay2_b(7 downto 1)));
      if ay3_on = '1' and ay3_lig = '1' then
        l := l + ("000" & unsigned(ay3_a)) + ("0000" & unsigned(ay3_b(7 downto 1)));
        r := r + ("000" & unsigned(ay3_c)) + ("0000" & unsigned(ay3_b(7 downto 1)));
      end if;
      if beep = '1' then l := l + 128; r := r + 128; end if;
      if ear_in = '1' then l := l + 64; r := r + 64; end if;      -- a cassete ouve-se (mais baixo que o beeper)
      -- 14 bits: AY + beeper (0..892) x 8, mais o General Sound (+-16128 / 4) a' volta de 4096
      if gs_rst = '1' and sid_on = '0' and (ay3_on = '0' or ay3_lig = '0') then
        -- GS parado e SID por usar: o AY e o beeper com o volume todo (x 16), como antes do GS
        sl := shift_left(signed(resize(l, 18)), 4);
        sr := shift_left(signed(resize(r, 18)), 4);
      else
        sl := shift_left(signed(resize(l, 18)), 3) + 4096 + shift_right(signed(sid_l), 5);
        sr := shift_left(signed(resize(r, 18)), 3) + 4096 + shift_right(signed(sid_r), 5);
        if gs_rst = '0' then
          sl := sl + resize(shift_right(gs_l, 2), 18);
          sr := sr + resize(shift_right(gs_r, 2), 18);
        end if;
      end if;
      if sl < 0 then sl := (others => '0'); elsif sl > 16383 then sl := to_signed(16383, 18); end if;
      if sr < 0 then sr := (others => '0'); elsif sr > 16383 then sr := to_signed(16383, 18); end if;
      gl := unsigned(sl(14 downto 0));
      gr := unsigned(sr(14 downto 0));
      aud_l <= "00" & std_logic_vector(gl(13 downto 0));
      aud_r <= "00" & std_logic_vector(gr(13 downto 0));
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- General Sound (todas as maquinas): portas xxBB (comando/estado) e xxB3 (dados).
  -- Memoria do GS na SDRAM a partir de 4 MB (512K: pagina 0 = ROM, 1-15 = RAM).
  -- ROM pelo ZX-UNO (como o .gs): A0h bit 0 = 1 para o GS (e poe o ponteiro a 0),
  -- A1h = byte seguinte da ROM (32K), A0h = 0 arranca-o. Ao ligar fica parado.
  process(clk)
  begin
    if rising_edge(clk) then
      io_wr_d <= io_wr;
      -- 2026-10-24: as saidas de memoria do Z80 do GS passam por um registo (timing do clk54);
      -- o Z80 do GS so' anda de 2 em 2 ciclos, por isso o pedido continua a tempo
      gs_ma <= gs_ma_c; gs_md <= gs_md_c; gs_rd <= gs_rd_c; gs_wr <= gs_wr_c;
      gs_cnt <= gs_cnt + 1;
      gs_ce <= not gs_cnt(0);                                          -- 27 MHz, como o MiSTer (28): as esperas
                                                                       -- da SDRAM deixam-no perto dos 12 MHz do GS
      if io_wr = '1' and io_wr_d = '0' and a = x"FD3B" then
        if zx_reg = x"A0" then gs_lp <= (others => '0'); end if;
        if zx_reg = x"A1" and gs_rst = '1' then ld_pend <= '1'; ld_d <= do_cpu; end if;
      end if;
      if ld_pend = '1' and g_vez = '1' and sd_livre = '1' and sd_rf = '0' then
        ld_pend <= '0'; gs_lp <= gs_lp + 1;
      end if;
      -- acessos do Z80 do GS: um pedido por acesso; acabado quando o dado chega
      if gs_acc = '0' then g_feito <= '0'; g_emcurso <= '0';
      elsif gs_rst = '0' and g_emcurso = '0' and g_feito = '0' and g_vez = '1' and sd_livre = '1' and sd_rf = '0' then
        g_emcurso <= '1';
      elsif g_emcurso = '1' and g_fim = '1' then
        g_emcurso <= '0'; g_feito <= '1';
      end if;
    end if;
  end process;
  -- GS 512 (como o original): so' as paginas 0-15; as outras leem FFh, sem esperar
  gs_alto <= '1' when gs_ma(20 downto 19) /= "00" else '0';
  gs_acc  <= (gs_rd or gs_wr) and not gs_alto;
  -- cache: indice A7-A2, etiqueta A18-A8 (512K); uma leitura que acerta nao vai a' SDRAM
  c_idx  <= to_integer(unsigned(gs_ma(7 downto 2)));
  c_hit  <= '1' when c_val(c_idx) = '1' and c_tag(c_idx) = gs_ma(18 downto 8) else '0';
  c_ler  <= gs_rd and not gs_alto and c_hit;
  with gs_ma(1 downto 0) select c_byte <=
    c_dat(c_idx)(7 downto 0)   when "00",
    c_dat(c_idx)(15 downto 8)  when "01",
    c_dat(c_idx)(23 downto 16) when "10",
    c_dat(c_idx)(31 downto 24) when others;
  gs_wait <= gs_acc and not g_feito and not c_ler;
  g_req   <= ld_pend when gs_rst = '1' else (gs_acc and not g_feito and not g_emcurso and not c_ler);
  process(clk)
    variable w : std_logic_vector(31 downto 0);
    variable b : integer range 0 to 3;
  begin
    if rising_edge(clk) then
      if gs_rst = '1' then
        c_val <= (others => '0');                         -- ROM nova: cache vazia
      elsif g_emcurso = '1' and g_fim = '1' then
        if gs_rd = '1' then                               -- leitura da SDRAM: enche a linha
          c_dat(c_idx) <= q_g32; c_tag(c_idx) <= gs_ma(18 downto 8); c_val(c_idx) <= '1';
        elsif gs_wr = '1' and c_hit = '1' then            -- escrita: actualiza o byte na linha
          w := c_dat(c_idx); b := to_integer(unsigned(gs_ma(1 downto 0)));
          w(b*8 + 7 downto b*8) := gs_md;
          c_dat(c_idx) <= w;
        end if;
      end if;
    end if;
  end process;
  g_ok    <= '1' when gs_rst = '1' else gs_wr;
  g_sa    <= "10" & "000000" & std_logic_vector(gs_lp) when gs_rst = '1' else "10" & gs_ma;
  g_sd    <= ld_d when gs_rst = '1' else gs_md;
  gs_mq <= x"FF" when gs_alto = '1' else c_byte when c_ler = '1' else q_g;
  gs_cs_rd <= '1' when io_rd = '1' and (a(7 downto 0) = x"BB" or a(7 downto 0) = x"B3") else '0';
  gs_cs_wr <= '1' when io_wr = '1' and (a(7 downto 0) = x"BB" or a(7 downto 0) = x"B3") else '0';
  gsnd: entity work.gs
    port map (clk => clk, reset_n => rst_n_i and not gs_rst, ce => gs_ce,
              cs_rd => gs_cs_rd, cs_wr => gs_cs_wr, a3 => a(3), din => do_cpu, dout => gs_q,
              m_a => gs_ma_c, m_rd => gs_rd_c, m_wr => gs_wr_c, m_d => gs_md_c, m_q => gs_mq, m_wait => gs_wait,
              out_l => gs_l, out_r => gs_r);

  ---------------------------------------------------------------------------
  -- quadro e INT: 48K 69888 T (INT 32 T); 128K 70908 T (228 x 311, INT 36 T);
  -- Pentagon 71680 T (224 x 320, INT 36 T). FF bit 6 desliga a INT.
  tfim <= 71679 when penta = '1' else 70907 when t128 = '1' else 69887;
  tint <= 36 when penta = '1' or t128 = '1' else 32;
  process(clk)
  begin
    if rising_edge(clk) then
      if ce35 = '1' then
        if tcnt >= tfim then tcnt <= 0; else tcnt <= tcnt + 1; end if;
        if tcnt < tint and regff(6) = '0' then int_n <= '0'; else int_n <= '1'; end if;
      end if;
    end if;
  end process;

  ulp: entity work.ulaplus
    port map (clk => clk, reset_n => rst_n_i, a => a, d => do_cpu,
              iorq_n => iorq_n, rd_n => rd_n, wr_n => wr_n, m1_n => m1_n,
              e_porta => u_porta, q_porta => u_q,
              pal_a => pal_a, pal_we => pal_we, pal_d => pal_d, pal_q => pal_q, ligado => ulap);
end architecture;
