/*
 * This file is part of the DIVtiesus project
 * Copyright (c) 2021 Miguel Angel Rodriguez Jodar.
 * 
 * This program is free software: you can redistribute it and/or modify  
 * it under the terms of the GNU General Public License as published by  
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but 
 * WITHOUT ANY WARRANTY; without even the implied warranty of 
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License 
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

`timescale 1ns / 1ps
`default_nettype none

module tres_e (
  input wire clk,
  input wire rst_n,
  input wire [15:0] a,   // Tang: 'wire' (a Gowin exige-o com default_nettype none)
  input wire mreq_n,
  input wire iorq_n,
  input wire rd_n,
  input wire wr_n,
  input wire [7:0] din,
  input wire modo128,              // 1 = decode 7FFD as a 128K does, ignore 1FFD
  input wire rom32,
  input wire sem_trinco,           // Tang: Pentagon 1024, o bit 5 do 7FFD nao e' trinco                // 1 = ROM in RAM from divMMC pages 32-35 (128K or TC2068 mode)
  output wire allramplus3,
  output wire [1:0] banco_rom,
  output wire [2:0] banco_ram,     // RAM bank selected with 7FFD bits 2-0
  output wire banco_ext,           // 7FFD bit 6 (Pentagon 256: banks 8-15)
  // DivMMC onboard memory control
  output reg sram_cs,
  output reg [5:0] sram_hiaddr  // up to 512KB of SRAM can be addressed
  );

  // In 128K mode the port is decoded with A15=0 and A1=0 only, as the 128K and
  // +2 do, and there is no 1FFD. Otherwise the original +2A/+3 decoding is used.
  wire ADDR_7FFD_PLUS2A = (modo128 == 1'b1)? (!a[1] && !a[15]) : (!a[1] && a[15:14]==2'b01);
  wire ADDR_1FFD        = (modo128 == 1'b0) && (!a[1] && a[15:12]==4'b0001);  // ojo! colisiona con 7FFD en el 128K por culpa de que solo decodifica a[15]=0 y a[1]=0 (wilco2009)
  // Standard 128K memory manager
  reg [7:0] bank128 = 8'h00;
  reg [7:0] bankplus3 = 8'h00;
  wire puerto_bloqueado = bank128[5] & ~sem_trinco;
  assign banco_rom = {bankplus3[2], bank128[4]};
  assign banco_ram = bank128[2:0];
  assign banco_ext = bank128[6];
  wire amstrad_allram_page_mode = bankplus3[0];
  assign allramplus3 = amstrad_allram_page_mode;

  wire iorq_wr = iorq_n | wr_n;
  always @(posedge iorq_wr or negedge rst_n) begin
    if (rst_n == 1'b0) begin
      bank128 <= 8'h00;
      bankplus3 <= 8'h00;
    end
    else begin
      if (ADDR_7FFD_PLUS2A && puerto_bloqueado == 1'b0)
        bank128 <= din;
      else if (ADDR_1FFD && puerto_bloqueado == 1'b0)
        bankplus3 <= din;
    end
  end

  always @* begin
    // In 128K mode the ROM comes from divMMC pages 32-35 (ROM0 32,33; ROM1
    // 34,35), which esxDOS and the NMI browser never use. Otherwise pages 8-15.
    if (modo128 == 1'b1 || rom32 == 1'b1)
      sram_hiaddr = {4'b0100, bank128[4], a[13]};
    else
      sram_hiaddr = {3'b111, banco_rom, a[13]};
    if (mreq_n == 1'b0 && a[15:14] == 1'b0 && rd_n == 1'b0 && amstrad_allram_page_mode == 1'b0)
      sram_cs = 1'b1;
    else
      sram_cs = 1'b0;
  end  
endmodule

// Tang: repoe o valor por omissao para os ficheiros seguintes (mem.v)
`default_nettype wire
