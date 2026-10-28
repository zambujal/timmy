-- i2s_rx.vhd: recebe o som do ESP32-S3 por I2S (Philips, 16 bits por canal, estereo; o ESP e' o mestre).
--   BCLK = 48 kHz x 32 = 1,536 MHz, amostrado a 54 MHz (~17 amostras por meio periodo).
--   Os dados mudam no flanco de descida do BCLK e leem-se no de subida. O WS muda um bit antes do MSB:
--   no flanco de subida em que o WS ja' mudou entra o LSB da palavra anterior. WS = 0 esquerda, 1 direita.
--   (esp55) Filtro: o BCLK so' muda de nivel depois de 4 amostras iguais (~75 ns), para os ressaltos das
--   arestas lentas nos fios nao contarem como flancos; e so' se aceita uma palavra com exatamente 16 bits
--   (senao fica a amostra anterior). Contadores de palavras boas e mas para o ESP (diagnostico).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_rx is
  port (
    clk    : in  std_logic;                        -- 54 MHz
    bck, ws, d : in std_logic;                     -- pinos (sem sincronizar)
    l, r   : out std_logic_vector(15 downto 0);    -- ultima amostra completa (com sinal)
    ativo  : out std_logic;                        -- 1 = ha' BCLK (o ESP esta' a mandar)
    n_mas  : out std_logic_vector(7 downto 0)      -- palavras com o numero de bits errado (conta e da' a volta)
  );
end entity;

architecture rtl of i2s_rx is
  signal bs : std_logic_vector(5 downto 0) := (others => '0');
  signal wsy, dsy : std_logic_vector(2 downto 0) := (others => '0');
  signal bf : std_logic := '0';                    -- BCLK filtrado
  signal sr : std_logic_vector(15 downto 0) := (others => '0');
  signal ws_ant : std_logic := '0';
  signal nb : unsigned(5 downto 0) := (others => '0');   -- bits desde a ultima mudanca do WS
  signal el, ol, orr : std_logic_vector(15 downto 0) := (others => '0');
  signal el_ok : std_logic := '0';
  signal mas : unsigned(7 downto 0) := (others => '0');
  signal sem : unsigned(11 downto 0) := (others => '1');   -- ciclos desde o ultimo flanco (satura)
begin
  process(clk)
    variable pal : std_logic_vector(15 downto 0);
    variable sobe : boolean;
  begin
    if rising_edge(clk) then
      bs <= bs(4 downto 0) & bck; wsy <= wsy(1 downto 0) & ws; dsy <= dsy(1 downto 0) & d;
      sobe := false;
      if bf = '0' and bs(5 downto 2) = "1111" then bf <= '1'; sobe := true; end if;
      if bf = '1' and bs(5 downto 2) = "0000" then bf <= '0'; end if;
      if sobe then                                  -- flanco de subida do BCLK (filtrado)
        sem <= (others => '0');
        pal := sr(14 downto 0) & dsy(2);            -- a palavra com este bit (o dado chega 1 ciclo antes do BCLK filtrado)
        sr <= pal;
        if wsy(2) /= ws_ant then                    -- o WS mudou: este bit era o LSB da palavra anterior
          if nb = 15 then                           -- 15 bits antes + este = 16
            if ws_ant = '0' then el <= pal; el_ok <= '1';
            elsif el_ok = '1' then ol <= el; orr <= pal; el_ok <= '0'; end if;
          else
            mas <= mas + 1; el_ok <= '0';
          end if;
          nb <= (others => '0');
        elsif nb /= 63 then
          nb <= nb + 1;
        end if;
        ws_ant <= wsy(2);
      elsif sem /= x"FFF" then
        sem <= sem + 1;
      end if;
    end if;
  end process;
  l <= ol; r <= orr;
  ativo <= '1' when sem /= x"FFF" else '0';         -- ~76 us sem flancos = parado
  n_mas <= std_logic_vector(mas);
end architecture;
