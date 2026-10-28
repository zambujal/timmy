// Memorias para a sintese (o yosys mete-as em BSRAM).
// Em VHDL o GHDL achatava as memorias inicializadas; ficam aqui em Verilog.
// Modelos VHDL equivalentes para simulacao: sim/mem_sim.vhd
// O build.sh copia para home.hex / exrom.hex as ROMs da maquina escolhida.

// ROM HOME 16K


// Timmy: as ROMs vem do cartao ao ligar (os cores antigos core_timex/core_penta usavam modulos rom_* com
// $readmemh de ROMs com direitos; ficaram de fora deste repositorio).
// ram_home comeca vazia; ram_esx comeca com o programa
// de arranque (arranque.hex, nosso), no lugar do esxDOS, que ele proprio la' escreve depois.
module ram_home (input clk, input [13:0] a, input we, input [7:0] d, output reg [7:0] q);
  reg [7:0] m [0:16383];
  always @(posedge clk) begin
    if (we) m[a] <= d;
    q <= m[a];
  end
endmodule

module ram_esx (input clk, input [12:0] a, input we, input [7:0] d, output reg [7:0] q);
  reg [7:0] m [0:8191];
  initial $readmemh("arranque.hex", m);
  always @(posedge clk) begin
    if (we) m[a] <= d;
    q <= m[a];
  end
endmodule

// EXROM 8K (TC2068)


// RAM com porto A (CPU, le/escreve) e porto B (video, so le, com relogio proprio)
module ram_dp #(parameter AW = 14) (
  input clk,
  input [AW-1:0] a, input we, input [7:0] d, output reg [7:0] q,
  input clkb, input [AW-1:0] b, output reg [7:0] bq);
  (* no_rw_check *) reg [7:0] m [0:(1<<AW)-1];   // sem logica de colisao entre portos (mesmo relogio)
  always @(posedge clk) begin
    if (we) m[a] <= d;
    else    q <= m[a];
  end
  always @(posedge clkb) bq <= m[b];
endmodule

// RAM so' do CPU
module ram_sp #(parameter AW = 15) (
  input clk, input [AW-1:0] a, input we, input [7:0] d, output reg [7:0] q);
  reg [7:0] m [0:(1<<AW)-1];
  always @(posedge clk) begin
    if (we) m[a] <= d;
    else    q <= m[a];
  end
endmodule

// ROM 32K do 128K / Pentagon (ROM0 = BASIC 128, ROM1 = BASIC 48)


// EEPROM do DivMMC (esxDOS, 8K), so' leitura


// RAM de 12K com dois portos (escrita no porto A, leitura no B com relogio proprio):
// os bancos 4/6 do modo 16C do Pentagon (2 x 6K)
module ram_dp12k (
  input clk, input [13:0] a, input we, input [7:0] d,
  input clkb, input [13:0] b, output reg [7:0] bq);
  (* no_rw_check *) reg [7:0] m [0:12287];
  always @(posedge clk) if (we) m[a] <= d;
  always @(posedge clkb) bq <= m[b];
endmodule
