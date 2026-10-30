-- hdmi_tx.vhd: HDMI com som (LPCM 48 kHz, 2 canais) para o Timmy.
--   Substitui os 3 tmds_enc do DVI. O video atrasa D_ATR pontos para se saber, antes
--   de cada linha, quando vem o DE (preambulo + banda de guarda do video).
--   Em cada linha, logo no inicio do HSYNC, vai uma ilha de dados com 2 pacotes:
--     pacote 0: amostras de audio pendentes (0..4; sem amostras = pacote nulo)
--     pacote 1: alterna ACR (N/CTS), AVI InfoFrame, ACR, Audio InfoFrame
--   Ilha: preambulo 8 + guarda 2 + 2 x 32 + guarda 2 = 76 pontos (cabe em 480p/576p/720p).
--   Pacotes: cabecalho 3 bytes + ECC (BCH 32,24); 4 subpacotes de 7 bytes + ECC (BCH 64,56).
--   Escrito para o Timmy a partir da especificacao HDMI 1.3 (seccao 5.2, TERC4, pacotes).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_tx is
  generic (
    FREQ     : integer := 74250000;   -- relogio do ponto (Hz)
    VIC      : integer := 19;         -- 19 = 720p50, 17 = 576p50, 1 = 640x480p60
    LARGO    : boolean := true;       -- true = 16:9, false = 4:3
    SYNC_POS : boolean := true        -- polaridade do HSYNC (para achar o inicio)
  );
  port (
    clk      : in  std_logic;                       -- relogio do ponto
    r, g, b  : in  std_logic_vector(7 downto 0);
    de, hs, vs : in std_logic;                      -- hs/vs ja' com a polaridade do fio
    aud_l, aud_r : in std_logic_vector(15 downto 0); -- PCM com sinal (outro relogio, estavel entre amostras)
    aud_tog  : in  std_logic;                        -- muda a cada amostra nova (48 kHz)
    q0, q1, q2 : out std_logic_vector(9 downto 0)   -- canais 0 (azul), 1 (verde), 2 (vermelho)
  );
end entity;

architecture rtl of hdmi_tx is
  constant D_ATR : integer := 12;
  constant N_ACR : integer := 6144;                 -- 48 kHz
  constant CTS   : integer := FREQ / 1000;          -- FREQ * N / (128 * 48000)
  constant CS_BITS : std_logic_vector(39 downto 0) := x"C202004004";   -- (62) estado do canal, bit 0 primeiro

  type sv_arr is array (natural range <>) of std_logic_vector(7 downto 0);

  -- atrasos
  type v8_arr is array (1 to D_ATR) of std_logic_vector(7 downto 0);
  signal rd, gd, bd : v8_arr;
  signal ded, hsd, vsd : std_logic_vector(1 to D_ATR) := (others => '0');

  -- TERC4 (q[9:0])
  function terc4(x : std_logic_vector(3 downto 0)) return std_logic_vector is
  begin
    case x is
      when "0000" => return "1010011100";
      when "0001" => return "1001100011";
      when "0010" => return "1011100100";
      when "0011" => return "1011100010";
      when "0100" => return "0101110001";
      when "0101" => return "0100011110";
      when "0110" => return "0110001110";
      when "0111" => return "0100111100";
      when "1000" => return "1011001100";
      when "1001" => return "0100111001";
      when "1010" => return "0110011100";
      when "1011" => return "1011000110";
      when "1100" => return "1010001110";
      when "1101" => return "1001110001";
      when "1110" => return "0101100011";
      when others => return "1011000011";
    end case;
  end function;

  -- BCH: um passo do ECC (um bit de dados), e o ECC de n bits (LSB primeiro)
  function passo(e : std_logic_vector(7 downto 0); b : std_logic) return std_logic_vector is
    variable r : std_logic_vector(7 downto 0);
  begin
    r := '0' & e(7 downto 1);
    if (e(0) xor b) = '1' then r := r xor "10000011"; end if;
    return r;
  end function;
  function ecc(x : std_logic_vector) return std_logic_vector is
    variable e : std_logic_vector(7 downto 0) := (others => '0');
  begin
    for i in x'low to x'high loop e := passo(e, x(i)); end loop;
    return e;
  end function;

  function bytes2v(bs : sv_arr) return std_logic_vector is   -- byte 0 nos bits baixos
    variable v : std_logic_vector(bs'length * 8 - 1 downto 0);
  begin
    for i in 0 to bs'length - 1 loop v(i*8 + 7 downto i*8) := bs(bs'low + i); end loop;
    return v;
  end function;

  function soma(bs : sv_arr) return std_logic_vector is      -- checksum de InfoFrame
    variable s : unsigned(7 downto 0) := (others => '0');
  begin
    for i in bs'range loop s := s + unsigned(bs(i)); end loop;
    return std_logic_vector(0 - s);
  end function;

  function par(v : std_logic_vector) return std_logic is
    variable p : std_logic := '0';
  begin
    for i in v'range loop p := p xor v(i); end loop;
    return p;
  end function;

  -- pacote pronto a sair: cabecalho 32 bits, 4 subpacotes de 64 bits
  type sp_arr is array (0 to 3) of std_logic_vector(63 downto 0);
  type pkt_t is record h : std_logic_vector(31 downto 0); s : sp_arr; end record;
  signal pk1 : pkt_t;                                       -- o pacote 1 da ilha (constante, com ECC)

  function monta(hb : sv_arr; pb : sv_arr) return pkt_t is   -- hb 0..2, pb 0..27
    variable p : pkt_t;
    variable h : std_logic_vector(23 downto 0);
    variable s : std_logic_vector(55 downto 0);
  begin
    h := bytes2v(hb);
    p.h := ecc(h) & h;
    for j in 0 to 3 loop
      s := bytes2v(pb(j*7 to j*7 + 6));
      p.s(j) := ecc(s) & s;
    end loop;
    return p;
  end function;

  -- InfoFrames e ACR (constantes)
  function avi_pb return sv_arr is
    variable pb : sv_arr(0 to 27) := (others => x"00");
    variable hb : sv_arr(0 to 2) := (x"82", x"02", x"0D");
  begin
    pb(1) := x"10";                                         -- RGB, A0 = 1
    if LARGO then pb(2) := x"28"; else pb(2) := x"18"; end if;  -- 16:9 / 4:3, R = igual
    pb(3) := x"08";                                         -- (core 62) Q = RGB gama completa 0..255, como o NextNano
    pb(4) := std_logic_vector(to_unsigned(VIC, 8));
    pb(0) := soma(hb & pb(1 to 13));
    return pb;
  end function;
  function aif_pb return sv_arr is
    variable pb : sv_arr(0 to 27) := (others => x"00");
    variable hb : sv_arr(0 to 2) := (x"84", x"01", x"0A");
  begin
    pb(1) := x"11";                                         -- 2 canais, CT = 1 (PCM; era 0 = "ver o fluxo"), como o NextNano
    pb(0) := soma(hb & pb(1 to 10));
    return pb;
  end function;
  function acr_pb return sv_arr is
    variable pb : sv_arr(0 to 27) := (others => x"00");
    variable c : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(CTS, 20));
    variable n : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(N_ACR, 20));
  begin
    for j in 0 to 3 loop
      pb(j*7 + 1) := "0000" & c(19 downto 16);
      pb(j*7 + 2) := c(15 downto 8);
      pb(j*7 + 3) := c(7 downto 0);
      pb(j*7 + 4) := "0000" & n(19 downto 16);
      pb(j*7 + 5) := n(15 downto 8);
      pb(j*7 + 6) := n(7 downto 0);
    end loop;
    return pb;
  end function;
  constant P_AVI : pkt_t := monta((x"82", x"02", x"0D"), avi_pb);
  constant P_AIF : pkt_t := monta((x"84", x"01", x"0A"), aif_pb);
  constant P_ACR : pkt_t := monta((x"01", x"00", x"00"), acr_pb);

  -- audio
  signal tg : std_logic_vector(4 downto 0) := (others => '0');
  type amostra_arr is array (0 to 3) of std_logic_vector(31 downto 0);
  signal fifo : amostra_arr := (others => (others => '0'));
  signal nf : integer range 0 to 4 := 0;
  signal quadro : integer range 0 to 191 := 0;               -- bloco IEC 60958

  -- ilha
  signal hs_a, hs_a_d : std_logic := '0';
  signal t_il : integer range 0 to 127 := 127;               -- 127 = sem ilha
  signal linha : unsigned(1 downto 0) := "00";
  signal am_buf : amostra_arr;
  signal am_n : integer range 0 to 4 := 0;
  signal q_d0, q_d1, q_d2 : std_logic_vector(9 downto 0);
  signal ov0, ov1, ov2 : std_logic_vector(9 downto 0) := (others => '0');
  signal ov_on : std_logic := '0';
  signal e0, e1, e2 : std_logic_vector(9 downto 0);
  signal c0, c1, c2 : std_logic_vector(1 downto 0);
  signal de_c : std_logic;
  signal q_amostra0 : integer range 0 to 191 := 0;
  signal hb_r : sv_arr(0 to 2) := (others => x"00");         -- (esp58) o pacote 0 sem ECC (t_il = 1); ECC em t_il = 2
  signal pb_r : sv_arr(0 to 27) := (others => x"00");
  signal ov_on2 : std_logic := '0';                          -- (esp58) os simbolos da ilha atrasados 1 ciclo
  signal ov0_2, ov1_2, ov2_2 : std_logic_vector(9 downto 0) := (others => '0');   -- (o tmds_enc tem 2 andares)
  signal hsh : std_logic_vector(31 downto 0) := (others => '0');
  signal ssh : sp_arr := (others => (others => '0'));
  -- (esp60) o ECC do pacote 0 calcula-se bit a bit enquanto ele sai (ver abaixo)
  signal ech : std_logic_vector(7 downto 0) := (others => '0');
  type ecc_arr is array (0 to 3) of std_logic_vector(7 downto 0);
  signal ec : ecc_arr := (others => (others => '0'));
begin
  -- atraso do video
  process(clk)
  begin
    if rising_edge(clk) then
      rd(1) <= r; gd(1) <= g; bd(1) <= b;
      ded(1) <= de; hsd(1) <= hs; vsd(1) <= vs;
      for k in 2 to D_ATR loop
        rd(k) <= rd(k-1); gd(k) <= gd(k-1); bd(k) <= bd(k-1);
        ded(k) <= ded(k-1); hsd(k) <= hsd(k-1); vsd(k) <= vsd(k-1);
      end loop;
    end if;
  end process;

  -- amostras a 48 kHz: chegam do relogio do core; o "tog" muda a cada uma e os dados
  -- ficam parados ~20 us, por isso basta sincronizar o tog
  process(clk)
    variable n : integer range 0 to 4;
  begin
    if rising_edge(clk) then
      tg <= tg(3 downto 0) & aud_tog;
      n := nf;
      if t_il = 0 then n := 0; end if;                     -- a ilha levou as pendentes
      if tg(4) /= tg(3) then                               -- 3 ciclos de margem para os dados
        if n < 4 then fifo(n) <= aud_r & aud_l; n := n + 1; end if;
      end if;
      nf <= n;
    end if;
  end process;

  -- ilha de dados: comeca no inicio do HSYNC (no tempo atrasado)
  hs_a <= hsd(D_ATR) when SYNC_POS else not hsd(D_ATR);
  process(clk)
    variable hb : sv_arr(0 to 2);
    variable pb : sv_arr(0 to 27);
    variable fq : integer range 0 to 191;
    variable smp, smpr : std_logic_vector(23 downto 0);
    variable cb : std_logic;
  begin
    if rising_edge(clk) then
      hs_a_d <= hs_a;
      if hs_a = '1' and hs_a_d = '0' then
        t_il <= 0;
      elsif t_il /= 127 then
        if t_il = 75 then t_il <= 127; else t_il <= t_il + 1; end if;
      end if;

      if t_il = 0 then                                      -- guarda o que vai sair
        am_buf <= fifo; am_n <= nf; q_amostra0 <= quadro;
        if quadro + nf > 191 then quadro <= quadro + nf - 192; else quadro <= quadro + nf; end if;
        linha <= linha + 1;
      elsif t_il = 1 then                                   -- monta os pacotes
        -- pacote 0: amostras
        hb := (x"00", x"00", x"00"); pb := (others => x"00");
        if am_n > 0 then
          hb(0) := x"02";
          fq := q_amostra0;
          for j in 0 to 3 loop
            if j < am_n then
              hb(1)(j) := '1';
              if fq = 0 then hb(2)(4 + j) := '1'; end if;
              -- estado do canal IEC 60958 igual ao do NextNano (C202004004h): bit 2 = copia permitida,
              -- categoria 40h, 48 kHz (bits 24-27 = 0010), 16 bits (32-35 = 0010), fs original 48 kHz (36-39)
              if fq < 40 then cb := CS_BITS(fq); else cb := '0'; end if;
              smp := am_buf(j)(15 downto 0) & x"00";
              smpr := am_buf(j)(31 downto 16) & x"00";
              pb(j*7 + 0) := smp(7 downto 0);   pb(j*7 + 1) := smp(15 downto 8);  pb(j*7 + 2) := smp(23 downto 16);
              pb(j*7 + 3) := smpr(7 downto 0);  pb(j*7 + 4) := smpr(15 downto 8); pb(j*7 + 5) := smpr(23 downto 16);
              pb(j*7 + 6) := (par(smpr) xor cb) & cb & "00" & (par(smp) xor cb) & cb & "00";
              if fq = 191 then fq := 0; else fq := fq + 1; end if;
            end if;
          end loop;
        end if;
        hb_r <= hb; pb_r <= pb;
        case linha is
          when "01"   => pk1 <= P_AVI;
          when "11"   => pk1 <= P_AIF;
          when others => pk1 <= P_ACR;
        end case;
      end if;
    end if;
  end process;

  -- controlo e preambulos (no tempo atrasado)
  process(all)
    variable vid_pre, vid_gb, il_pre : boolean;
    variable fut : std_logic;
  begin
    fut := '0';
    for k in 2 to 9 loop fut := fut or ded(k); end loop;
    vid_gb  := ded(D_ATR) = '0' and (ded(D_ATR-1) = '1' or ded(D_ATR-2) = '1');
    vid_pre := ded(D_ATR) = '0' and not vid_gb and fut = '1';
    il_pre  := t_il <= 7;
    c0 <= vsd(D_ATR) & hsd(D_ATR);
    if vid_pre then c1 <= "01"; c2 <= "00";
    elsif il_pre then c1 <= "01"; c2 <= "01";
    else c1 <= "00"; c2 <= "00"; end if;
  end process;
  de_c <= ded(D_ATR);

  enc0: entity work.tmds_enc port map (clk => clk, de => de_c, d => bd(D_ATR), c => c0, q => e0);
  enc1: entity work.tmds_enc port map (clk => clk, de => de_c, d => gd(D_ATR), c => c1, q => e1);
  enc2: entity work.tmds_enc port map (clk => clk, de => de_c, d => rd(D_ATR), c => c2, q => e2);

  -- simbolos que substituem os do codificador (registados, como o tmds_enc).
  --   Os pacotes saem por registos de deslocamento: 1 bit do cabecalho e 2 de cada
  --   subpacote por ponto.
  --   (esp60) O ECC do pacote 0 (as amostras) ja' nao se calcula de uma vez (56 bits de XOR num
  --   ciclo: era o caminho mais lento do pclk, e numa compilacao do core 59 ficou a -0,47 ns e a
  --   TV perdia o sinal de vez em quando). Agora o BCH anda bit a bit ao ritmo da saida (1 bit do
  --   cabecalho e 2 de cada subpacote por ponto) e entra no registo de deslocamento mesmo antes
  --   de sair: o cabecalho em t_il = 33 (os 24 bits sairam), os subpacotes em 37 (56 bits).
  --   O pacote 1 (AVI / AIF / ACR) e' constante, com o ECC feito na compilacao.
  process(clk)
    variable x1, x2 : std_logic_vector(3 downto 0);
    variable syn : std_logic_vector(1 downto 0);
    variable gb : boolean;
    variable f : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      syn := vsd(D_ATR) & hsd(D_ATR);
      ov_on <= '0';
      gb := ded(D_ATR) = '0' and (ded(D_ATR-1) = '1' or ded(D_ATR-2) = '1');
      if t_il = 9 then                                      -- o pacote 0 sem ECC (ainda)
        hsh <= x"00" & bytes2v(hb_r); ech <= x"00";
        for j in 0 to 3 loop ssh(j) <= x"00" & bytes2v(pb_r(j*7 to j*7 + 6)); ec(j) <= x"00"; end loop;
      end if;
      if gb then                                            -- guarda do video
        ov_on <= '1'; ov0 <= "1011001100"; ov1 <= "0100110011"; ov2 <= "1011001100";
      elsif t_il = 8 or t_il = 9 or t_il = 74 or t_il = 75 then   -- guarda da ilha
        ov_on <= '1'; ov0 <= terc4("11" & syn); ov1 <= "0100110011"; ov2 <= "0100110011";
      elsif t_il >= 10 and t_il <= 73 then                  -- pacotes
        for j in 0 to 3 loop x1(j) := ssh(j)(0); x2(j) := ssh(j)(1); end loop;
        ov_on <= '1';
        if t_il = 10 then ov0 <= terc4('0' & hsh(0) & syn);
        else ov0 <= terc4('1' & hsh(0) & syn); end if;
        ov1 <= terc4(x1); ov2 <= terc4(x2);
        -- cabecalho: 1 bit por ponto, e o BCH a andar com ele
        f := passo(ech, hsh(0)); ech <= f;
        if t_il = 41 then hsh <= pk1.h;                     -- pacote seguinte
        elsif t_il = 33 then hsh <= x"000000" & f;          -- os 24 bits sairam: a seguir o ECC
        else hsh <= '0' & hsh(31 downto 1); end if;
        -- subpacotes: 2 bits por ponto
        for j in 0 to 3 loop
          f := passo(passo(ec(j), ssh(j)(0)), ssh(j)(1)); ec(j) <= f;
          if t_il = 41 then ssh(j) <= pk1.s(j);
          elsif t_il = 37 then ssh(j) <= x"00000000000000" & f;   -- os 56 bits sairam: a seguir o ECC
          else ssh(j) <= "00" & ssh(j)(63 downto 2); end if;
        end loop;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then ov_on2 <= ov_on; ov0_2 <= ov0; ov1_2 <= ov1; ov2_2 <= ov2; end if;
  end process;
  q0 <= ov0_2 when ov_on2 = '1' else e0;
  q1 <= ov1_2 when ov_on2 = '1' else e1;
  q2 <= ov2_2 when ov_on2 = '1' else e2;
end architecture;
