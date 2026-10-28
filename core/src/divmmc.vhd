-- divmmc.vhd: DivMMC (esxDOS) para o core do Timmy na Tang Nano 20K.
--   Segue o divmmc_mcleod.v do DivTIESUS (Miguel Angel Rodriguez Jodar, GPL v3),
--   reescrito em VHDL e sincrono ao relogio do core (54 MHz).
--   Porta E3 (escrita): bit 7 CONMEM, bit 6 MAPRAM (so' liga), bits 5-0 pagina de 8K.
--   Porta E7 (escrita): bit 0 = /CS do cartao.
--   Porta EB (SPI a 3,4 MHz, uma transferencia leva 2,4 us): escrita envia um byte por SPI; leitura devolve o ultimo byte recebido
--     e envia FF (como no DivMMC).
--   Automapeamento no M1: 0000, 0008, 0038, 0066, 04C6, 0562 (depois do M1),
--     3D00-3DFF (logo), sai em 1FF8-1FFF (depois do M1). Jumper E fechado (EEPROM so' de leitura).
--   NMI do botao so' passa com o DivMMC desligado.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity divmmc is
  port (
    clk      : in  std_logic;
    reset_n  : in  std_logic;
    a        : in  std_logic_vector(15 downto 0);
    d        : in  std_logic_vector(7 downto 0);   -- dados do CPU
    mreq_n, iorq_n, rd_n, wr_n, m1_n : in std_logic;
    inrom48k : in  std_logic;                      -- a ROM em 0000 e' a do 48K
    modo2068 : in  std_logic;                      -- TC2068: traps proprias (como no DivTIESUS v3)
    exlo     : in  std_logic;                      -- TC2068 com a EXROM em 0000-1FFF
    nmi128   : in  std_logic := '0';               -- 1 = 0066 mapeia tambem com a ROM do 128 (como o modo128 do DivTIESUS)
    sem38    : in  std_logic := '0';               -- 1 = sem a trap em 0038 (teste: o INT de cada quadro nao passa pelo esxDOS)
    nmi_bot  : in  std_logic;                      -- botao (1 = carregado, ja' sem ressaltos)
    nmi_n    : out std_logic;
    -- memoria: o core decide com isto
    mapa     : out std_logic;                      -- 0000-3FFF e' do DivMMC
    e_eeprom : out std_logic;                      -- este acesso e' a' EEPROM (0000-1FFF)
    pagina   : out std_logic_vector(5 downto 0);   -- pagina de 8K da RAM (2000-3FFF, ou 3 em 0000)
    ram_we   : out std_logic;                      -- a escrita na RAM do DivMMC e' permitida
    -- porta EB
    e_porta  : out std_logic;                      -- leitura de uma porta do DivMMC
    q_porta  : out std_logic_vector(7 downto 0);
    -- SPI
    sd_cs_n  : out std_logic;
    sd_sclk  : out std_logic;
    sd_mosi  : out std_logic;
    sd_miso  : in  std_logic
  );
end entity;

architecture rtl of divmmc is
  signal conmem, mapram : std_logic := '0';
  signal pag : std_logic_vector(5 downto 0) := (others => '0');
  signal mapeado, depois_m1 : std_logic := '1';
  signal mreq_d, iorq_d : std_logic := '1';
  signal cs_r : std_logic := '1';
  -- SPI
  signal sh : std_logic_vector(7 downto 0) := (others => '1');
  signal rx : std_logic_vector(7 downto 0) := (others => '1');
  signal cnt : unsigned(4 downto 0) := (others => '1');   -- 16 meios ciclos; 11111 = parado
  signal div : unsigned(2 downto 0) := (others => '0');
  signal sclk_r : std_logic := '0';
  signal io_feito : std_logic := '0';
  signal e_mem0 : std_logic;
  signal bit_in : std_logic := '1';
  signal armado : std_logic := '0';
  signal trap68 : boolean;
begin
  -- TC2068 (DivTIESUS v3): 0000, 0066 e 3Dxx sempre; 0008 e 0038 so' com a HOME em
  -- 0000-1FFF; 04C6 nunca; 0562 so' logo a seguir ao M1 em 0108 com a EXROM (o JP 0562
  -- que o faz2068rom.py pos no LD-BYTES da EXROM).
  trap68 <= modo2068 = '1' and (a = x"0066" or (exlo = '0' and (a = x"0008" or a = x"0038"))
                                or (armado = '1' and a = x"0562"));

  process(clk)
  begin
    if rising_edge(clk) then
      mreq_d <= mreq_n; iorq_d <= iorq_n;
      if reset_n = '0' then
        conmem <= '0'; mapram <= '0'; pag <= (others => '0');
        mapeado <= '1'; depois_m1 <= '1'; armado <= '0';
        cs_r <= '1';
      else
        -- automapeamento, no flanco descendente do MREQ
        if mreq_d = '1' and mreq_n = '0' then
          if m1_n = '0' then
            if modo2068 = '1' and exlo = '1' and a = x"0108" then armado <= '1'; else armado <= '0'; end if;
            if a = x"0000" or trap68 or (modo2068 = '0' and nmi128 = '1' and a = x"0066") or
               (modo2068 = '0' and inrom48k = '1' and (a = x"0008" or (a = x"0038" and sem38 = '0') or a = x"0066"
                                                       or a = x"04C6" or a = x"0562")) then
              depois_m1 <= '1';
            elsif a(15 downto 8) = x"3D" and (inrom48k = '1' or modo2068 = '1') then
              mapeado <= '1'; depois_m1 <= '1';
            elsif a(15 downto 3) = "0001111111111" then
              depois_m1 <= '0';
            end if;
          else
            mapeado <= depois_m1;
          end if;
        end if;
        -- portas (escrita); repetir a escrita durante o ciclo nao faz mal
        if iorq_n = '0' and wr_n = '0' and m1_n = '1' then
          case a(7 downto 0) is
            when x"E3" => conmem <= d(7); mapram <= mapram or d(6); pag <= d(5 downto 0);
            when x"E7" => cs_r <= d(0);
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;

  -- SPI modo 0: 54 MHz / 8 por meio ciclo = 3,375 MHz no SCLK.
  --   subida: o cartao amostra o MOSI e eu guardo o MISO; descida: entra o bit, sai o seguinte.
  --   Leitura da EB: devolve o byte da transferencia anterior (guardado no inicio) e envia FF.
  process(clk)
  begin
    if rising_edge(clk) then
      if iorq_n = '1' then io_feito <= '0'; end if;
      if reset_n = '0' then
        cnt <= (others => '1'); sclk_r <= '0'; sh <= (others => '1');
      elsif cnt = "11111" then
        sclk_r <= '0';
        if iorq_n = '0' and m1_n = '1' and a(7 downto 0) = x"EB" and io_feito = '0'
           and (wr_n = '0' or rd_n = '0') then
          io_feito <= '1';
          if wr_n = '0' then sh <= d;
          else rx <= sh; sh <= x"FF"; end if;
          cnt <= (others => '0'); div <= (others => '0');
        end if;
      else
        div <= div + 1;
        if div = 7 then
          if cnt(0) = '0' then
            sclk_r <= '1'; bit_in <= sd_miso;
          else
            sclk_r <= '0'; sh <= sh(6 downto 0) & bit_in;
          end if;
          if cnt = 15 then cnt <= (others => '1'); else cnt <= cnt + 1; end if;
        end if;
      end if;
    end if;
  end process;

  sd_sclk <= sclk_r;
  sd_mosi <= sh(7);
  sd_cs_n <= cs_r;

  -- leitura da porta EB: o byte da transferencia anterior
  e_porta <= '1' when iorq_n = '0' and rd_n = '0' and m1_n = '1' and a(7 downto 0) = x"EB" else '0';
  q_porta <= rx;

  -- memoria em 0000-3FFF (jumper E fechado)
  e_mem0 <= '1' when a(15 downto 14) = "00" else '0';
  process(conmem, mapram, mapeado, a, pag)
  begin
    mapa <= '0'; e_eeprom <= '0'; pagina <= pag; ram_we <= '0';
    if conmem = '1' then
      mapa <= '1';
      if a(13) = '0' then e_eeprom <= '1'; else ram_we <= '1'; end if;
    elsif mapeado = '1' and mapram = '1' then
      mapa <= '1';
      if a(13) = '0' then pagina <= "000011";               -- pagina 3, so' leitura
      elsif pag /= "000011" then ram_we <= '1'; end if;
    elsif mapeado = '1' then
      mapa <= '1';
      if a(13) = '0' then e_eeprom <= '1'; else ram_we <= '1'; end if;
    end if;
  end process;

  nmi_n <= '0' when nmi_bot = '1' and mapeado = '0' else '1';
end architecture;
