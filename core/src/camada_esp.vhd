-- camada_esp.vhd (2026-10-22, v2): as camadas do ESP32 por cima da imagem do Spectrum, a' saida do HDMI.
--   Camada L: o ecra todo (H_ACT x V_ACT, 1280x720 em 720p) a 2 bits por ponto, ponto a ponto.
--     Cor 0 = transparente; cores 1-3 = paleta de 24 bits. H_ACT/4 bytes por linha (320 em 720p);
--     em cada byte o ponto da esquerda e' o dos bits 7-6. Na SDRAM em 600000h (ou 640000h).
--   Janela W: 256x192 a 24 bits (4 bytes por ponto: R, G, B, -), cada ponto a 3x3 (768x576, o tamanho do
--     jogo), com o canto em (wx, wy). 1024 bytes por linha, na SDRAM em 680000h (ou 6C0000h).
--   Por cima de tudo a camada L (cor /= 0), depois a janela, depois o Spectrum.
--   O core le' as linhas da SDRAM em rajadas de 8 palavras para o buffer (ram_linha, 512 x 32):
--     0-255: a camada L (2 linhas: a mostrada e a seguinte, 80 palavras cada)
--     256-511: uma linha da janela (cada linha da janela serve 3 linhas do HDMI; a seguinte e' lida
--              no fim da 3.a, enquanto o feixe esta' fora da janela).
--   Um so' porto de leitura: a janela le' uma palavra a cada 3 pontos, a camada L uma a cada 16 (lida
--   adiantada, num ponto sem leitura da janela).
--   Atraso: 5 ciclos de pclk (r, g, b, de, hs e vs saem todos atrasados de 5; era 4 ate' ao esp59).
-- Tambem aqui: ram_linha (128 x 32, dois relogios, BSRAM) e ram_lut (RAM pequena em LUTs, para a paleta
-- da ULAplus sair da BSRAM e deixar um bloco livre para o buffer de linhas).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_linha is
  generic (AW : integer := 9);
  port (clka : in std_logic; wea : in std_logic; aa : in std_logic_vector(AW-1 downto 0);
        da : in std_logic_vector(31 downto 0);
        clkb : in std_logic; ab : in std_logic_vector(AW-1 downto 0); qb : out std_logic_vector(31 downto 0));
end entity;
architecture rtl of ram_linha is
  type m_t is array (0 to 2**AW - 1) of std_logic_vector(31 downto 0);
  signal m : m_t := (others => (others => '0'));
begin
  process(clka) begin
    if rising_edge(clka) then
      if wea = '1' then m(to_integer(unsigned(aa))) <= da; end if;
    end if;
  end process;
  process(clkb) begin
    if rising_edge(clkb) then qb <= m(to_integer(unsigned(ab))); end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity ram_lut is
  generic (AW : integer := 6);
  port (clk : in std_logic; a : in std_logic_vector(AW-1 downto 0); we : in std_logic;
        d : in std_logic_vector(7 downto 0); q : out std_logic_vector(7 downto 0);
        clkb : in std_logic; b : in std_logic_vector(AW-1 downto 0); bq : out std_logic_vector(7 downto 0));
end entity;
architecture rtl of ram_lut is
  type m_t is array (0 to 2**AW - 1) of std_logic_vector(7 downto 0);
  signal m : m_t := (others => (others => '0'));
  attribute syn_ramstyle : string;
  attribute syn_ramstyle of m : signal is "distributed_ram";
begin
  process(clk) begin
    if rising_edge(clk) then
      if we = '1' then m(to_integer(unsigned(a))) <= d; end if;
      q <= m(to_integer(unsigned(a)));
    end if;
  end process;
  process(clkb) begin
    if rising_edge(clkb) then bq <= m(to_integer(unsigned(b))); end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity camada_esp is
  generic (H_ACT : integer := 1280; V_ACT : integer := 720; SYNC_POS : boolean := true);
  port (
    clk    : in  std_logic;                          -- pclk
    ligada : in  std_logic;                          -- camada L ligada (registo da ponte, quase estatico)
    janela : in  std_logic;                          -- janela W ligada
    dobro  : in  std_logic := '0';
    w16    : in  std_logic := '0';                   -- (esp43) janela a 16 bits por ponto (RGB565, 512 bytes por linha)
    meio   : in  std_logic_vector(2 downto 0) := "000";   -- cores 3..1 meio transparentes (3/4 a cor, 1/4 o que esta' por baixo)                   -- (2026-10-22) janela a 2x (512x384) em vez de 3x (768x576)
    wx     : in  std_logic_vector(10 downto 0);      -- canto da janela (pontos do HDMI)
    wy     : in  std_logic_vector(9 downto 0);
    sel_in : in  std_logic;                          -- imagens pedidas pelo ESP (0 ou 1)
    sel_out: out std_logic;                          -- imagens mostradas: so' muda no inicio do quadro
    -- (esp44) a janela com escolha propria (3 imagens): wsep = 1 -> a janela mostra a imagem widx (0-2)
    wsep_in : in std_logic := '0';
    widx_in : in std_logic_vector(1 downto 0) := "00";
    wsep_out : out std_logic;
    widx_out : out std_logic_vector(1 downto 0);
    cor1, cor2, cor3 : in std_logic_vector(23 downto 0);   -- RRGGBB
    ri, gi, bi : in std_logic_vector(7 downto 0);
    dei, hsi, vsi : in std_logic;
    ro, go, bo : out std_logic_vector(7 downto 0);
    deo, hso, vso : out std_logic;
    -- pedidos para o core (relogio de 54 MHz): mudam de valor a cada pedido
    pede_l : out std_logic;
    lin_l  : out std_logic_vector(9 downto 0);       -- linha da camada L (0..V_ACT-1)
    pede_w : out std_logic;
    lin_w  : out std_logic_vector(7 downto 0);       -- linha da janela (0..191)
    -- buffer de linhas (porto de leitura)
    lb_a   : out std_logic_vector(8 downto 0);
    lb_q   : in  std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of camada_esp is
  signal hx : integer range 0 to 4095 := 0;
  signal ly : integer range 0 to 2047 := 0;
  signal de_d, vs_d : std_logic := '0';
  signal lig_s, jan_s, sel_s, dob_s, w16_s : std_logic_vector(1 downto 0) := "00";
  signal w16_q, wh1, wh2, whc : std_logic := '0';
  signal wsep_s : std_logic_vector(1 downto 0) := "00";
  signal wsep_q : std_logic := '0';
  signal widx_s1, widx_s2, widx_q : std_logic_vector(1 downto 0) := "00";
  signal wmax : integer range 1 to 2 := 2;           -- 2x: 1, 3x: 2 (cada ponto / linha da janela repete wmax+1 vezes)
  signal jw : integer range 0 to 1023 := 768;         -- largura da janela no ecra
  signal jh : integer range 0 to 1023 := 576;         -- altura
  signal sel_q : std_logic := '0';
  signal pl, pw : std_logic := '0';
  signal ll : std_logic_vector(9 downto 0) := (others => '0');
  signal lw : std_logic_vector(7 downto 0) := (others => '0');
  signal wc : integer range 0 to 2 := 0;
  signal wsn : integer range 0 to 255 := 0;
  -- andar A (v2b): as comparacoes ficam registadas (o caminho de 17 niveis nao cumpria os 74,25 MHz)
  signal x0r, y0r : integer range 0 to 2047 := 0;
  signal x1r, y1r : integer range 0 to 4095 := 0;     -- fim da janela (registado: x0r + jw, y0r + jh)
  signal a_win, a_x0, a_m1, a_m2, a_de, a_hs, a_hsd, a_vs, a_lig, a_par : std_logic := '0';
  signal a_s : unsigned(3 downto 0) := (others => '0');
  signal a_wn : std_logic_vector(6 downto 0) := (others => '0');
  signal a_r, a_g, a_b : std_logic_vector(7 downto 0) := (others => '0');
  signal a_hs_in, a_vs_in : std_logic := '0';
  -- andar B: as leituras do buffer
  signal wph : integer range 0 to 2 := 0;
  signal wix : integer range 0 to 255 := 0;
  signal lp : std_logic := '0';
  signal k1, k2 : std_logic_vector(1 downto 0) := "00";
  signal lcur, lnext, wcur : std_logic_vector(31 downto 0) := (others => '0');
  signal s1, s2 : unsigned(3 downto 0) := (others => '0');
  signal lon1, lon2, win1, win2 : std_logic := '0';
  signal hs1, vs1, de1, hs2, vs2, de2 : std_logic := '0';
  signal r1, g1, b1, r2, g2, b2 : std_logic_vector(7 downto 0) := (others => '0');
  -- (esp60) andar 4: a mistura da cor da camada L fica num andar proprio (o caminho s2 -> ro/go/bo
  -- tinha so' 1,4 ns de folga a 74,25 MHz)
  signal idx3 : std_logic_vector(1 downto 0) := "00";
  signal baixo3 : std_logic_vector(23 downto 0) := (others => '0');
  signal lon3, de3, hs3, vs3 : std_logic := '0';
  signal vsa, hsa : std_logic;
begin
  vsa <= vsi when SYNC_POS else not vsi;
  hsa <= hsi when SYNC_POS else not hsi;
  pede_l <= pl; lin_l <= ll; pede_w <= pw; lin_w <= lw; sel_out <= sel_q; wsep_out <= wsep_q; widx_out <= widx_q;

  process(clk)
    variable nl : integer;
    variable ph : integer range 0 to 2;
    variable ix : integer range 0 to 255;
    variable w, lw_v, wv : std_logic_vector(31 downto 0);
    variable byte : std_logic_vector(7 downto 0);
    variable idx : std_logic_vector(1 downto 0);
    variable c, baixo : std_logic_vector(23 downto 0);
    variable p16 : std_logic_vector(15 downto 0);
    variable wh, mt : std_logic;
  begin
    if rising_edge(clk) then
      lig_s <= lig_s(0) & ligada; jan_s <= jan_s(0) & janela; sel_s <= sel_s(0) & sel_in;
      wsep_s <= wsep_s(0) & wsep_in; widx_s1 <= widx_in; widx_s2 <= widx_s1;
      dob_s <= dob_s(0) & dobro; w16_s <= w16_s(0) & w16;
      if vsa = '1' and vs_d = '0' then                   -- a escala so' muda no inicio do quadro
        w16_q <= w16_s(1);
        if dob_s(1) = '1' then wmax <= 1; jw <= 512; jh <= 384; else wmax <= 2; jw <= 768; jh <= 576; end if;
      end if;
      x0r <= to_integer(unsigned(wx)); y0r <= to_integer(unsigned(wy));
      x1r <= x0r + jw; y1r <= y0r + jh;
      de_d <= dei; vs_d <= vsa;
      if dei = '1' then hx <= hx + 1; else hx <= 0; end if;

      -- pedidos de linhas (no relogio de entrada; nao sao de tempo apertado)
      if vsa = '1' and vs_d = '0' then
        ly <= 0;
        sel_q <= sel_s(1);                                       -- troca de imagens so' aqui
        wsep_q <= wsep_s(1);
        if wsep_s(1) = '1' then widx_q <= widx_s2; else widx_q <= "00"; end if;
        if lig_s(1) = '1' then ll <= (others => '0'); pl <= not pl; end if;
        if jan_s(1) = '1' and y0r = 0 then lw <= (others => '0'); pw <= not pw; wc <= 0; wsn <= 0; end if;
      elsif dei = '1' and de_d = '0' then
        if lig_s(1) = '1' and ly + 1 < V_ACT then ll <= std_logic_vector(to_unsigned(ly + 1, 10)); pl <= not pl; end if;
      elsif dei = '0' and de_d = '1' then
        ly <= ly + 1;
        nl := ly + 1;
        if nl = y0r then
          wc <= 0; wsn <= 0;
          if jan_s(1) = '1' then lw <= (others => '0'); pw <= not pw; end if;
        elsif nl > y0r and nl < y1r then
          if wc = wmax then
            wc <= 0;
            if wsn < 191 then
              wsn <= wsn + 1;
              if jan_s(1) = '1' then lw <= std_logic_vector(to_unsigned(wsn + 1, 8)); pw <= not pw; end if;
            end if;
          else
            wc <= wc + 1;
          end if;
        end if;
      end if;

      -- andar A: comparacoes do ponto hx (registadas)
      if jan_s(1) = '1' and dei = '1' and ly >= y0r and ly < y1r and hx >= x0r and hx < x1r then a_win <= '1'; else a_win <= '0'; end if;
      if hx = x0r then a_x0 <= '1'; else a_x0 <= '0'; end if;
      if dei = '1' and hx mod 16 = 1 then a_m1 <= '1'; else a_m1 <= '0'; end if;
      if dei = '1' and hx mod 16 = 2 then a_m2 <= '1'; else a_m2 <= '0'; end if;
      a_s <= to_unsigned(hx mod 16, 4);
      a_wn <= std_logic_vector(to_unsigned((hx / 16 + 1) mod 128, 7));
      a_par <= std_logic(to_unsigned(ly mod 2, 1)(0));
      if lig_s(1) = '1' and dei = '1' then a_lig <= '1'; else a_lig <= '0'; end if;
      a_de <= dei; a_hs_in <= hsi; a_vs_in <= vsi; a_r <= ri; a_g <= gi; a_b <= bi;
      a_hs <= hsa; a_hsd <= a_hs;

      -- andar B: leituras do buffer (uma por ciclo; o dado chega 2 ciclos depois)
      if a_x0 = '1' then ph := 0; ix := 0;
      elsif wph >= wmax then ph := 0; if wix < 255 then ix := wix + 1; else ix := wix; end if;
      else ph := wph + 1; ix := wix; end if;
      wph <= ph; wix <= ix;
      if a_m1 = '1' then lp <= '1'; end if;
      k1 <= "00";
      if a_win = '1' and ph = 0 then
        if w16_q = '1' then lb_a <= "10" & std_logic_vector(to_unsigned(ix / 2, 7)); else lb_a <= '1' & std_logic_vector(to_unsigned(ix, 8)); end if;
        k1 <= "10"; wh1 <= std_logic(to_unsigned(ix mod 2, 1)(0));
      elsif a_m1 = '1' or (a_m2 = '1' and lp = '1') then
        lb_a <= '0' & a_par & a_wn; k1 <= "01"; lp <= '0';
      elsif a_hs = '1' and a_hsd = '0' then
        -- no sincronismo: a 1.a palavra da proxima linha da camada L
        lb_a <= '0' & a_par & "0000000"; k1 <= "01";
      end if;
      k2 <= k1; wh2 <= wh1;

      s1 <= a_s; lon1 <= a_lig; win1 <= a_win;
      r1 <= a_r; g1 <= a_g; b1 <= a_b; de1 <= a_de; hs1 <= a_hs_in; vs1 <= a_vs_in;
      s2 <= s1; lon2 <= lon1; win2 <= win1;
      r2 <= r1; g2 <= g1; b2 <= b1; de2 <= de1; hs2 <= hs1; vs2 <= vs1;

      -- andar 3: chegou o dado pedido 2 ciclos antes
      wv := wcur; wh := whc;
      if k2 = "10" then wv := lb_q; wh := wh2; end if;
      wcur <= wv; whc <= wh;
      -- (esp43) a 16 bits: o ponto e' a metade da palavra (o 1.o ponto nos bits 15-0), RGB565 -> 24 bits
      if w16_q = '1' then
        if wh = '1' then p16 := wv(31 downto 16); else p16 := wv(15 downto 0); end if;
        wv := x"00" & p16(4 downto 0) & p16(4 downto 2) & p16(10 downto 5) & p16(10 downto 9) & p16(15 downto 11) & p16(15 downto 13);
      end if;
      if k2 = "01" then lnext <= lb_q; end if;
      if s2 = 0 then lw_v := lnext; lcur <= lnext; else lw_v := lcur; end if;
      case s2(3 downto 2) is
        when "00"   => byte := lw_v(7 downto 0);
        when "01"   => byte := lw_v(15 downto 8);
        when "10"   => byte := lw_v(23 downto 16);
        when others => byte := lw_v(31 downto 24);
      end case;
      case s2(1 downto 0) is
        when "00"   => idx := byte(7 downto 6);
        when "01"   => idx := byte(5 downto 4);
        when "10"   => idx := byte(3 downto 2);
        when others => idx := byte(1 downto 0);
      end case;
      -- o que esta' por baixo da camada L: a janela ou o Spectrum (registado: andar 4)
      idx3 <= idx;
      if win2 = '1' then baixo3 <= wv(7 downto 0) & wv(15 downto 8) & wv(23 downto 16); else baixo3 <= r2 & g2 & b2; end if;
      lon3 <= lon2; de3 <= de2; hs3 <= hs2; vs3 <= vs2;

      -- andar 4 (esp60): a cor da camada L por cima do que esta' por baixo
      case idx3 is
        when "01"   => c := cor1; mt := meio(0);
        when "10"   => c := cor2; mt := meio(1);
        when others => c := cor3; mt := meio(2);
      end case;
      baixo := baixo3;
      if lon3 = '1' and idx3 /= "00" and mt = '1' then
        ro <= std_logic_vector(resize((unsigned("00" & c(23 downto 16)) * 3 + unsigned(baixo(23 downto 16))) / 4, 8));
        go <= std_logic_vector(resize((unsigned("00" & c(15 downto 8)) * 3 + unsigned(baixo(15 downto 8))) / 4, 8));
        bo <= std_logic_vector(resize((unsigned("00" & c(7 downto 0)) * 3 + unsigned(baixo(7 downto 0))) / 4, 8));
      elsif lon3 = '1' and idx3 /= "00" then
        ro <= c(23 downto 16); go <= c(15 downto 8); bo <= c(7 downto 0);
      else
        ro <= baixo(23 downto 16); go <= baixo(15 downto 8); bo <= baixo(7 downto 0);
      end if;
      deo <= de3; hso <= hs3; vso <= vs3;
    end if;
  end process;
end architecture;
