-- video_timex.vhd: ecra do Timex (TC2048/TC2068) num modo HDMI.
--   Modos (porto FF bits 2-0, como no SCLD do Timmy):
--     bit 0  ecra 1: bitmap em 6000 e atributos em 7800 (em vez de 4000/5800)
--     bit 1  hi-colour: a cor vem de 6000 com a disposicao do bitmap (1 atributo por linha)
--     bit 2  hi-res 512: cada coluna mostra o byte de 4000 e depois o de 6000;
--            tinta = FF bits 5-3, papel e borda = o inverso
--   Horizontal em pontos de hi-res (512 por linha): ESC=2 -> 1 ponto HDMI por ponto
--   de hi-res (576p, exacto); ESC=3 -> 1,5 (720p: os pontos de hi-res alternam 2 e 1).
--   Vertical: cada linha do Timex ocupa ESC linhas HDMI.
--   Memoria: um so' porto de leitura (14 bits desde 4000). Os 2 bytes de cada coluna
--   (bitmap e atributo / 2.o bitmap) leem-se durante a coluna anterior.
--   O VSYNC comeca e acaba no inicio de um HSYNC (CEA-861).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_timex is
  generic (
    H_ACT : integer := 1280; H_FP : integer := 440; H_SY : integer := 40; H_TOT : integer := 1980;
    V_ACT : integer := 720;  V_FP : integer := 5;   V_SY : integer := 5;  V_TOT : integer := 750;
    ESC   : integer := 3;
    SYNC_POS : boolean := true
  );
  port (
    clk    : in  std_logic;
    border : in  std_logic_vector(2 downto 0);  -- bit0 B, bit1 R, bit2 G
    modo   : in  std_logic_vector(2 downto 0);
    hcor   : in  std_logic_vector(2 downto 0);
    r, g, b: out std_logic_vector(7 downto 0);
    de     : out std_logic;
    hs, vs : out std_logic;
    va     : out std_logic_vector(13 downto 0);
    vq     : in  std_logic_vector(7 downto 0);
    -- modo 16C do Pentagon (com modo = 010): mais 2 bytes por coluna, dos bancos 4/6 (0..6143 e 6144..12287)
    m16c   : in  std_logic := '0';
    va2    : out std_logic_vector(13 downto 0);
    vq2    : in  std_logic_vector(7 downto 0) := (others => '0');
    sinc   : in  std_logic := '0';               -- muda quando o core acabou de escrever a linha 0
                                                  -- (Pentagon); a linha 0 do ecra comeca logo a seguir
    -- ULAplus: indice da paleta (FB0III tinta, FB1PPP papel, 001BBB borda) e a cor GGGRRRBB
    ulap   : in  std_logic := '0';
    pal_a  : out std_logic_vector(5 downto 0);
    pal_q  : in  std_logic_vector(7 downto 0) := (others => '0');
    -- (core 62) modo TC2068: o preto com BRIGHT 1 sai cinzento escuro, como no 2068 verdadeiro
    --   (no Spectrum e no TC2048 fica preto)
    m2068  : in  std_logic := '0'
  );
end entity;

architecture rtl of video_timex is
  constant X0 : integer := (H_ACT - 256 * ESC) / 2;
  constant Y0 : integer := (V_ACT - 192 * ESC) / 2;
  constant HS0 : integer := H_ACT + H_FP;

  signal hc : unsigned(11 downto 0) := (others => '0');
  signal vc : unsigned(10 downto 0) := (others => '0');
  signal frames : unsigned(4 downto 0) := (others => '0');

  signal hon, von : std_logic := '0';
  signal hx : unsigned(8 downto 0) := (others => '0');     -- ponto de hi-res 0..511
  signal hacc : integer range 0 to 7 := 0;
  signal sy : unsigned(7 downto 0) := (others => '0');
  signal vsub : integer range 0 to 7 := 0;
  signal vsy : std_logic := '0';
  signal sn : std_logic_vector(2 downto 0) := (others => '0');
  signal pal_r : std_logic_vector(5 downto 0) := (others => '0');
  signal up1, de1, hs1, vs1, up2, de2, hs2, vs2 : std_logic := '0';
  signal r1, g1, b1, r2, g2, b2 : std_logic_vector(7 downto 0) := (others => '0');

  -- leitura antecipada da coluna seguinte
  signal fcol : unsigned(4 downto 0);
  signal p, p1, p2 : std_logic := '0';
  signal va_r : std_logic_vector(13 downto 0) := (others => '0');
  signal nb0, nb1, cb0, cb1 : std_logic_vector(7 downto 0) := (others => '0');
  signal nb2, nb3, cb2, cb3 : std_logic_vector(7 downto 0) := (others => '0');
  signal va2_r : std_logic_vector(13 downto 0) := (others => '0');

  constant PRETO_BR : std_logic_vector(7 downto 0) := x"3C";   -- preto + BRIGHT no TC2068 (a afinar)

  function nivel(aceso : std_logic; br : std_logic) return std_logic_vector is
  begin
    if aceso = '0' then return x"00";
    elsif br = '1' then return x"FF";
    else return x"D7";
    end if;
  end function;

  function pol(x : std_logic) return std_logic is
  begin
    if SYNC_POS then return x; else return not x; end if;
  end function;
begin
  -- contadores HDMI e coordenadas do Timex
  process(clk)
    variable passo : boolean;
  begin
    if rising_edge(clk) then
      sn <= sn(1 downto 0) & sinc;
      -- acerto com o quadro do Z80: se o core acabou a linha 0 e o ecra nao esta' para
      -- comecar (mais de 2 linhas de diferenca), salta para o fim da linha antes da imagem.
      -- Com os relogios presos isto so' acontece uma vez.
      if sn(2) /= sn(1) and (vc < Y0 - 2 or vc > Y0) then
        hc <= to_unsigned(H_TOT - 2, 12); vc <= to_unsigned(Y0 - 1, 11);
      elsif hc = H_TOT - 1 then
        hc <= (others => '0');
        if vc = V_TOT - 1 then
          vc <= (others => '0');
          frames <= frames + 1;
        else
          vc <= vc + 1;
        end if;
        if vc = Y0 - 1 then
          von <= '1'; sy <= (others => '0'); vsub <= 0;
        elsif von = '1' then
          if vsub = ESC - 1 then
            vsub <= 0;
            if sy = 191 then von <= '0'; else sy <= sy + 1; end if;
          else
            vsub <= vsub + 1;
          end if;
        end if;
      else
        hc <= hc + 1;
      end if;

      -- horizontal: 2 pontos de hi-res em cada ESC ciclos
      if hc = X0 - 1 then
        hon <= '1'; hx <= (others => '0'); hacc <= 0;
        cb0 <= nb0; cb1 <= nb1; cb2 <= nb2; cb3 <= nb3; -- coluna 0, lida antes
      elsif hon = '1' then
        passo := hacc + 2 >= ESC;
        if passo then hacc <= hacc + 2 - ESC; else hacc <= hacc + 2; end if;
        if passo then
          if hx = 511 then
            hon <= '0';
          else
            hx <= hx + 1;
            if hx(3 downto 0) = 15 then cb0 <= nb0; cb1 <= nb1; cb2 <= nb2; cb3 <= nb3; end if;  -- coluna nova
          end if;
        end if;
      end if;

      if hc = HS0 - 1 then
        if vc = V_ACT + V_FP then vsy <= '1';
        elsif vc = V_ACT + V_FP + V_SY then vsy <= '0';
        end if;
      end if;
    end if;
  end process;

  -- leitura: alterna o 1.o byte (p=0) e o 2.o (p=1) da coluna seguinte
  fcol <= hx(8 downto 4) + 1 when hon = '1' else (others => '0');
  process(clk)
    variable boff : std_logic_vector(12 downto 0);
  begin
    if rising_edge(clk) then
      boff := std_logic_vector(sy(7 downto 6) & sy(2 downto 0) & sy(5 downto 3) & fcol);
      p <= not p;
      p1 <= p;
      p2 <= p1;
      if p = '0' then
        va_r <= modo(0) & boff;                                          -- bitmap
      elsif modo(1) = '1' then
        va_r <= '1' & boff;                                              -- hi-colour / hi-res
      else
        va_r <= modo(0) & "110" & std_logic_vector(sy(7 downto 3) & fcol); -- atributos
      end if;
      if p = '0' then va2_r <= '0' & boff; else va2_r <= std_logic_vector(unsigned('0' & boff) + 6144); end if;
      if p2 = '0' then nb0 <= vq; nb2 <= vq2; else nb1 <= vq; nb3 <= vq2; end if;
    end if;
  end process;
  va <= va_r;
  va2 <= va2_r;

  -- ponto: 1.o ciclo escolhe a cor (e o indice do ULAplus); a paleta e' uma RAM com 1 ciclo
  -- de atraso; no 3.o ciclo sai a cor (as cores fixas e os sincronismos atrasam o mesmo)
  process(clk)
    variable px  : std_logic;
    variable byt : std_logic_vector(7 downto 0);
    variable c   : std_logic_vector(2 downto 0);
    variable br  : std_logic;
    variable at  : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      up1 <= ulap and not modo(2) and not m16c;     -- no hi-res e no 16C ficam as cores fixas
      if hon = '1' and von = '1' then
        if m16c = '1' then
          -- 16C: 8 pontos por coluna, 2 por byte: banco 4, banco 5, banco 4 + 2000h, banco 5 + 2000h;
          -- ponto da esquerda = bits 2-0 + brilho no bit 6, da direita = bits 5-3 + brilho no bit 7
          case hx(3 downto 2) is
            when "00" => byt := cb2;
            when "01" => byt := cb0;
            when "10" => byt := cb3;
            when others => byt := cb1;
          end case;
          if hx(1) = '0' then c := byt(2 downto 0); br := byt(6);
          else c := byt(5 downto 3); br := byt(7); end if;
          pal_r <= (others => '0');
        elsif modo(2) = '1' then
          if hx(3) = '0' then byt := cb0; else byt := cb1; end if;
          px := byt(7 - to_integer(hx(2 downto 0)));
          if px = '1' then c := hcor; else c := not hcor; end if;
          br := '0';
          pal_r <= (others => '0');
        else
          at := cb1;
          if ulap = '1' then
            px := cb0(7 - to_integer(hx(3 downto 1)));            -- com ULAplus nao ha' FLASH
            if px = '1' then pal_r <= at(7 downto 6) & '0' & at(2 downto 0);
            else pal_r <= at(7 downto 6) & '1' & at(5 downto 3); end if;
          else
            px := cb0(7 - to_integer(hx(3 downto 1))) xor (cb1(7) and frames(4));
          end if;
          if px = '1' then c := cb1(2 downto 0); else c := cb1(5 downto 3); end if;
          br := cb1(6);
        end if;
      else
        if modo(2) = '1' then c := not hcor; else c := border; end if;
        br := '0';
        pal_r <= "001" & border;                                  -- borda: entrada 8 + cor
      end if;
      if c = "000" and br = '1' and m2068 = '1' then
        r1 <= PRETO_BR; g1 <= PRETO_BR; b1 <= PRETO_BR;
      else
        r1 <= nivel(c(1), br);
        g1 <= nivel(c(2), br);
        b1 <= nivel(c(0), br);
      end if;
      if hc < H_ACT and vc < V_ACT then de1 <= '1'; else de1 <= '0'; end if;
      if hc >= HS0 and hc < HS0 + H_SY then hs1 <= pol('1'); else hs1 <= pol('0'); end if;
      vs1 <= pol(vsy);
      -- 2.o ciclo: a RAM da paleta le' o indice
      r2 <= r1; g2 <= g1; b2 <= b1; de2 <= de1; hs2 <= hs1; vs2 <= vs1; up2 <= up1;
      -- 3.o ciclo: sai a cor
      if up2 = '1' then
        r <= pal_q(4 downto 2) & pal_q(4 downto 2) & pal_q(4 downto 3);
        g <= pal_q(7 downto 5) & pal_q(7 downto 5) & pal_q(7 downto 6);
        b <= pal_q(1 downto 0) & (pal_q(1) or pal_q(0)) & pal_q(1 downto 0) & (pal_q(1) or pal_q(0)) & pal_q(1 downto 0);
      else
        r <= r2; g <= g2; b <= b2;
      end if;
      de <= de2; hs <= hs2; vs <= vs2;
    end if;
  end process;
  pal_a <= pal_r;
end architecture;
