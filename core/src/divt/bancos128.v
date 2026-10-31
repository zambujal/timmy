//    128K RAM banks for DivTIESUS on a Timex TC2048 / TC2068.
//
//    Addition to the DivTIESUS CPLD design by Miguel Angel Rodriguez Jodar
//    (https://github.com/mcleod-ideafix/divtiesus), under the same licence,
//    the GNU General Public License version 3.
//
//    Makes the onboard SRAM serve the Spectrum 128K RAM banks on a Timextenso
//    (TC2048 clone) whose SCLD is the CPLD replacement with the 128K mode.
//    It needs a 512K SRAM: the banks use divMMC pages 16 to 31.
//
//    Both sides follow Timex port F4, the SCLD register that takes 8K
//    blocks away from the internal RAM. This module keeps its own copy of
//    the whole register; the SCLD has no reset on it, and neither has this
//    copy, so the two stay equal from power on.
//
//    F4 = F0h (8000h-FFFFh away from the internal RAM) is the 128K mode, in
//    the SCLD and here:
//     - 7FFD is decoded as on a 128K (A15=0, A1=0), see tres_e.v;
//     - 8000h-BFFFh is bank 2, from the SRAM, so that bank 2 at C000h is
//       the same memory;
//     - C000h-FFFFh is the bank in 7FFD, from the SRAM, except banks 5 and
//       7: those live in the Timextenso's video RAM (4464), where the SCLD can
//       show them on screen, and the SCLD serves them.
//    Any other value with some of those bits set: the blocks taken away
//    are served as plain RAM (bank 2 at 8000h, bank 0 at C000h), so the
//    machine never loses that memory.
//    To leave the 128K mode: OUT 65524,0 (F4 = 0) or power off.
//
//    The old switch (ZXUNO register DE = A5) is no longer used: the SCLD
//    cannot see it, and both sides must agree on the mode.
//
//    TC2068 mode (ZXUNO register DDh, bit 0; 0 at power on and after a master
//    reset, so with nothing written this design behaves exactly as before, also
//    on a real TC2068 with its own EXROM). Set only by the NMI browser on the
//    Timextenso, which has no EXROM chip:
//     - EXROM: an 8K block that port F4 takes away from the home bank, with
//       port FF bit 7 = 1 (EXROM, not DOCK), reads divMMC page 36 (the 8K
//       EXROM of the TC2068). Read only. Not in 128K mode.
//     - the ROM in RAM (home ROM of the TC2068) comes from divMMC pages 32-35
//       as in 128K mode, not 8-15 (the NMI uses pages 5-10 for its copy of RAM);
//    Shadow of the video RAM (register DDh bit 1, and port F3 bit 6 of the SCLD;
//    both 0 at power on and neither has any other reset, as the SCLD register,
//    so with nothing written this design behaves exactly as before):
//     - DDh bit 1 = 1: every CPU write to the video RAM (4000h-7FFFh, and banks
//       5/7 at C000h in 128K mode) is also written to the SRAM: bank 5 in divMMC
//       page 26/27, bank 7 in page 30/31, the pages those banks would have.
//     - DDh bit 1 = 1 and F3 bit 6 = 1 (the SCLD shadow mode, same OUT for both
//       CPLDs): the CPU reads of the video RAM come from the SRAM. The SCLD does
//       nothing in those reads (buffer closed, no RAS/CAS, no contention).
//       On a TC2068 with its own SCLD, F3 bit 6 alone does nothing here.
//    To switch on: DDh bit 1 = 1, read and write back every byte of the video RAM
//    (bank 7 too in 128K mode), then OUT F3 with bit 6. To switch off: OUT F3 with
//    bit 6 = 0 first, then DDh bit 1 = 0. A master reset does not change them.
//    No NMI in this mode (the ROM is not a Spectrum ROM): a master reset
//    (RESET with NMI held) clears it and the Timextenso starts as a TC2048.
//    The copy of FF bit 7 follows the SCLD: it is not written while port F3
//    bit 5 is set (floating bus on FF, FF writes ignored by the SCLD).

module bancos128 (
  input wire clk,
  input wire mrst_n,              // not used any more
  input wire [15:0] a,
  input wire [7:0] din,
  input wire mreq_n,
  input wire iorq_n,
  input wire rd_n,
  input wire wr_n,
  input wire [7:0] zxuno_addr,    // not used any more
  input wire zxuno_regwr,         // not used any more
  input wire [2:0] banco_ram,     // 7FFD bits 2-0
  input wire banco_ext,           // 7FFD bit 6 (Pentagon 256)
  output wire modo128,            // 1 = 128K mode (F4 = F0h)
  output wire sel,                // 1 = this address is served by the SRAM (128K banks; /BE)
  output wire sel_sram,           // 1 = the SRAM signals below are used (sel or shadow)
  output wire sram_oe_n,
  output wire sram_we_n,
  output wire [5:0] sram_hiaddr,  // SRAM A18-A13
  output wire modo2068,           // 1 = TC2068 mode (register DDh bit 0)
  output wire exrom_sel,          // 1 = this address reads the EXROM (page 36)
  output wire exlo                // 1 = TC2068 mode and the EXROM is at 0000-1FFF
  );

  // Copy of Timex port F4.
  reg [7:0] hsr = 8'h00;
  wire iorq_wr = iorq_n | wr_n;
  always @(posedge iorq_wr) begin
    if (a[7:0] == 8'hF4)
      hsr <= din;
  end

  // Copies of FF bit 7 (0 DOCK, 1 EXROM) and F3 bit 5. No reset, as in the SCLD.
  reg ff7 = 1'b0;
  reg f3flut = 1'b0;
  reg f3sombra = 1'b0;
  reg f3penta = 1'b0;
  reg f3b3 = 1'b0;      // F3 bit 3: with F3 bit 7, Pentagon 256 (.go256)
  always @(posedge iorq_wr) begin
    if (a[7:0] == 8'hF3) begin
      f3flut <= din[5];
      f3sombra <= din[6];
      f3penta <= din[7];
      f3b3 <= din[3];
    end
    if (a[7:0] == 8'hFF && f3flut == 1'b0)
      ff7 <= din[7];
  end

  // ZXUNO register DDh: TC2068 mode
  reg r2068 = 1'b0;
  always @(posedge clk) begin
    if (mrst_n == 1'b0)
      r2068 <= 1'b0;
    else if (zxuno_regwr == 1'b1 && zxuno_addr == 8'hDD)
      r2068 <= din[0];
  end

  // DDh bit 1: copy the writes to the video RAM. Power on only, no master reset:
  // it must stay equal to what the SCLD has (F3 bit 6 has no reset).
  reg copia = 1'b0;
  always @(posedge clk) begin
    if (zxuno_regwr == 1'b1 && zxuno_addr == 8'hDD)
      copia <= din[1];
  end
  assign modo2068 = r2068;

  wire activo = (hsr == 8'hF0);
  assign modo128 = activo;

  // Bit of F4 for the 8K block of this address
  wire bloque_externo = hsr[a[15:13]];

  assign exrom_sel = (r2068 == 1'b1 && activo == 1'b0 && bloque_externo == 1'b1 && ff7 == 1'b1);
  assign exlo = (r2068 == 1'b1 && activo == 1'b0 && hsr[0] == 1'b1 && ff7 == 1'b1);

  // Pentagon 256 (F3 bit 7, as the SCLD): 7FFD bit 6 selects banks 8-15, all in the
  // SRAM (SRAM pages 0-15 = divMMC pages 48-63). Without F3 bit 7 bit 6 is ignored.
  // Pentagon 256 only with F3 bit 3 too (as the SCLD); otherwise Pentagon 128: bit 6 ignored
  wire ext = (activo == 1'b1 && f3penta == 1'b1 && f3b3 == 1'b1 && banco_ext == 1'b1);

  // Banks 5 (101) and 7 (111) at C000h are served by the SCLD (not 13 and 15).
  wire banco_video = (banco_ram[2] == 1'b1 && banco_ram[0] == 1'b1 && ext == 1'b0);

  assign sel = (a[15] == 1'b1 && bloque_externo == 1'b1 &&
                !(activo == 1'b1 && a[14] == 1'b1 && banco_video == 1'b1));

  // Shadow of the video RAM: 4000h-7FFFh (bank 5) or bank 5/7 at C000h in 128K mode
  wire video = (a[15:14] == 2'b01) ||
               (a[15:14] == 2'b11 && activo == 1'b1 && banco_video == 1'b1);
  wire sombra = (video == 1'b1 && copia == 1'b1 && mreq_n == 1'b0 && (rd_n == 1'b0 || wr_n == 1'b0));
  assign sel_sram = sel | sombra;

  assign sram_oe_n = ~(mreq_n == 1'b0 && rd_n == 1'b0 && (sel == 1'b1 || (sombra == 1'b1 && f3sombra == 1'b1)));
  assign sram_we_n = ~(mreq_n == 1'b0 && wr_n == 1'b0 && (sel == 1'b1 || sombra == 1'b1));

  // divMMC pages 16-31. divMMC page p is SRAM page {~p[5:4], p[3:0]}, so
  // pages 16-31 are SRAM pages 32-47. 8000h-BFFFh is always bank 2;
  // C000h-FFFFh is the 7FFD bank in 128K mode and bank 0 otherwise.
  // Shadow: 4000h-7FFFh is bank 5.
  wire [2:0] banco = (a[15:14] == 2'b01)? 3'b101 :
                     (a[14] == 1'b0)? 3'b010 : ((activo == 1'b1)? banco_ram : 3'b000);
  // banks 8-15 (C000h with ext): SRAM pages 0-15 = divMMC pages 48-63
  wire alto = (a[15:14] == 2'b11 && ext == 1'b1);
  assign sram_hiaddr = {~alto, 1'b0, banco, a[13]};
endmodule
