// sid_timextenso.v: dois SID (sid_top do C64_MiSTer, Verilog gerado pelo sv2v) para o Timextenso.
//   mode = 1 para cada SID (8580) ou 0 (6581); filtros normais, sem curvas carregadas.
module sid_timextenso (
  input clk, input reset, input ce_1m,
  input [1:0] cs, input we, input [4:0] addr, input [7:0] din, output [7:0] dout,
  input [1:0] mode,
  output [17:0] audio_l, output [17:0] audio_r);
  sid_top #(.MULTI_FILTERS(0), .DUAL(1)) s (
    .reset(reset), .clk(clk), .ce_1m(ce_1m),
    .cs(cs), .we(we), .addr(addr), .data_in(din), .data_out(dout),
    .fc_offset_l(13'd0), .pot_x_l(8'hFF), .pot_y_l(8'hFF), .ext_in_l(18'd0), .audio_l(audio_l),
    .fc_offset_r(13'd0), .pot_x_r(8'hFF), .pot_y_r(8'hFF), .ext_in_r(18'd0), .audio_r(audio_r),
    .filter_en(2'b11), .mode(mode), .cfg(4'b0000),
    .ld_clk(clk), .ld_addr(12'd0), .ld_data(16'd0), .ld_wr(1'b0));
endmodule
