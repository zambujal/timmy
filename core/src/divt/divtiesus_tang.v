// divtiesus_tang.v: o tld_divtiesus.v do DivTIESUS v13 (Antonio / Miguel Angel Rodriguez
// Jodar, GPL v3) dentro do core da Tang. As ligacoes entre os modulos sao as mesmas;
// mudam so' as pontas:
//   - barramento de dados: din (do Z80) e dout/doe (para o Z80), sem 3 estados;
//   - romcs, romoe1 (/BE) e nmi_n saem como sinais normais (o core decide);
//   - notplus3 = 1 (o Timextenso nao e' um +2A/+3); jumper E fechado.
// A SRAM e a EEPROM da placa sao a SDRAM e uma ROM do core: o core usa os sinais
// eeprom_oe_n, sram_oe_n, sram_we_n e sram_hiaddr (pagina fisica de 8K da SRAM de 512K).

`timescale 1ns / 1ps
`default_nettype none

module divtiesus_tang (
  input  wire clk,              // relogio do CPLD (na placa 25 MHz)
  input  wire rst_n,
  input  wire [15:0] a,
  input  wire mreq_n,
  input  wire iorq_n,
  input  wire rd_n,
  input  wire wr_n,
  input  wire m1_n,
  input  wire [7:0] din,
  output wire [7:0] dout,
  output wire doe,
  output wire zxromcs,          // 1 = a ROM do Timex fica calada
  output wire be_n,             // 0 = este endereco e' servido pela SRAM (bancos 128K): RAM interna calada
  output wire nmi_n,
  input  wire nmi_button_n,
  output wire sclk,
  output wire mosi,
  input  wire miso,
  output wire sd_cs0,
  output wire eeprom_oe_n,
  output wire sram_oe_n,
  output wire sram_we_n,
  output wire [5:0] sram_hiaddr,
  // para o SCLD da Tang (o clone le-os nas suas proprias copias das portas)
  output wire modo128,
  output wire modo2068,
  input  wire p1024              // Tang: Pentagon 1024, o 7FFD sem trinco (bit 5 = banco)
  );

  wire notplus3 = 1'b1;
  wire jumper_e = 1'b1;

  wire divmmc_zxromcs, divmmc_eeprom_cs, divmmc_sram_cs, divmmc_sram_write_n;
  wire [5:0] divmmc_sram_hiaddr;
  wire trese_sram_cs;
  wire [5:0] trese_sram_hiaddr;
  wire nmi_to_cpu_n;
  wire allramplus3;
  wire zxuno_regrd, zxuno_regwr;
  wire [7:0] zxuno_addr;
  wire [1:0] banco_rom;
  wire [2:0] banco_ram;
  wire banco_ext;
  wire bancos_sel, bancos_sel_sram, bancos_oe_n, bancos_we_n;
  wire exrom_sel, exlo;
  wire [5:0] bancos_hiaddr;
  wire inrom48k = (banco_rom[1] | notplus3) & banco_rom[0];
  wire [7:0] dout_div, dout_modo;
  wire doe_div, doe_modo;
  wire eeprom_we_n_nc, sd_cs1_nc;

  assign nmi_n = nmi_to_cpu_n;
  // 2026-10-20 (como no clone): ZXUNO A2h = 52h faz o master reset dos registos (DFh: ROM em
  // RAM e DivMMC; DDh: TC2068) sem o Z80: o navegador e o .go128 -reset voltam ao TC2048 com jp 0
  reg soft_mrst = 1'b0;
  always @(posedge clk)
    soft_mrst <= (zxuno_regwr == 1'b1 && zxuno_addr == 8'hA2 && din == 8'h52);
  wire mrst_n = (rst_n | nmi_button_n) & ~soft_mrst;
  assign be_n = ~bancos_sel;

  divmmc_mcleod el_divmmc (
    .clk(clk), .rst_n(rst_n), .enable_autopage(jumper_e),
    .a(a), .d(din), .dout(dout_div), .doe(doe_div),
    .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n),
    .nmi_button_n(nmi_button_n), .nmi_to_cpu_n(nmi_to_cpu_n),
    .inrom48k(inrom48k), .modo128(modo128), .modo2068(modo2068), .exlo(exlo),
    .zxromcs(divmmc_zxromcs),
    .eeprom_cs(divmmc_eeprom_cs), .eeprom_we_n(eeprom_we_n_nc),
    .sram_cs(divmmc_sram_cs), .sram_write_n(divmmc_sram_write_n), .sram_hiaddr(divmmc_sram_hiaddr),
    .sd_cs0_n(sd_cs0), .sd_cs1_n(sd_cs1_nc), .sd_sclk(sclk), .sd_mosi(mosi), .sd_miso(miso)
  );

  tres_e el_3e (
    .clk(clk), .rst_n(rst_n), .a(a), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n),
    .din(din), .modo128(modo128), .rom32(modo2068), .sem_trinco(p1024),
    .allramplus3(allramplus3), .banco_rom(banco_rom), .banco_ram(banco_ram), .banco_ext(banco_ext),
    .sram_cs(trese_sram_cs), .sram_hiaddr(trese_sram_hiaddr)
  );

  modo modo_operacion (
    .clk(clk), .mrst_n(mrst_n), .zxuno_addr(zxuno_addr), .zxuno_regrd(zxuno_regrd), .zxuno_regwr(zxuno_regwr),
    .d(din), .dout(dout_modo), .doe(doe_modo),
    .allramplus3(allramplus3), .mreq_n(mreq_n), .rd_n(rd_n),
    .divmmc_zxromcs(divmmc_zxromcs), .divmmc_eeprom_cs(divmmc_eeprom_cs), .divmmc_sram_cs(divmmc_sram_cs),
    .divmmc_sram_write_n(divmmc_sram_write_n), .divmmc_sram_hiaddr(divmmc_sram_hiaddr),
    .trese_sram_cs(trese_sram_cs), .trese_sram_hiaddr(trese_sram_hiaddr),
    .bancos_sel(bancos_sel_sram), .bancos_oe_n(bancos_oe_n), .bancos_we_n(bancos_we_n), .bancos_hiaddr(bancos_hiaddr),
    .exrom_sel(exrom_sel), .a_rom(a[15:14] == 2'b00), .modo2068(modo2068),
    .zxromcs(zxromcs), .eeprom_oe_n(eeprom_oe_n), .sram_oe_n(sram_oe_n), .sram_write_n(sram_we_n), .sram_hiaddr(sram_hiaddr)
  );

  bancos128 bancos_128k (
    .clk(clk), .mrst_n(mrst_n), .a(a), .din(din), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n),
    .zxuno_addr(zxuno_addr), .zxuno_regwr(zxuno_regwr), .banco_ram(banco_ram), .banco_ext(banco_ext),
    .modo128(modo128), .sel(bancos_sel), .sel_sram(bancos_sel_sram),
    .sram_oe_n(bancos_oe_n), .sram_we_n(bancos_we_n), .sram_hiaddr(bancos_hiaddr),
    .modo2068(modo2068), .exrom_sel(exrom_sel), .exlo(exlo)
  );

  zxunoregs el_zxuno_esta_por_aqui (
    .clk(clk), .rst_n(rst_n), .a(a), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .d(din),
    .addr(zxuno_addr), .read_from_reg(zxuno_regrd), .write_to_reg(zxuno_regwr)
  );

  // leituras do Z80: porta EB (SPI) ou registo DF
  assign doe  = doe_div | doe_modo;
  assign dout = doe_div ? dout_div : dout_modo;
endmodule

// Tang: repoe o valor por omissao para os ficheiros seguintes (mem.v)
`default_nettype wire
