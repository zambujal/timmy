-- ponte_rapida.vhd - teste da ponte rapida (2026-10-24): os dados do ESP apanhados com o proprio relogio
-- do ESP (e nao amostrados a 54 MHz). Comandos (octal, modo 0, comando e endereco num ciclo cada):
--   03h escrever: os bytes seguintes devem ser uma sequencia LFSR (seguinte = f(anterior)): conta os bytes
--       e os que nao seguem a sequencia
--   04h ler: 2 ciclos de espera; a FPGA manda a sequencia LFSR (o ESP verifica-a), muda no flanco de descida
--   06h ler como o 04h, mas a FPGA muda os dados no flanco de SUBIDA (2026-10-24: escolher o melhor)
--   05h sair: a ponte normal volta a ouvir (ver o registo 5F da ponte_esp)
--   07h (2026-10-24) escrita em bloco: os bytes vao para uma fila de 2 KB (do relogio do ESP para os 54 MHz);
--       a ponte_esp tira-os de la' para a fila normal (SDRAM, RAM de video ou cartao, registo 39)
--   08h teste como o 03h, mas a FPGA le' os dados no flanco de DESCIDA (para os 40 MHz)
-- f(x) = (x >> 1) xor (B8h se x(0) = 1): periodo 255 (nunca 0).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ponte_rapida is
  port (
    sclk   : in  std_logic;
    cs     : in  std_logic;                       -- 1 = sem transaccao
    d      : in  std_logic_vector(7 downto 0);
    q      : out std_logic_vector(7 downto 0);
    oe     : out std_logic;
    sair_t : out std_logic;                       -- muda a cada comando 05h
    wb     : out std_logic_vector(23 downto 0);   -- bytes escritos (03h)
    we     : out std_logic_vector(15 downto 0);   -- bytes fora da sequencia
    rb     : out std_logic_vector(23 downto 0);   -- bytes lidos (04h/06h)
    -- fila de 2 KB do 07h, lado dos 54 MHz
    clk    : in  std_logic;
    tira   : in  std_logic;                       -- 1 ciclo: tira um byte (so' sem vazia)
    b_q    : out std_logic_vector(7 downto 0);    -- o byte tirado, no ciclo seguinte (com b_ok = 1)
    b_ok   : out std_logic;
    b_vazia: out std_logic;
    b_livres : out std_logic_vector(11 downto 0); -- lugares livres (0-2048)
    b_vis  : out std_logic                        -- muda a cada comando 07h (para a ponte_esp deixar de estar surda)
  );
end entity;

architecture rtl of ponte_rapida is
  function f(x : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    if x(0) = '1' then return ('0' & x(7 downto 1)) xor x"B8"; else return '0' & x(7 downto 1); end if;
  end function;
  signal k : unsigned(2 downto 0) := (others => '0');
  signal cmd, ant : std_logic_vector(7 downto 0) := (others => '0');
  signal tem_ant, sair_r, oe_r : std_logic := '0';
  signal wb_r, rb_r : unsigned(23 downto 0) := (others => '0');
  signal we_r : unsigned(15 downto 0) := (others => '0');
  signal lf, lf2 : std_logic_vector(7 downto 0) := x"01";
  signal oe2 : std_logic := '0';
  -- fila do 07h
  type fila_t is array (0 to 2047) of std_logic_vector(7 downto 0);
  signal fila : fila_t;
  signal bwp, brp, bwp_s : unsigned(11 downto 0) := (others => '0');
  signal bwg, bwg1, bwg2 : std_logic_vector(11 downto 0) := (others => '0');
  signal b_q_r : std_logic_vector(7 downto 0) := (others => '0');
  signal b_ok_r, vis_r : std_logic := '0';
  -- 08h: escrita lida no flanco de descida
  signal ant8 : std_logic_vector(7 downto 0) := (others => '0');
  signal tem8 : std_logic := '0';
  signal wb8, we8 : unsigned(15 downto 0) := (others => '0');
  function g2b(g : std_logic_vector(11 downto 0)) return unsigned is
    variable b : std_logic_vector(11 downto 0);
  begin
    b(11) := g(11);
    for i in 10 downto 0 loop b(i) := b(i + 1) xor g(i); end loop;
    return unsigned(b);
  end function;
begin
  -- os contadores do teste: 03h (subida) e 08h (descida) somados
  sair_t <= sair_r; wb <= std_logic_vector(wb_r + wb8); we <= std_logic_vector(we_r + we8); rb <= std_logic_vector(rb_r);
  oe <= oe_r or oe2;

  process(sclk, cs)
  begin
    if cs = '1' then
      k <= (others => '0'); tem_ant <= '0'; oe2 <= '0'; lf2 <= x"01";
    elsif rising_edge(sclk) then
      if cmd = x"06" and k >= 2 then
        oe2 <= '1';
        if k >= 3 then lf2 <= f(lf2); rb_r <= rb_r + 1; end if;
      end if;
      if k /= 7 then k <= k + 1; end if;
      if k = 0 then cmd <= d;
      elsif k = 1 then
        if cmd = x"05" then sair_r <= not sair_r; end if;
        if cmd = x"07" then vis_r <= not vis_r; end if;
      elsif cmd = x"03" then
        wb_r <= wb_r + 1;
        if tem_ant = '1' and d /= f(ant) then we_r <= we_r + 1; end if;
        ant <= d; tem_ant <= '1';
      end if;
    end if;
  end process;

  -- leitura: muda no flanco de descida (o ESP le' no de subida); liga a saida depois dos 2 de espera
  process(sclk, cs)
  begin
    if cs = '1' then
      oe_r <= '0'; lf <= x"01";
    elsif falling_edge(sclk) then
      if cmd = x"04" and k >= 3 then
        oe_r <= '1';
        if k >= 4 then lf <= f(lf); end if;
      end if;
    end if;
  end process;
  q <= lf2 when cmd = x"06" else lf;

  -- 08h: os dados lidos no flanco de descida (o ESP muda-os na descida tambem, mas com atraso dos fios)
  process(sclk, cs)
  begin
    if cs = '1' then
      tem8 <= '0';
    elsif falling_edge(sclk) then
      if cmd = x"08" and k >= 2 then
        wb8 <= wb8 + 1;
        if tem8 = '1' and d /= f(ant8) then we8 <= we8 + 1; end if;
        ant8 <= d; tem8 <= '1';
      end if;
    end if;
  end process;

  -- 07h: os dados para a fila (no relogio do ESP; o ponteiro passa para os 54 MHz em codigo Gray)
  process(sclk)
    variable n : unsigned(11 downto 0);
  begin
    if rising_edge(sclk) then
      if cs = '0' and cmd = x"07" and k >= 2 then
        fila(to_integer(bwp(10 downto 0))) <= d;
        n := bwp + 1; bwp <= n;
        bwg <= std_logic_vector(n xor ('0' & n(11 downto 1)));
      end if;
    end if;
  end process;
  process(clk)
  begin
    if rising_edge(clk) then
      bwg1 <= bwg; bwg2 <= bwg1; bwp_s <= g2b(bwg2);
      b_ok_r <= '0';
      if tira = '1' and bwp_s /= brp then
        b_q_r <= fila(to_integer(brp(10 downto 0))); b_ok_r <= '1'; brp <= brp + 1;
      end if;
    end if;
  end process;
  b_q <= b_q_r; b_ok <= b_ok_r; b_vis <= vis_r;
  b_vazia <= '1' when bwp_s = brp else '0';
  b_livres <= std_logic_vector(to_unsigned(2048, 12) - (bwp_s - brp));
end architecture;
