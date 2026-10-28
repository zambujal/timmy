-- sdram.vhd: controlador simples da SDRAM de dentro do GW2AR-18 (64 Mbit, 32 bits:
-- 4 bancos x 2048 linhas x 256 colunas). Um byte de cada vez, com auto-precarga.
-- Relogio de 54 MHz (18,5 ns); a SDRAM recebe o relogio invertido (amostra a meio do ciclo).
--   leitura : ACT, NOP, READ(AP), NOP, NOP, dado 3 ciclos depois do READ (CL = 2)
--   escrita : ACT, NOP, WRITE(AP), 3 x NOP
--   refresh : REF, 6 x NOP
--   rajada (2026-10-22, so' leitura, para o video): ACT, NOP, 8 x READ seguidos (c..c+7, o ultimo
--     com auto-precarga), cada palavra sai em qr com qr_v = 1 e o indice em qr_i.
--     O endereco tem de estar alinhado a 32 bytes (8 palavras na mesma linha da SDRAM). ~16 ciclos.
-- Endereco de byte de 23 bits: banco = a(22:21), linha = a(20:10), coluna = a(9:2),
-- byte dentro da palavra = a(1:0) (DQM escolhe o byte na escrita).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram is
  port (
    clk     : in  std_logic;                      -- 54 MHz
    pronta  : out std_logic;                      -- 1 depois da inicializacao e do teste
    teste_ok : out std_logic;                     -- 1 = o teste do arranque (16 bytes em palavras diferentes) passou
    teste_ok2 : out std_logic;                    -- 1 = 4 bytes seguidos na mesma palavra (DQM) passaram
    -- pedido (amostrado com req = 1 e livre = 1)
    req     : in  std_logic;
    we      : in  std_logic;
    a       : in  std_logic_vector(22 downto 0);
    d       : in  std_logic_vector(7 downto 0);
    d32     : in  std_logic_vector(31 downto 0) := (others => '0');   -- (esp43) escrita de palavra: os bytes de be
    be      : in  std_logic_vector(3 downto 0) := "0000";           -- 0000 = escrita de um byte (d), como antes
    q       : out std_logic_vector(7 downto 0);   -- fica ate' ao pedido seguinte
    q32     : out std_logic_vector(31 downto 0);  -- a palavra inteira da ultima leitura (cache do GS)
    rf      : in  std_logic;                      -- pedido de refresh
    rajada  : in  std_logic := '0';               -- com req (e we = 0): le' 8 palavras seguidas
    qr      : out std_logic_vector(31 downto 0);  -- palavra da rajada
    qr_v    : out std_logic;                      -- 1 = qr tem a palavra qr_i
    qr_i    : out unsigned(2 downto 0);
    livre   : out std_logic;
    -- pinos (nomes que o apicula liga 'a SDRAM de dentro)
    sd_clk   : out std_logic;
    sd_cke   : out std_logic;
    sd_cs_n  : out std_logic;
    sd_ras_n : out std_logic;
    sd_cas_n : out std_logic;
    sd_we_n  : out std_logic;
    sd_ba    : out std_logic_vector(1 downto 0);
    sd_addr  : out std_logic_vector(10 downto 0);
    sd_dqm   : out std_logic_vector(3 downto 0);
    -- dados: o buffer de 3 estados (IOBUF) fica no top (o yosys perdia o inout)
    sd_dq_i  : in  std_logic_vector(31 downto 0);
    sd_dq_o  : out std_logic_vector(31 downto 0);
    sd_dq_oe : out std_logic
  );
end entity;

architecture rtl of sdram is
  -- comandos (cs ras cas we)
  constant C_NOP  : std_logic_vector(3 downto 0) := "0111";
  constant C_ACT  : std_logic_vector(3 downto 0) := "0011";
  constant C_RD   : std_logic_vector(3 downto 0) := "0101";
  constant C_WR   : std_logic_vector(3 downto 0) := "0100";
  constant C_PRE  : std_logic_vector(3 downto 0) := "0010";
  constant C_REF  : std_logic_vector(3 downto 0) := "0001";
  constant C_MRS  : std_logic_vector(3 downto 0) := "0000";

  type est_t is (INI_ESPERA, INI_PRE, INI_REF, INI_MRS, LIVRE_E, CMD, ESPERA);
  signal est : est_t := INI_ESPERA;
  signal cnt : unsigned(15 downto 0) := (others => '0');
  signal nref : integer range 0 to 15 := 0;
  signal cmd_r : std_logic_vector(3 downto 0) := C_NOP;
  signal ba_r : std_logic_vector(1 downto 0) := "00";
  signal addr_r : std_logic_vector(10 downto 0) := (others => '0');
  signal dqm_r : std_logic_vector(3 downto 0) := "1111";
  signal dq_o : std_logic_vector(31 downto 0) := (others => '0');
  signal dq_oe : std_logic := '0';
  signal q_r : std_logic_vector(7 downto 0) := (others => '0');
  signal q32_r : std_logic_vector(31 downto 0) := (others => '0');
  signal pronta_r, livre_r : std_logic := '0';
  -- pedido em curso
  signal p_we : std_logic := '0';
  signal p_a : std_logic_vector(22 downto 0) := (others => '0');
  signal p_d : std_logic_vector(7 downto 0) := (others => '0');
  signal p_d32 : std_logic_vector(31 downto 0) := (others => '0');
  signal p_be : std_logic_vector(3 downto 0) := "0000";
  signal p_raj, qr_v_r : std_logic := '0';
  signal qr_r : std_logic_vector(31 downto 0) := (others => '0');
  signal qr_i_r : unsigned(2 downto 0) := (others => '0');
  signal passo : integer range 0 to 15 := 0;
  signal e_ref : std_logic := '0';
  signal dq_desc : std_logic_vector(31 downto 0) := (others => '0');
  -- teste do arranque
  signal bt : integer range 0 to 41 := 0;
  signal ok_r, ok2_r : std_logic := '1';
  -- depois do teste: apaga a RAM do DivMMC (512K desde 1 MB), palavra a palavra, para cada
  -- bitstream novo arrancar a frio (gravar a FPGA nao apaga a SDRAM; o esxDOS via la' restos)
  signal cl : unsigned(17 downto 0) := (others => '0');   -- bit 17 = acabou
  signal p_pal : std_logic := '0';                         -- escrita da palavra inteira (DQM 0000)
  type ta_t is array (0 to 19) of std_logic_vector(22 downto 0);
  type td_t is array (0 to 19) of std_logic_vector(7 downto 0);
  function fa return ta_t is
    variable r : ta_t; variable i4 : unsigned(3 downto 0);
  begin
    for i in 0 to 15 loop
      i4 := to_unsigned(i, 4);
      -- banco, linha, coluna e byte variam com i (inclui linhas altas, como a 1 MB)
      r(i) := std_logic_vector(i4(1 downto 0) & i4(3) & i4 & "101101" & i4(2 downto 0) & "01101" & i4(1 downto 0));
    end loop;
    -- 16-19: os 4 bytes da mesma palavra (endereco 1 MB + 40h + 0..3), como o Z80 escreve
    for i in 16 to 19 loop
      r(i) := std_logic_vector(to_unsigned(16#100040# + (i - 16), 23));
    end loop;
    return r;
  end function;
  function fd return td_t is
    variable r : td_t;
  begin
    for i in 0 to 19 loop r(i) := std_logic_vector(to_unsigned((i * 37 + 90) mod 256, 8)); end loop;
    return r;
  end function;
  constant ta : ta_t := fa;
  constant td : td_t := fd;
begin
  process(clk)
    variable byte : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      cmd_r <= C_NOP;
      dq_oe <= '0';
      qr_v_r <= '0';
      case est is
        -- 200 us depois de ligar (10800 ciclos; espera-se 2^14 = 303 us)
        when INI_ESPERA =>
          cnt <= cnt + 1;
          if cnt(14) = '1' then est <= INI_PRE; cnt <= (others => '0'); end if;
        when INI_PRE =>
          cmd_r <= C_PRE; addr_r(10) <= '1';         -- todos os bancos
          est <= INI_REF; nref <= 0; cnt <= (others => '0');
        when INI_REF =>
          cnt <= cnt + 1;
          if cnt = 7 then
            cnt <= (others => '0');
            if nref = 8 then
              est <= INI_MRS;
            else
              cmd_r <= C_REF; nref <= nref + 1;
            end if;
          end if;
        when INI_MRS =>
          cmd_r <= C_MRS; ba_r <= "00";
          -- burst 1, sequencial, CL 2, escrita simples
          addr_r <= "0" & "0" & "00" & "010" & "0" & "000";
          est <= ESPERA; passo <= 4; bt <= 0;
        when LIVRE_E =>
          if bt < 40 then
            -- teste do arranque: escreve 16 bytes (bancos, linhas, colunas e bytes
            -- diferentes) e le-os de volta; teste_ok fica a 0 se algum vier errado
            p_we <= '1' when bt < 20 else '0';
            p_a <= ta(bt mod 20); p_d <= td(bt mod 20); e_ref <= '0'; p_pal <= '0'; p_raj <= '0'; p_be <= "0000";
            cmd_r <= C_ACT; ba_r <= ta(bt mod 20)(22 downto 21); addr_r <= ta(bt mod 20)(20 downto 10);
            est <= CMD; passo <= 0; bt <= bt + 1;
          elsif bt = 40 and cl(17) = '0' then
            -- apagar: 131072 palavras de 32 bits (~17 ms, menos que os 64 ms do refresh)
            p_we <= '1'; p_pal <= '1'; p_d <= x"00"; e_ref <= '0'; p_raj <= '0'; p_be <= "0000";
            p_a <= "0010" & std_logic_vector(cl(16 downto 0)) & "00";
            cmd_r <= C_ACT; ba_r <= "00"; addr_r <= "10" & std_logic_vector(cl(16 downto 8));
            est <= CMD; passo <= 0; cl <= cl + 1;
          elsif bt = 40 then
            bt <= 41; pronta_r <= '1';
          elsif rf = '1' then
            cmd_r <= C_REF; e_ref <= '1';
            est <= ESPERA; passo <= 7;
          elsif req = '1' then
            p_we <= we; p_a <= a; p_d <= d; e_ref <= '0'; p_pal <= '0'; p_raj <= rajada and not we;
            p_d32 <= d32; p_be <= be;
            cmd_r <= C_ACT; ba_r <= a(22 downto 21); addr_r <= a(20 downto 10);
            est <= CMD; passo <= 0;
          end if;
        when CMD =>
          passo <= passo + 1;
          if p_raj = '1' then
            -- rajada: READ nas colunas c..c+7 nos passos 1-8 (o ultimo com auto-precarga).
            -- Em rajada cada palavra so' dura um ciclo no barramento e o flanco descendente ja'
            -- apanha a seguinte: a palavra do READ do passo p esta' em dq_desc no passo p+3
            -- (numa leitura simples e' p+4, porque o barramento a mantem). Dados nos passos 4-11.
            if passo >= 1 and passo <= 8 then
              cmd_r <= C_RD; dqm_r <= "0000"; ba_r <= p_a(22 downto 21);
              addr_r <= (others => '0');
              addr_r(7 downto 0) <= p_a(9 downto 5) & std_logic_vector(to_unsigned(passo - 1, 3));
              if passo = 8 then addr_r(10) <= '1'; end if;     -- auto-precarga no ultimo
            end if;
            if passo >= 4 and passo <= 11 then
              qr_r <= dq_desc; qr_v_r <= '1'; qr_i_r <= to_unsigned(passo - 4, 3);
            end if;
            if passo = 12 then est <= ESPERA; passo <= 0; end if;
          elsif passo = 1 then                         -- tRCD = 2 ciclos (37 ns)
            ba_r <= p_a(22 downto 21);
            addr_r <= "100" & p_a(9 downto 2);       -- A10 = auto-precarga
            if p_we = '1' then
              cmd_r <= C_WR;
              dq_o <= p_d & p_d & p_d & p_d; dq_oe <= '1';
              dqm_r <= "1111";
              dqm_r(to_integer(unsigned(p_a(1 downto 0)))) <= '0';
              if p_pal = '1' then dqm_r <= "0000"; end if;
              if p_be /= "0000" then dq_o <= p_d32; dqm_r <= not p_be; end if;   -- (esp43) palavra do ESP
              est <= ESPERA; passo <= 3;            -- tWR + tRP
            else
              cmd_r <= C_RD; dqm_r <= "0000";
            end if;
          elsif passo = 5 then
            -- CL 2, relogio da SDRAM a 180 graus (CLKOUTP do PLL): o dado e' valido mais
            -- ou menos entre 10 e 25 ns depois do 2.o flanco da SDRAM. Apanha-se no flanco
            -- descendente seguinte (dq_desc, a meio da janela) e usa-se aqui.
            case p_a(1 downto 0) is
              when "00"   => byte := dq_desc(7 downto 0);
              when "01"   => byte := dq_desc(15 downto 8);
              when "10"   => byte := dq_desc(23 downto 16);
              when others => byte := dq_desc(31 downto 24);
            end case;
            q_r <= byte; q32_r <= dq_desc;
            if bt >= 21 and bt <= 36 and byte /= p_d then ok_r <= '0'; end if;    -- teste 1
            if bt >= 37 and bt <= 40 and byte /= p_d then ok2_r <= '0'; end if;   -- teste 2 (DQM)
            est <= ESPERA; passo <= 0;
          end if;
        when ESPERA =>
          if passo = 0 then est <= LIVRE_E; else passo <= passo - 1; end if;
      end case;
    end if;
  end process;

  livre_r <= '1' when est = LIVRE_E and rf = '0' and req = '0' else '0';
  livre  <= '1' when est = LIVRE_E else '0';
  pronta <= pronta_r;
  teste_ok <= ok_r;
  teste_ok2 <= ok2_r;

  -- dados da SDRAM apanhados no flanco descendente
  process(clk)
  begin
    if falling_edge(clk) then dq_desc <= sd_dq_i; end if;
  end process;
  q <= q_r;
  q32 <= q32_r;
  qr <= qr_r; qr_v <= qr_v_r; qr_i <= qr_i_r;

  sd_clk   <= not clk;   -- nao usado: o top liga o relogio da SDRAM ao CLKOUTP do PLL (180 graus)
  sd_cke   <= '1';
  sd_cs_n  <= cmd_r(3);
  sd_ras_n <= cmd_r(2);
  sd_cas_n <= cmd_r(1);
  sd_we_n  <= cmd_r(0);
  sd_ba    <= ba_r;
  sd_addr  <= addr_r;
  sd_dqm   <= dqm_r;
  sd_dq_o  <= dq_o;
  sd_dq_oe <= dq_oe;
end architecture;
