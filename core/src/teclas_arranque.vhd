-- teclas_arranque.vhd: escolha do botao B no core Timmy (sem menu no arranque).
--   Cada toque no A passa a' escolha seguinte (em ciclo); os LEDs 4-6 mostram-na em binario.
--   O B faz a escolha:
--     0 (LEDs apagados) NMI, como antes      1 .ls          2 .go128
--     3 .go128 -penta   4 .go1024  5 .go2068   6 RESET+NMI (volta ao TC2048, sai do 2068/128K)
--     7 scroll: no menu do 128 vai ao 48 BASIC, .vdisk 0 teste.trd, TR-DOS, RUN (no Pentagon)
--     8 RESET so' (sem NMI): reinicia a maquina em que esta' (128K, Pentagon, 2068 ficam)
--     9 16color.scl (como o 7, para o Pentagon 1024)   10 .gs (carrega e arranca o General Sound)
--     11 hello.trd (como o 7)   12 ENTER   13 cursor baixo (CS+6)   14 cursor cima (CS+7)
--     15 turbo: cada B passa 3,5 -> 7 -> 14 -> 3,5 MHz (o top guarda a velocidade)
--   A escolha tem 4 bits, nos LEDs dos pinos 17, 18, 19, 20 = bits 0, 1, 2, 3; por agora vai de 0 a 15.
--   O A carregado 3 s continua a trocar de core (multiboot, no top).
--   Os comandos escrevem-se tecla a tecla (78 ms + 78 ms): tem de estar no BASIC.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.teclas_seq.all;

entity teclas_arranque is
  port (
    clk      : in  std_logic;                     -- 54 MHz
    pronta   : in  std_logic;                     -- (nao usado)
    rst_n    : in  std_logic;                     -- reset do Z80
    bot_a    : in  std_logic;                     -- botoes sem ressaltos (1 = carregado)
    bot_b    : in  std_logic;
    segura   : out std_logic;                     -- 1 = reset do Z80 (escolha 6: RESET+NMI)
    nmi_rst  : out std_logic;                     -- 1 = NMI carregado durante esse reset
    turbo_t  : out std_logic;
    rnmi_t   : in  std_logic := '0';              -- impulso do core: faz a escolha 6 (RESET+NMI)                     -- impulso: velocidade seguinte (escolha 15)
    escolha  : out std_logic_vector(3 downto 0);
    led_pisca : out std_logic;
    mat      : out std_logic_vector(39 downto 0)
  );
end entity;

architecture rtl of teclas_arranque is
  constant K_CS : integer := 0; constant K_SS : integer := 36;
  constant SEQ : seq_t := SEQ_LS & SEQ_G128 & SEQ_GPEN & SEQ_G256 & SEQ_G2068 & SEQ_TRD & SEQ_SCL & SEQ_GS & SEQ_HEL & SEQ_ENT & SEQ_BAIXO & SEQ_CIMA;
  constant ULTIMA : integer := 15;
  constant I1 : integer := SEQ_LS'length;
  constant I2 : integer := I1 + SEQ_G128'length;
  constant I3 : integer := I2 + SEQ_GPEN'length;
  constant I4 : integer := I3 + SEQ_G256'length;
  constant I5 : integer := I4 + SEQ_G2068'length;
  constant I6 : integer := I5 + SEQ_TRD'length;
  constant I7 : integer := I6 + SEQ_SCL'length;
  constant I8 : integer := I7 + SEQ_GS'length;
  constant I9 : integer := I8 + SEQ_HEL'length;
  constant I10 : integer := I9 + SEQ_ENT'length;
  constant I11 : integer := I10 + SEQ_BAIXO'length;
  signal esc : unsigned(3 downto 0) := "0000";
  signal a_d, b_d : std_logic := '0';
  signal ativo : std_logic := '0';
  constant T_RST : integer := 27000000;           -- 0,5 s (NMI so' na 1.a metade)
  signal rt : integer range 0 to T_RST := 0;
  signal com_nmi : std_logic := '0';
  signal idx, fim : integer range 0 to SEQ'length := 0;
  signal t : unsigned(22 downto 0) := (others => '0');
  signal m : std_logic_vector(39 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      a_d <= bot_a; b_d <= bot_b;
      if bot_a = '1' and a_d = '0' then
        if esc = ULTIMA then esc <= (others => '0'); else esc <= esc + 1; end if;
      end if;
      if rt /= 0 then rt <= rt - 1; end if;
      turbo_t <= '0';
      if bot_b = '1' and b_d = '0' and esc = 15 then
        turbo_t <= '1';
      elsif rnmi_t = '1' then
        rt <= T_RST; ativo <= '0'; com_nmi <= '1';
      elsif bot_b = '1' and b_d = '0' and (esc = 6 or esc = 8) then
        rt <= T_RST; ativo <= '0';
        if esc = 6 then com_nmi <= '1'; else com_nmi <= '0'; end if;
      elsif rst_n = '0' then
        ativo <= '0';
      elsif ativo = '0' and bot_b = '1' and b_d = '0' and esc /= 0 then
        ativo <= '1'; t <= (others => '0');
        case to_integer(esc) is
          when 1      => idx <= 0;  fim <= I1 - 1;
          when 2      => idx <= I1; fim <= I2 - 1;
          when 3      => idx <= I2; fim <= I3 - 1;
          when 4      => idx <= I3; fim <= I4 - 1;
          when 5      => idx <= I4; fim <= I5 - 1;
          when 7      => idx <= I5; fim <= I6 - 1;
          when 9      => idx <= I6; fim <= I7 - 1;
          when 10     => idx <= I7; fim <= I8 - 1;
          when 11     => idx <= I8; fim <= I9 - 1;
          when 12     => idx <= I9; fim <= I10 - 1;
          when 13     => idx <= I10; fim <= I11 - 1;
          when others => idx <= I11; fim <= SEQ'length - 1;
        end case;
      elsif ativo = '1' then
        t <= t + 1;
        if t = 2**23 - 1 then
          if idx = fim then ativo <= '0'; else idx <= idx + 1; end if;
        end if;
      end if;
    end if;
  end process;
  segura    <= '1' when rt /= 0 else '0';
  nmi_rst   <= '1' when rt > T_RST/2 and com_nmi = '1' else '0';
  escolha   <= std_logic_vector(esc);
  led_pisca <= ativo;

  process(ativo, idx, t)
    variable v : std_logic_vector(39 downto 0);
  begin
    v := (others => '0');
    if ativo = '1' and t(22) = '0' and SEQ(idx).np = '0' then
      v(SEQ(idx).k) := '1';
      if SEQ(idx).ss = '1' then v(K_SS) := '1'; end if;
      if SEQ(idx).cs = '1' then v(K_CS) := '1'; end if;
    end if;
    m <= v;
  end process;
  mat <= m;
end architecture;
