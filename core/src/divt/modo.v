// Tang Nano 20K (Timmy): copia do DivTIESUS v13 do Antonio. Unica mudanca: o barramento
// de dados bidireccional (inout d) passa a din (entrada) + dout/doe (saida), porque dentro
// da FPGA nao ha' 3 estados.
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

module modo (
  input wire clk,
  input wire mrst_n,
  input wire [7:0] zxuno_addr,
  input wire zxuno_regrd,
  input wire zxuno_regwr,
  input wire [7:0] d,               // Tang: so' entrada
  output wire [7:0] dout,           // Tang: leitura do registo DF
  output wire doe,
  input wire allramplus3,
  input wire mreq_n,
  input wire rd_n,
  
  input wire divmmc_zxromcs,
  input wire divmmc_eeprom_cs,
  input wire divmmc_sram_cs,
  input wire divmmc_sram_write_n,
  input wire [5:0] divmmc_sram_hiaddr,
  
  input wire trese_sram_cs,
  input wire [5:0] trese_sram_hiaddr,

  // 128K RAM banks at C000-FFFF (bancos128.v). With bancos_sel = 0 this
  // module behaves exactly as before.
  input wire bancos_sel,
  input wire bancos_oe_n,
  input wire bancos_we_n,
  input wire [5:0] bancos_hiaddr,

  // EXROM of the TC2068 mode (bancos128.v). 0 when the mode is off.
  input wire exrom_sel,
  input wire a_rom,             // 1 = address in 0000-3FFF
  // TC2068 mode (bancos128.v, register DDh bit 0). The esxDOS firmware is read
  // from divMMC page 37 (ESX2068.BIN, loaded there by the NMI browser) instead
  // of the EEPROM. 0 = exactly as before.
  input wire modo2068,

  output reg zxromcs,
  output reg eeprom_oe_n,
  output reg sram_oe_n,
  output reg sram_write_n,
  output reg [5:0] sram_hiaddr  
  );

  parameter ADDR_MODO = 8'hDF;

  reg rmodo = 1'b0;
  reg rendiv = 1'b0;
  wire oe = (zxuno_regrd == 1'b1 && zxuno_addr == ADDR_MODO);
  assign dout = {rmodo, rendiv, 6'b000000};   // Tang: os bits 5-0 ficavam soltos (3 estados)
  assign doe = oe;
  
  always @(posedge clk) begin
    if (mrst_n == 1'b0) begin
      rmodo <= 1'b0;
      rendiv <= 1'b0;
    end
    else if (zxuno_regwr == 1'b1 && zxuno_addr == ADDR_MODO) begin
      rmodo <= rmodo | d[7];
      rendiv <= rendiv | d[6];
    end
  end
  
  always @* begin
    if (allramplus3 == 1'b0) begin
      if (rmodo == 1'b0) begin
        zxromcs = divmmc_zxromcs;
        eeprom_oe_n = ~divmmc_eeprom_cs;
        sram_oe_n = ~divmmc_sram_cs;
        sram_write_n = divmmc_sram_write_n;
        sram_hiaddr = divmmc_sram_hiaddr;
      end
      else begin
        zxromcs = 1'b1;        
        if (rendiv == 1'b0 || divmmc_zxromcs == 1'b0) begin
          eeprom_oe_n = 1'b1;
          sram_oe_n = ~trese_sram_cs;
          sram_write_n = 1'b1;
          sram_hiaddr = trese_sram_hiaddr;
        end
        else begin
          eeprom_oe_n = ~divmmc_eeprom_cs;
          sram_oe_n = ~divmmc_sram_cs;
          sram_write_n = divmmc_sram_write_n;
          sram_hiaddr = divmmc_sram_hiaddr;
        end
      end
    end
    else begin
      zxromcs = 1'b0;
      eeprom_oe_n = 1'b1;
      sram_oe_n = 1'b1;
      sram_write_n = 1'b1;
      sram_hiaddr = 6'b110000;
    end    

    // TC2068 mode: the reads that would go to the EEPROM come from divMMC
    // page 37, read only. Pages 36 (EXROM) and 37 cannot be written.
    if (modo2068 == 1'b1) begin
      if (eeprom_oe_n == 1'b0) begin
        eeprom_oe_n = 1'b1;
        sram_oe_n = 1'b0;
        sram_write_n = 1'b1;
        sram_hiaddr = 6'b010101;  // divMMC page 37
      end
      else if (sram_hiaddr[5:1] == 5'b01010)
        sram_write_n = 1'b1;
    end

    // The address is in C000-FFFF and that block is served by the SRAM.
    // None of the cases above uses the SRAM for these addresses.
    if (bancos_sel == 1'b1) begin
      sram_oe_n = bancos_oe_n;
      sram_write_n = bancos_we_n;
      sram_hiaddr = bancos_hiaddr;
    end

    // EXROM (divMMC page 36, read only), unless the divMMC has 0000-3FFF mapped.
    if (exrom_sel == 1'b1 && !(a_rom == 1'b1 && divmmc_zxromcs == 1'b1 && (rmodo == 1'b0 || rendiv == 1'b1))) begin
      zxromcs = 1'b1;
      eeprom_oe_n = 1'b1;
      sram_oe_n = ~(mreq_n == 1'b0 && rd_n == 1'b0);
      sram_write_n = 1'b1;
      sram_hiaddr = 6'b010100;  // divMMC page 36
    end
  end
endmodule

// Tang: repoe o valor por omissao para os ficheiros seguintes (mem.v)
`default_nettype wire
