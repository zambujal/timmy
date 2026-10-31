-- ponte_esp.vhd: escravo SPI octal para o ESP32-S3 (o ESP e' o mestre, meio-duplex, modo 0).
-- Tudo no relogio de 54 MHz: o CLK, o CS e os dados do ESP sao sincronizados (testado ate' 10 MHz).
-- Cada transaccao (CS em baixo), um byte por cada flanco de subida do CLK (8 linhas):
--   flanco 1 = comando, flanco 2 = endereco (registo)
--   01h escrever: bytes seguintes -> registos(endereco), endereco + 1 (menos nos registos 33h/34h)
--   02h ler: 2 ciclos de espera (flancos 3 e 4); a FPGA prepara cada byte no flanco de subida anterior
--        ao que o ESP usa para o ler (um periodo de folga), endereco + 1
-- Registos:
--   00-0F memoria de teste (ler/escrever); 10-14 "TIMMY" (so' ler; o nome antigo do Timextenso, fica: e' o que o ESP procura)
--   20 bit 0 = linha IRQ; 21 contador que sobe a cada ~1,2 ms (so' ler)
--   22 estado (so' ler): bit 0 = 1 fila vazia (tudo escrito), bit 1 = fila cheia,
--      bit 2 = perdeu-se um byte (fila cheia); escrever qualquer coisa no 22 limpa o bit 2
--   30/31/32 ponteiro (bits 7-0, 15-8, 22-16): RAM de video (15 bits) ou SDRAM (23 bits)
--   33 escrever aqui -> RAM de video (BSRAM de 32K: 0000-3FFF = banco 5 = 4000h do Z80, 4000-7FFF = banco 7)
--   34 escrever aqui -> SDRAM (endereco fisico de 23 bits; 000000-007FFF = RAM do Z80 8000-FFFF no 48K)
--      Nos 33/34 o endereco do registo nao avanca: os bytes vao para uma fila de 64 e o ponteiro
--      avanca um por cada byte escrito. O ESP so' deve mudar o ponteiro com a fila vazia (22 bit 0)
--      e mandar no maximo 64 bytes de cada vez.
--   40 camada do ESP (camada_esp v2): bit 0 = camada L ligada, bit 1 = imagens 1 (L em 640000h e W em
--      6C0000h; 0 = 600000h e 680000h), bit 3 = janela W ligada;
--      ler: bit 2 = a imagem que o HDMI esta' a mostrar (so' troca no inicio do quadro: o ESP desenha na
--      outra e espera que o bit 2 mude antes de voltar a desenhar); bit 4 = janela a 2x (512x384; 0 = 3x)
--   41-43 cor 1 (R, G, B), 44-46 cor 2, 47-49 cor 3 (a cor 0 e' transparente)
--   4E bits 2-0 = cores 3, 2, 1 da camada L meio transparentes (3/4 a cor, 1/4 a janela ou o Spectrum)
--   4A/4B canto x da janela (bits 7-0, 10-8), 4C/4D canto y (bits 7-0, 9-8); por omissao 512, 72
--      Camada L: o ecra todo (1280x720 em 720p) a 2 bits por ponto, 320 bytes por linha.
--      Janela W: 256x192, 4 bytes por ponto (R, G, B, -), 1024 bytes por linha, mostrada a 3x3.
--   (v3, 2026-10-22) cartao SD, leitura da RAM de video, teclas:
--   50 cartao SD: bit 0 = o ESP fica com o cartao (o DivMMC do Z80 deixa de o ver), bit 1 = CS do cartao
--      activo, bit 2 = relogio rapido (13,5 MHz; 0 = 400 kHz, para a inicializacao)
--   51 escrever aqui -> bytes para o cartao (pela mesma fila de 64 do 33/34; a resposta deita-se fora)
--   53/54 ler N bytes do cartao (bits 7-0, 15-8; escrever o 54 comeca): manda FFh N vezes e guarda o que
--      vem na fila de leitura (comeca depois de a fila de escrita esvaziar)
--   37/38 ler N bytes da RAM de video a partir do ponteiro (escrever o 38 comeca) para a fila de leitura
--   52 ler aqui -> bytes da fila de leitura (64); 56 = quantos bytes la' estao
--   55 estado: bit 0 = cartao ocupado (a mandar ou a ler), bit 1 = leitura da RAM de video em curso
--   60-64 teclas do Spectrum carregadas pelo ESP (40 bits, como a matriz do teclado: 5 por fila,
--      fila 0 = bits 4-0 do 60 ...); 65 bit 0 = reset do Z80 (enquanto a 1), bit 1 = NMI (enquanto a 1),
--      bit 2 = as teclas do teclado so' vao para o ESP (o Z80 nao as ve'), bit 3 = Z80 a 14 MHz (turbo 4x),
--      bit 4 = parar o General Sound (como o ZX-UNO A0h bit 0 = 1), bit 6 = placa do 3.o AY (TurboSound Next)
--   66-6A (ler) as teclas carregadas no teclado (40 bits, como no 60-64; 1 = carregada)
--   6B (ler) o joystick (Kempston: bit 0 direita, 1 esquerda, 2 baixo, 3 cima, 4 fogo); com o 65 bit 2
--      o Z80 deixa de o ver
--   74-77 (ler) o joystick 0 tal como o BL616 o manda: estado (bits 0-3 dir esq baixo cima, 4-7 A B X Y),
--      X, Y, extra (os outros botoes)
--   78/79 (ler) a maquina: 78 = registo F3 (bit 7 Pentagon, bit 5 ZX), 79 bit 0 = modo 128 (F4 = F0),
--      bit 1 = TC2068 (DivTIESUS), bit 7 = GS a correr
--   7A (ler) a velocidade do Z80: 1 = 3,5 MHz, 2 = 7, 4 = 14 (Win+'+' / Win+'-', botoes, ou o ESP)
--   6C (ler) atalhos do teclado USB: bit 0 = Win+J, bit 1 = Win+S, bit 2 = Win+C, 3 Win+'+', 4 Win+'-', 5 Win+R, 6 Win+M, 7 F1 (o Spectrum nao os ve');
--      (v6) cada atalho fica a 1 ate' o ESP ler o 6C, mesmo que ja' o tenham largado
--   6D (ler) mais atalhos (como o 6C): bit 0 = F2, 1 Page Up, 2 Page Down, 3 Home, 4 End, 5 F3, 6 F4
--   39 (2026-10-24) escrita em bloco (comando 07h a 26,7 MHz, depois de 5F = 1): destino 00 SDRAM, 01 RAM de
--      video, 10 cartao (como 34/33/51; o ponteiro avanca igual); ler 39/3A = lugares livres na fila de 2 KB.
--      A ponte volta a ouvir sozinha quando o CS sobe depois do 07h. O 22 bit 0 conta tambem com esta fila.
--   3B (ler) F5 (bit 0) e F6 (bit 1), guardados ate' ler (o modo musica do ESP)
--   23 (escrever) / 24 (ler, o endereco nao avanca) os AY: 16 bytes, AY 1 e AY 2: periodo A, B, C (12 bits:
--      byte baixo, nibble alto), volume A, B, C (5 bits) - ver core_timextenso (ay_vis)
--   58-5A bytes escritos na ponte rapida (03h), 5B-5C os fora da sequencia, 5D-5F bytes lidos (04h);
--   5F escrita bit 0 = esta ponte fica surda (ate' ao comando 05h da ponte rapida, ou 1,2 s)
--   6E escrita: impulsos da cassete (2 bytes cada); leitura bit 0 = a tocar. 6F escrita bit 0 = parar; leitura = livres
--   (v4, 2026-10-22) caixa de correio Z80 <-> ESP (portos do Z80 EE3Bh = 60987 e EF3Bh = 61243):
--      Z80: OUT EF3B,b  -> b para o pedido (64 bytes, um a seguir ao outro)
--           OUT EE3B,c  -> comando c: o pedido fica a' espera do ESP (linha IRQ a 1), e os indices do
--                          pedido e da resposta voltam a 0
--           IN  EE3B    -> estado: bit 0 = pedido a' espera do ESP, bit 1 = resposta pronta,
--                          bit 7 = ESP presente (registo 73)
--           IN  EF3B    -> o byte seguinte da resposta (64 bytes)
--   70 (ler) comando; 71 (ler) estado como o EE3B; 72 (ler) quantos bytes tem o pedido
--   71 (escrever) bit 0 = 1: a resposta esta' pronta (o pedido deixa de estar a' espera)
--   73 (escrever) bit 0 = ESP presente
--   80-BF (ler) o pedido; C0-FF (escrever) a resposta
--   (v5, 2026-10-23) UART do ZX-UNO (o Z80 ve' os registos C6h/C7h pelas FC3B/FD3B), filas de 64:
--      7B (ler) quantos bytes o Z80 escreveu (fila Z80 -> ESP); 7C (ler) o byte seguinte dessa fila
--      (o endereco nao avanca, como o 52); 7D (escrever) bytes para o Z80 (o endereco nao avanca;
--      perdem-se com a fila cheia); 7E (ler) lugares livres na fila para o Z80
--      Z80: C7 = bit 7 ha' byte para ler, bit 6 a fila para o ESP esta' cheia (como o "a enviar")
-- Proteccao: a FPGA so' conduz os dados com o DIR a 1 (o ESP poe-no a 1 so' durante as leituras).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ponte_esp is
  port (
    clk     : in    std_logic;                       -- 54 MHz
    esp_clk : in    std_logic;
    esp_cs  : in    std_logic;                       -- 0 = transaccao
    esp_dir : in    std_logic;                       -- 1 = o ESP esta' a ler: so' assim a FPGA pode conduzir os dados
    esp_d   : inout std_logic_vector(7 downto 0);
    esp_irq : out   std_logic;
    -- escritas para o core (um byte de cada vez; p_ack = 1 no ciclo em que o core o aceita)
    p_req   : out   std_logic;
    p_vram  : out   std_logic;                       -- 1 = RAM de video, 0 = SDRAM
    p_a     : out   std_logic_vector(22 downto 0);
    p_d     : out   std_logic_vector(7 downto 0);
    p_ack   : in    std_logic := '0';
    -- (esp43) as escritas na SDRAM juntam-se em palavras de 32 bits (os bytes seguidos da mesma palavra):
    -- 4 bytes por acesso em vez de 1. p_req/p_ack ficam so' para a RAM de video.
    p_wreq  : out   std_logic;
    p_wa    : out   std_logic_vector(22 downto 0);
    p_wd    : out   std_logic_vector(31 downto 0);
    p_wbe   : out   std_logic_vector(3 downto 0);
    p_wack  : in    std_logic := '0';
    -- camada do ESP
    c_lig, c_sel, c_jan : out std_logic;
    c_2x    : out std_logic;                         -- janela a 2x (registo 40 bit 4)
    c_meio  : out std_logic_vector(2 downto 0);
    c_w16   : out std_logic;
    -- (esp44) 4F bit 1 = a janela com escolha propria, bits 3-2 = a imagem pedida (0-2); ler bits 5-4 = a mostrada
    c_wsep  : out std_logic;
    c_widx  : out std_logic_vector(1 downto 0);
    c_wmostra : in std_logic_vector(1 downto 0) := "00";
    -- (esp46) o som do ESP: 2A bit 0 = a tocar; 2B/2C = amostras por segundo; ler 2D/2E = a amostra seguinte
    -- (indice no anel de 64K palavras em 7C0000h)
    mp_on   : out std_logic;
    mp_alto : out std_logic;                         -- (esp49) 2A bit 1 = o som do ESP no volume todo (0 = metade)
    mp_rate : out std_logic_vector(15 downto 0);
    mp_idx  : in  std_logic_vector(15 downto 0) := (others => '0');                         -- (esp43) janela a 16 bits por ponto (RGB565, registo 4F bit 0)      -- cores 3..1 da camada L meio transparentes (registo 4E)
    c_wx : out std_logic_vector(10 downto 0);
    c_wy : out std_logic_vector(9 downto 0);
    c_ativa : in std_logic := '0';                   -- imagem que o HDMI esta' a mostrar (muda no inicio do quadro)
    c_cor1, c_cor2, c_cor3 : out std_logic_vector(23 downto 0);
    -- leitura da RAM de video (o core responde com p_rv = 1 e o byte em p_rd, um ciclo depois)
    p_rreq  : out   std_logic;
    p_rv    : in    std_logic := '0';
    p_rd    : in    std_logic_vector(7 downto 0) := (others => '0');
    -- cartao SD
    sd_meu  : out   std_logic;                       -- 1 = o ESP pede o cartao (o top da'-lho quando o Z80 o largar)
    sd_dado : in    std_logic := '1';                -- (63) 1 = os pinos do cartao ja' sao do ESP (registo 50 bit 3)
    sd_cs_n, sd_sclk, sd_mosi : out std_logic;
    sd_miso : in    std_logic := '1';
    -- teclas, reset e NMI
    k_mat   : out   std_logic_vector(39 downto 0);
    k_rst, k_nmi : out std_logic;
    k_in    : in    std_logic_vector(39 downto 0) := (others => '0');   -- teclas carregadas no teclado (USB e outros)
    k_cap   : out   std_logic;                                          -- 1 = as teclas so' vao para o ESP
    k_turbo : out   std_logic;                                          -- 1 = o Z80 a 14 MHz (registo 65 bit 3)
    k_gspara: out   std_logic;                                          -- 1 = parar o General Sound (registo 65 bit 4)
    k_ay3   : out   std_logic;                                          -- 1 = placa do 3.o AY ligada (registo 65 bit 6)
    k_joy   : in    std_logic_vector(7 downto 0) := (others => '0');    -- joystick (Kempston, 1 = carregado)
    k_atal  : in    std_logic_vector(20 downto 0) := (others => '0');           -- Win+J, Win+S, Win+C, Win+'+', Win+'-', Win+R
    k_jcru  : in    std_logic_vector(31 downto 0) := (others => '0');
    k_ay    : in    std_logic_vector(191 downto 0) := (others => '0');   -- (2026-10-24) os AY 1 e 2 (registo 24)   -- joystick 0 tal como vem do BL616
    k_maq   : in    std_logic_vector(15 downto 0) := (others => '0');   -- a maquina (core: maq_st)
    k_vel   : in    std_logic_vector(3 downto 0) := "0001";             -- MHz do Z80 / 3,5 (1, 2, 4 ou 8)
    -- cassete (2026-10-24): 6E = impulsos (byte baixo, byte alto; o endereco nao avanca),
    -- 6F escrita bit 0 = parar e esvaziar; leitura 6F = lugares livres, 6E bit 0 = a tocar
    cs_wr    : out   std_logic;
    cs_d     : out   std_logic_vector(15 downto 0);
    cs_limpa : out   std_logic;
    cs_livres: in    std_logic_vector(7 downto 0) := x"FF";
    cs_ativa : in    std_logic := '0';
    -- caixa de correio (lado do Z80, no mesmo relogio)
    z_wr    : in    std_logic := '0';
    z_rd    : in    std_logic := '0';
    z_sel   : in    std_logic := '0';
    z_d     : in    std_logic_vector(7 downto 0) := (others => '0');
    z_q     : out   std_logic_vector(7 downto 0);
    -- UART do ZX-UNO (lado do Z80)
    u_wr    : in    std_logic := '0';
    u_rd    : in    std_logic := '0';
    u_dat   : in    std_logic := '0';
    u_q     : out   std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of ponte_esp is
  signal c_s, s_s : std_logic_vector(2 downto 0) := (others => '1');
  signal dir_s : std_logic_vector(1 downto 0) := (others => '0');
  signal d_s1, d_s2 : std_logic_vector(7 downto 0) := (others => '0');
  type reg_t is array (0 to 15) of std_logic_vector(7 downto 0);
  signal mem : reg_t := (others => (others => '0'));
  signal n : integer range 0 to 7 := 0;
  signal cmd, ender, dout : std_logic_vector(7 downto 0) := (others => '0');
  signal oe, irq_r : std_logic := '0';
  signal cont : unsigned(23 downto 0) := (others => '0');
  -- fila de 64 bytes (bits 9-8 = destino: 00 SDRAM, 01 RAM de video, 10 cartao SD)
  type fila_t is array (0 to 63) of std_logic_vector(9 downto 0);
  signal fila : fila_t;
  signal wp, rp : unsigned(6 downto 0) := (others => '0');
  signal ptr : unsigned(22 downto 0) := (others => '0');
  -- (esp43) a palavra a juntar (pk) e a que esta' a ser escrita (o)
  signal pk_v, o_v, toma_sd : std_logic := '0';
  signal pk_a, o_a : unsigned(22 downto 2) := (others => '0');
  signal pk_d, o_d : std_logic_vector(31 downto 0) := (others => '0');
  signal pk_be, o_be : std_logic_vector(3 downto 0) := "0000";
  signal pk_t : unsigned(3 downto 0) := (others => '0');
  signal perdeu : std_logic := '0';
  signal vazia, cheia : std_logic;
  signal cabeca : std_logic_vector(9 downto 0);
  -- fila de leitura (cartao SD ou RAM de video -> ESP)
  type rx_t is array (0 to 63) of std_logic_vector(7 downto 0);
  signal rx : rx_t;
  signal rwp, rrp : unsigned(6 downto 0) := (others => '0');
  signal rx_n : unsigned(6 downto 0);
  -- cartao SD
  signal sd_ctl : std_logic_vector(2 downto 0) := "000";
  signal sd_n, vr_n : unsigned(15 downto 0) := (others => '0');
  signal sd_lo, vr_lo : std_logic_vector(7 downto 0) := (others => '0');
  signal sd_ativo, sd_ler, sclk_r, mosi_r : std_logic := '0';
  signal sd_div : integer range 0 to 127 := 0;
  signal sd_bit : integer range 0 to 7 := 0;
  signal sd_fase : std_logic := '0';
  signal sh_o, sh_i : std_logic_vector(7 downto 0) := (others => '1');
  signal miso_s : std_logic_vector(1 downto 0) := "11";
  signal sd_toma : std_logic;
  -- teclas
  signal kmat_r : std_logic_vector(39 downto 0) := (others => '0');
  signal r65 : std_logic_vector(6 downto 0) := "0000000";
  signal kin_s : std_logic_vector(39 downto 0) := (others => '0');
  signal joy_s : std_logic_vector(7 downto 0) := (others => '0');
  signal atal_s, atal_l : std_logic_vector(20 downto 0) := (others => '0');
  signal jcru_s : std_logic_vector(31 downto 0) := (others => '0');
  signal maq_s : std_logic_vector(15 downto 0) := (others => '0');
  signal vel_s : std_logic_vector(3 downto 0) := "0001";
  signal cs_lo : std_logic_vector(7 downto 0) := (others => '0');
  signal ay_s : std_logic_vector(191 downto 0) := (others => '0');
  signal ay_i : unsigned(4 downto 0) := (others => '0');
  signal cs_fase, cs_wr_r, cs_limpa_r : std_logic := '0';
  signal cs_d_r : std_logic_vector(15 downto 0) := (others => '0');
  signal cs_liv_s : std_logic_vector(7 downto 0) := x"FF";
  signal cs_atv_s : std_logic := '0';
  -- (2026-10-24) teste da ponte rapida (ponte_rapida, no relogio do ESP); 5F bit 0 = esta ponte fica surda
  signal surdo : std_logic := '0';
  signal f_q : std_logic_vector(7 downto 0);
  signal f_oe, f_sair : std_logic;
  signal f_sair_s : std_logic_vector(2 downto 0) := (others => '0');
  signal f_wb, f_rb, f_wb_s, f_rb_s : std_logic_vector(23 downto 0);
  signal f_we, f_we_s : std_logic_vector(15 downto 0);
  signal surdo_t : unsigned(25 downto 0) := (others => '0');
  -- (2026-10-24) escrita em bloco (07h da ponte rapida, 26,7 MHz): fila de 2 KB -> a fila normal
  signal b_tira, b_ok, b_vazia, b_vis, b_pend : std_logic := '0';
  signal b_q : std_logic_vector(7 downto 0);
  signal b_livres : std_logic_vector(11 downto 0);
  signal b_vis_s : std_logic_vector(2 downto 0) := (others => '0');
  signal b_vis_g : std_logic := '0';                      -- o b_vis quando ficou surda
  signal b_dest : std_logic_vector(1 downto 0) := "00";   -- registo 39: 00 SDRAM, 01 RAM de video, 10 cartao
  type cor_t is array (0 to 8) of std_logic_vector(7 downto 0);
  signal cores : cor_t := (x"FF", x"FF", x"FF",  x"FF", x"D0", x"00",  x"10", x"10", x"10");  -- branco, amarelo, quase preto
  signal r40 : std_logic_vector(4 downto 0) := "00000";
  signal r4e : std_logic_vector(2 downto 0) := "000";
  signal r4f : std_logic_vector(3 downto 0) := "0000";
  signal wm_s1, wm_s2 : std_logic_vector(1 downto 0) := "00";
  signal mp_on_r, mp_alto_r : std_logic := '0';
  signal mp_rate_r : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(44100, 16));
  signal mp_idx_s : std_logic_vector(15 downto 0) := (others => '0');
  -- (esp44) escrita em rectangulo: 26/27 = largura (bytes; 0 = desligado), 28/29 = passo (bytes por linha).
  -- Depois de cada largura de bytes escritos o ponteiro salta para o inicio da linha + passo.
  signal r_larg, r_passo, r_cnt : unsigned(15 downto 0) := (others => '0');
  signal r_lin : unsigned(22 downto 0) := (others => '0');
  signal wx_r : std_logic_vector(10 downto 0) := std_logic_vector(to_unsigned(512, 11));
  signal wy_r : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(72, 10));
  signal at_s : std_logic_vector(1 downto 0) := "00";
  -- caixa de correio
  signal req, rep : rx_t;
  signal zwi, zri, mb_n : unsigned(5 downto 0) := (others => '0');
  signal mb_cmd : std_logic_vector(7 downto 0) := (others => '0');
  signal pedido, pronto, vivo, zw_d, zr_d, zr_sel : std_logic := '0';
  signal mb_est : std_logic_vector(7 downto 0);
  -- UART
  signal ut, ur : rx_t;                                -- ut: Z80 -> ESP, ur: ESP -> Z80
  signal utw, utr, urw, urr, ut_n, ur_n : unsigned(6 downto 0) := (others => '0');
  signal uw_d, ud_d, urd_sel, ur_tem : std_logic := '0';
begin
  c_lig <= r40(0); c_sel <= r40(1); c_jan <= r40(3); c_2x <= r40(4); c_meio <= r4e; mp_on <= mp_on_r; mp_alto <= mp_alto_r; mp_rate <= mp_rate_r;
  c_w16 <= r4f(0); c_wsep <= r4f(1); c_widx <= r4f(3 downto 2); c_wx <= wx_r; c_wy <= wy_r;
  c_cor1 <= cores(0) & cores(1) & cores(2);
  c_cor2 <= cores(3) & cores(4) & cores(5);
  c_cor3 <= cores(6) & cores(7) & cores(8);
  esp_d   <= dout when oe = '1' and dir_s(1) = '1' else
             f_q  when f_oe = '1' and esp_dir = '1' else (others => 'Z');
  rap: entity work.ponte_rapida port map (sclk => esp_clk, cs => esp_cs, d => esp_d, q => f_q, oe => f_oe,
                                          sair_t => f_sair, wb => f_wb, we => f_we, rb => f_rb,
                                          clk => clk, tira => b_tira, b_q => b_q, b_ok => b_ok, b_vazia => b_vazia,
                                          b_livres => b_livres, b_vis => b_vis);
  -- tira da fila de 2 KB so' com lugar na fila normal (um de cada vez: o byte chega no ciclo seguinte)
  b_tira <= '1' when b_vazia = '0' and b_pend = '0' and b_ok = '0' and (wp - rp) < 60 else '0';
  esp_irq <= irq_r or pedido;
  mb_est  <= vivo & "00000" & pronto & pedido;
  z_q     <= rep(to_integer(zri)) when z_sel = '1' else mb_est;
  ut_n    <= utw - utr;
  ur_n    <= urw - urr;
  u_q     <= ur(to_integer(urr(5 downto 0))) when u_dat = '1' else
             ur_tem & ut_n(6) & "000000";
  ur_tem  <= '0' when ur_n = 0 else '1';

  vazia  <= '1' when wp = rp else '0';
  cheia  <= '1' when (wp - rp) = 64 else '0';
  cabeca <= fila(to_integer(rp(5 downto 0)));
  p_req  <= '1' when vazia = '0' and cabeca(9 downto 8) = "01" and pk_v = '0' and o_v = '0' else '0';
  -- um byte da SDRAM entra na palavra se e' da mesma palavra e o lugar dele esta' livre, ou se a palavra
  -- pode sair (a de escrita esta' livre) para comecar outra
  toma_sd <= '1' when vazia = '0' and cabeca(9 downto 8) = "00" and
                      (pk_v = '0' or o_v = '0' or (ptr(22 downto 2) = pk_a and pk_be(to_integer(ptr(1 downto 0))) = '0')) else '0';
  p_wreq <= o_v; p_wa <= std_logic_vector(o_a) & "00"; p_wd <= o_d; p_wbe <= o_be;
  p_vram <= cabeca(8);
  rx_n   <= rwp - rrp;
  -- leitura da RAM de video: so' com a fila de escrita vazia e lugar na fila de leitura
  p_rreq <= '1' when vr_n /= 0 and vazia = '1' and rx_n < 63 else '0';
  sd_meu <= sd_ctl(0); sd_cs_n <= not sd_ctl(1); sd_sclk <= sclk_r; sd_mosi <= mosi_r;
  k_mat <= kmat_r; k_rst <= r65(0); k_nmi <= r65(1); k_cap <= r65(2); k_turbo <= r65(3); k_gspara <= r65(4); k_ay3 <= r65(6);
  -- o motor do cartao pega no byte da cabeca da fila (destino 10)
  sd_toma <= '1' when sd_ativo = '0' and vazia = '0' and cabeca(9) = '1' else '0';
  p_d    <= cabeca(7 downto 0);
  p_a    <= std_logic_vector(ptr);
  cs_wr <= cs_wr_r; cs_d <= cs_d_r; cs_limpa <= cs_limpa_r;

  process(clk)
    variable v, a : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      cs_wr_r <= '0'; cs_limpa_r <= '0';               -- impulsos de 1 ciclo
      -- teste da ponte rapida: os contadores so' se leem com a ponte parada; surda ate' ao comando 05h
      -- ou 1,2 s (se o ESP nao conseguir mandar o 05h a essa velocidade)
      f_sair_s <= f_sair_s(1 downto 0) & f_sair; f_wb_s <= f_wb; f_we_s <= f_we; f_rb_s <= f_rb;
      b_vis_s <= b_vis_s(1 downto 0) & b_vis;
      b_pend <= b_tira;
      if b_ok = '1' then                               -- o byte da fila de 2 KB vai para a fila normal
        fila(to_integer(wp(5 downto 0))) <= b_dest & b_q; wp <= wp + 1;
      end if;
      if surdo = '1' then
        surdo_t <= surdo_t + 1;
        -- volta a ouvir: com o 05h, com o CS em alto depois de um 07h, ou ao fim de 1,2 s
        if f_sair_s(2) /= f_sair_s(1) or surdo_t = 2**26 - 1 or (b_vis_s(2) /= b_vis_g and s_s(1) = '1') then surdo <= '0'; end if;
      else
        surdo_t <= (others => '0');
      end if;
      cont <= cont + 1;
      at_s <= at_s(0) & c_ativa;
      wm_s1 <= c_wmostra; wm_s2 <= wm_s1;
      if dir_s(1) = '0' then mp_idx_s <= mp_idx; end if;   -- (fica parado durante uma leitura: os 2 bytes batem)
      c_s <= c_s(1 downto 0) & esp_clk;
      s_s <= s_s(1 downto 0) & esp_cs;
      dir_s <= dir_s(0) & esp_dir;
      d_s1 <= esp_d; d_s2 <= d_s1;
      -- caixa de correio, lado do Z80: OUT no inicio, IN avanca no fim
      atal_l <= atal_l or atal_s;                    -- (v6) guardado ate' o ESP ler
      kin_s <= k_in; joy_s <= k_joy; atal_s <= k_atal; jcru_s <= k_jcru; maq_s <= k_maq; vel_s <= k_vel; ay_s <= k_ay; cs_liv_s <= cs_livres; cs_atv_s <= cs_ativa;
      zw_d <= z_wr; zr_d <= z_rd;
      if z_rd = '1' then zr_sel <= z_sel; end if;
      if z_wr = '1' and zw_d = '0' then
        if z_sel = '1' then
          req(to_integer(zwi)) <= z_d; if zwi /= 63 then zwi <= zwi + 1; end if;
        else
          mb_cmd <= z_d; mb_n <= zwi; zwi <= (others => '0'); zri <= (others => '0');
          pedido <= '1'; pronto <= '0';
        end if;
      end if;
      if z_rd = '0' and zr_d = '1' and zr_sel = '1' and zri /= 63 then zri <= zri + 1; end if;
      -- UART, lado do Z80: OUT C6 no inicio poe na fila para o ESP; IN C6 tira da fila no fim
      uw_d <= u_wr; ud_d <= u_rd;
      if u_rd = '1' then urd_sel <= u_dat; end if;
      if u_wr = '1' and uw_d = '0' and ut_n /= 64 then ut(to_integer(utw(5 downto 0))) <= z_d; utw <= utw + 1; end if;
      if u_rd = '0' and ud_d = '1' and urd_sel = '1' and ur_n /= 0 then urr <= urr + 1; end if;
      -- o core aceitou o byte da cabeca da fila
      if p_ack = '1' and vazia = '0' then
        rp <= rp + 1;
        if r_larg /= 0 and r_cnt = r_larg - 1 then ptr <= r_lin + r_passo; r_lin <= r_lin + r_passo; r_cnt <= (others => '0');
        else ptr <= ptr + 1; r_cnt <= r_cnt + 1; end if;
      end if;
      -- (esp43) as palavras da SDRAM
      if p_wack = '1' then o_v <= '0'; end if;
      if toma_sd = '1' then
        rp <= rp + 1; pk_t <= (others => '0');
        if r_larg /= 0 and r_cnt = r_larg - 1 then ptr <= r_lin + r_passo; r_lin <= r_lin + r_passo; r_cnt <= (others => '0');
        else ptr <= ptr + 1; r_cnt <= r_cnt + 1; end if;
        if pk_v = '1' and ptr(22 downto 2) = pk_a and pk_be(to_integer(ptr(1 downto 0))) = '0' then
          for k in 0 to 3 loop
            if to_integer(ptr(1 downto 0)) = k then pk_be(k) <= '1'; pk_d(k * 8 + 7 downto k * 8) <= cabeca(7 downto 0); end if;
          end loop;
        else
          if pk_v = '1' then o_v <= '1'; o_a <= pk_a; o_d <= pk_d; o_be <= pk_be; end if;   -- (o_v estava a 0)
          pk_v <= '1'; pk_a <= ptr(22 downto 2);
          for k in 0 to 3 loop
            if to_integer(ptr(1 downto 0)) = k then pk_be(k) <= '1'; pk_d(k * 8 + 7 downto k * 8) <= cabeca(7 downto 0);
            else pk_be(k) <= '0'; end if;
          end loop;
        end if;
      elsif pk_v = '1' and o_v = '0' and (pk_be = "1111" or pk_t = 15 or (vazia = '0' and cabeca(9 downto 8) /= "00")) then
        o_v <= '1'; o_a <= pk_a; o_d <= pk_d; o_be <= pk_be; pk_v <= '0';
      elsif pk_v = '1' and pk_t /= 15 then
        pk_t <= pk_t + 1;
      end if;
      -- leitura da RAM de video: chegou o byte
      if p_rv = '1' then
        rx(to_integer(rwp(5 downto 0))) <= p_rd; rwp <= rwp + 1;
        ptr <= ptr + 1; vr_n <= vr_n - 1;
      end if;
      -- motor SPI do cartao (modo 0): o MOSI muda com o SCLK em baixo, o MISO le'-se na subida
      miso_s <= miso_s(0) & sd_miso;
      if sd_ativo = '0' then
        sclk_r <= '0';
        if sd_toma = '1' then
          sh_o <= cabeca(7 downto 0); rp <= rp + 1; sd_ler <= '0';
          sd_ativo <= '1'; sd_bit <= 7; sd_fase <= '0'; sd_div <= 0; mosi_r <= cabeca(7);
        elsif sd_n /= 0 and vazia = '1' and rx_n < 63 then
          sh_o <= x"FF"; sd_ler <= '1'; sd_n <= sd_n - 1;
          sd_ativo <= '1'; sd_bit <= 7; sd_fase <= '0'; sd_div <= 0; mosi_r <= '1';
        end if;
      else
        if (sd_ctl(2) = '1' and sd_div = 1) or (sd_ctl(2) = '0' and sd_div = 67) then
          sd_div <= 0;
          if sd_fase = '0' then
            sclk_r <= '1'; sd_fase <= '1';
          else
            -- o MISO le'-se no fim da metade alta (o cartao mudou-o na descida anterior)
            sclk_r <= '0'; sd_fase <= '0';
            sh_i <= sh_i(6 downto 0) & miso_s(0);
            if sd_bit = 0 then
              sd_ativo <= '0';
              if sd_ler = '1' then rx(to_integer(rwp(5 downto 0))) <= sh_i(6 downto 0) & miso_s(0); rwp <= rwp + 1; end if;
            else
              sd_bit <= sd_bit - 1; sh_o <= sh_o(6 downto 0) & '1'; mosi_r <= sh_o(6);
            end if;
          end if;
        else
          sd_div <= sd_div + 1;
        end if;
      end if;
      if s_s(1) = '1' then
        n <= 0; oe <= '0';
      elsif surdo = '0' and c_s(2) = '0' and c_s(1) = '1' then   -- flanco de subida do CLK do ESP
        if n /= 7 then n <= n + 1; end if;
        -- leituras (v3b, 2026-10-22): o byte que o ESP vai ler no flanco de subida seguinte prepara-se ja'
        -- neste flanco de subida (um periodo inteiro de folga; antes era no de descida, meio periodo, e a
        -- 10 MHz o 1.o byte podia vir do pedido anterior). Flancos: 1 comando, 2 endereco, 3-4 espera,
        -- dados a partir do 5; aqui no 4 (n = 3) o 1.o byte, depois um por flanco.
        if cmd = x"02" and n >= 3 then
          oe <= '1';
          if n = 3 then a := ender; else a := std_logic_vector(unsigned(ender) + 1); end if;
          if ender = x"7C" then
            -- UART: a fila Z80 -> ESP, como o 52
            if n >= 4 and ut_n /= 0 then
              utr <= utr + 1; v := ut(to_integer(utr(5 downto 0) + 1));
            else
              v := ut(to_integer(utr(5 downto 0)));
            end if;
          elsif ender = x"24" then
            -- (2026-10-24) os AY para as barras do ESP: 16 bytes seguidos (o endereco nao avanca; 23 = volta ao 1.o)
            if n >= 4 then ay_i <= ay_i + 1; a := std_logic_vector(resize(ay_i + 1, 8)); else a := std_logic_vector(resize(ay_i, 8)); end if;
            -- (esp46) 24 bytes: os 3 AY
            if unsigned(a(4 downto 0)) > 23 then a := x"17"; end if;
            v := ay_s(to_integer(unsigned(a(4 downto 0))) * 8 + 7 downto to_integer(unsigned(a(4 downto 0))) * 8);
          elsif ender = x"52" then
            -- fila de leitura: o endereco nao avanca; o byte lido sai da fila e mostra-se o seguinte
            if n >= 4 and rx_n /= 0 then
              rrp <= rrp + 1; v := rx(to_integer(rrp(5 downto 0) + 1));
            else
              v := rx(to_integer(rrp(5 downto 0)));
            end if;
          else
            if n >= 4 then ender <= a; end if;
              case a is
                when x"10" => v := x"54";   -- T
                when x"11" => v := x"49";   -- I
                when x"12" => v := x"4D";   -- M
                when x"13" => v := x"4D";   -- M
                when x"14" => v := x"59";   -- Y
                when x"20" => v := "0000000" & irq_r;
                when x"21" => v := std_logic_vector(cont(23 downto 16));
                when x"22" => v := "00000" & perdeu & cheia & (vazia and b_vazia and not b_pend and not b_ok and not pk_v and not o_v);
                when x"39" => v := b_livres(7 downto 0);
                when x"3A" => v := "0000" & b_livres(11 downto 8);
                when x"30" => v := std_logic_vector(ptr(7 downto 0));
                when x"31" => v := std_logic_vector(ptr(15 downto 8));
                when x"32" => v := '0' & std_logic_vector(ptr(22 downto 16));
                when x"40" => v := "000" & r40(4) & r40(3) & at_s(1) & r40(1 downto 0);   -- bit 2 = imagens mostradas
                when x"4E" => v := "00000" & r4e;
                when x"4F" => v := "00" & wm_s2 & r4f;
                when x"26" => v := std_logic_vector(r_larg(7 downto 0));
                when x"2A" => v := "000000" & mp_alto_r & mp_on_r;
                when x"2B" => v := mp_rate_r(7 downto 0);
                when x"2C" => v := mp_rate_r(15 downto 8);
                when x"2D" => v := mp_idx_s(7 downto 0);
                when x"2E" => v := mp_idx_s(15 downto 8);
                when x"4A" => v := wx_r(7 downto 0);
                when x"4B" => v := "00000" & wx_r(10 downto 8);
                when x"4C" => v := wy_r(7 downto 0);
                when x"4D" => v := "000000" & wy_r(9 downto 8);
                when x"50" => v := "0000" & sd_dado & sd_ctl;   -- (63) bit 3 = o cartao e' do ESP
                when x"55" =>
                  v := (others => '0');
                  if vr_n /= 0 then v(1) := '1'; end if;
                  if sd_ativo = '1' or sd_n /= 0 or (vazia = '0' and cabeca(9) = '1') then v(0) := '1'; end if;
                when x"56" => v := '0' & std_logic_vector(rx_n);
                when x"65" => v := "0" & r65;
                when x"66" => v := kin_s(7 downto 0);
                when x"67" => v := kin_s(15 downto 8);
                when x"68" => v := kin_s(23 downto 16);
                when x"69" => v := kin_s(31 downto 24);
                when x"6A" => v := kin_s(39 downto 32);
                when x"6B" => v := joy_s;
                when x"6C" => v := atal_s(7 downto 0) or atal_l(7 downto 0); atal_l(7 downto 0) <= (others => '0');
                when x"6D" => v := "0" & (atal_s(14 downto 8) or atal_l(14 downto 8)); atal_l(14 downto 8) <= (others => '0');
                when x"3B" => v := "00" & (atal_s(20 downto 15) or atal_l(20 downto 15)); atal_l(20 downto 15) <= (others => '0');   -- F5 F6 F7 F8 F9 F10 (esp56)
                when x"78" => v := maq_s(7 downto 0);
                when x"79" => v := maq_s(15 downto 8);
                when x"7A" => v := "0000" & vel_s;
                when x"6E" => v := "0000000" & cs_atv_s;
                when x"58" => v := f_wb_s(7 downto 0);
                when x"59" => v := f_wb_s(15 downto 8);
                when x"5A" => v := f_wb_s(23 downto 16);
                when x"5B" => v := f_we_s(7 downto 0);
                when x"5C" => v := f_we_s(15 downto 8);
                when x"5D" => v := f_rb_s(7 downto 0);
                when x"5E" => v := f_rb_s(15 downto 8);
                when x"5F" => v := f_rb_s(23 downto 16);
                when x"6F" => v := cs_liv_s;
                when x"74" => v := jcru_s(7 downto 0);
                when x"75" => v := jcru_s(15 downto 8);
                when x"76" => v := jcru_s(23 downto 16);
                when x"77" => v := jcru_s(31 downto 24);
                when x"70" => v := mb_cmd;
                when x"71" => v := mb_est;
                when x"72" => v := "00" & std_logic_vector(mb_n);
                when x"7B" => v := '0' & std_logic_vector(ut_n);
                when x"7E" => v := '0' & std_logic_vector(to_unsigned(64, 7) - ur_n);
                when x"41" | x"42" | x"43" | x"44" | x"45" | x"46" | x"47" | x"48" | x"49" =>
                  v := cores(to_integer(unsigned(a)) - 16#41#);
                when others =>
                  if a(7 downto 4) = "0000" then v := mem(to_integer(unsigned(a(3 downto 0))));
                  elsif a(7 downto 6) = "10" then v := req(to_integer(unsigned(a(5 downto 0))));
                  else v := x"FF"; end if;
              end case;
          end if;
          dout <= v;
        end if;
        case n is
          when 0 => cmd <= d_s2;
          when 1 => ender <= d_s2;
          when others =>
            if cmd = x"01" then
              if ender(7 downto 4) = "0000" then mem(to_integer(unsigned(ender(3 downto 0)))) <= d_s2; end if;
              if ender(7 downto 6) = "11" then rep(to_integer(unsigned(ender(5 downto 0)))) <= d_s2; end if;
              case ender is
                when x"20" => irq_r <= d_s2(0);
                when x"22" => perdeu <= '0';
                when x"30" => ptr(7 downto 0)   <= unsigned(d_s2); r_lin(7 downto 0) <= unsigned(d_s2); r_cnt <= (others => '0');
                when x"31" => ptr(15 downto 8)  <= unsigned(d_s2); r_lin(15 downto 8) <= unsigned(d_s2); r_cnt <= (others => '0');
                when x"32" => ptr(22 downto 16) <= unsigned(d_s2(6 downto 0)); r_lin(22 downto 16) <= unsigned(d_s2(6 downto 0)); r_cnt <= (others => '0');
                when x"40" => r40 <= d_s2(4 downto 0);
                when x"4E" => r4e <= d_s2(2 downto 0);
                when x"4F" => r4f <= d_s2(3 downto 0);
                when x"26" => r_larg(7 downto 0) <= unsigned(d_s2); r_cnt <= (others => '0');
                when x"27" => r_larg(15 downto 8) <= unsigned(d_s2); r_cnt <= (others => '0');
                when x"2A" => mp_on_r <= d_s2(0); mp_alto_r <= d_s2(1);
                when x"2B" => mp_rate_r(7 downto 0) <= d_s2;
                when x"2C" => mp_rate_r(15 downto 8) <= d_s2;
                when x"28" => r_passo(7 downto 0) <= unsigned(d_s2);
                when x"29" => r_passo(15 downto 8) <= unsigned(d_s2);
                when x"4A" => wx_r(7 downto 0) <= d_s2;
                when x"4B" => wx_r(10 downto 8) <= d_s2(2 downto 0);
                when x"4C" => wy_r(7 downto 0) <= d_s2;
                when x"4D" => wy_r(9 downto 8) <= d_s2(1 downto 0);
                when x"50" => sd_ctl <= d_s2(2 downto 0);
                when x"53" => sd_lo <= d_s2;
                when x"54" => sd_n <= unsigned(d_s2) & unsigned(sd_lo);
                when x"37" => vr_lo <= d_s2;
                when x"38" => vr_n <= unsigned(d_s2) & unsigned(vr_lo);
                when x"60" => kmat_r(7 downto 0) <= d_s2;
                when x"61" => kmat_r(15 downto 8) <= d_s2;
                when x"62" => kmat_r(23 downto 16) <= d_s2;
                when x"63" => kmat_r(31 downto 24) <= d_s2;
                when x"64" => kmat_r(39 downto 32) <= d_s2;
                when x"65" => r65 <= d_s2(6 downto 0);
                when x"71" => if d_s2(0) = '1' then pedido <= '0'; pronto <= '1'; end if;
                when x"73" => vivo <= d_s2(0);
                when x"6F" => cs_limpa_r <= d_s2(0); cs_fase <= '0';
                when x"5F" => surdo <= d_s2(0); b_vis_g <= b_vis_s(2);
                when x"39" => b_dest <= d_s2(1 downto 0);
                when x"23" => ay_i <= (others => '0');
                when x"41" | x"42" | x"43" | x"44" | x"45" | x"46" | x"47" | x"48" | x"49" =>
                  cores(to_integer(unsigned(ender)) - 16#41#) <= d_s2;
                when others => null;
              end case;
              if ender = x"6E" then
                if cs_fase = '0' then cs_lo <= d_s2; cs_fase <= '1';
                else cs_d_r <= d_s2 & cs_lo; cs_wr_r <= '1'; cs_fase <= '0'; end if;
              elsif ender = x"7D" then
                if ur_n /= 64 then ur(to_integer(urw(5 downto 0))) <= d_s2; urw <= urw + 1; end if;
              elsif ender = x"33" or ender = x"34" or ender = x"51" then
                if cheia = '0' then
                  if ender = x"51" then fila(to_integer(wp(5 downto 0))) <= "10" & d_s2;        -- cartao SD
                  elsif ender = x"33" then fila(to_integer(wp(5 downto 0))) <= "01" & d_s2;     -- RAM de video
                  else fila(to_integer(wp(5 downto 0))) <= "00" & d_s2; end if;                  -- SDRAM
                  wp <= wp + 1;
                else
                  perdeu <= '1';
                end if;
              else
                ender <= std_logic_vector(unsigned(ender) + 1);
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
