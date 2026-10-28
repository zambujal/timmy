# Relogios do Timmy: 27 MHz -> pll54 (core e SDRAM, 54 MHz) e pll (HDMI 371,25 MHz, pixel 74,25 MHz)
create_clock -name clk27 -period 37.037 [get_ports {I_clk}]
create_generated_clock -name clk54  -source [get_ports {I_clk}] -master_clock clk27 -multiply_by 2 [get_pins {pll54/CLKOUT}]
create_generated_clock -name clk54p -source [get_ports {I_clk}] -master_clock clk27 -multiply_by 2 [get_pins {pll54/CLKOUTP}]
create_generated_clock -name sclk   -source [get_ports {I_clk}] -master_clock clk27 -multiply_by 55 -divide_by 4 [get_pins {pll/CLKOUT}]
create_generated_clock -name pclk   -source [get_pins {pll/CLKOUT}] -master_clock sclk -divide_by 5 [get_pins {div/CLKOUT}]
# (2026-10-24) o relogio do ESP (ponte rapida: dados apanhados com ele; ate' 80 MHz no teste)
create_clock -name espclk -period 12.5 [get_ports {I_esp_clk}]
set_clock_groups -asynchronous -group [get_clocks {espclk}] -group [get_clocks {clk54 clk54p sclk pclk spiclk}]
# SPI do BL616 (ate' ~20 MHz)
create_clock -name spiclk -period 40 [get_ports {I_spi_sclk}]
# o video passa para o core por RAM de dois portos e registos duplos
set_clock_groups -asynchronous -group [get_clocks {clk54 clk54p}] -group [get_clocks {sclk pclk}] -group [get_clocks {spiclk}]
report_timing -setup -max_paths 50 -to_clock [get_clocks {clk54}]
report_timing -hold -max_paths 50
# 2026-10-22: os caminhos dentro de cada relogio (os 50 piores acima sao todos do iorq_wr da DivTIESUS)
report_timing -setup -max_paths 25 -from_clock [get_clocks {clk54}] -to_clock [get_clocks {clk54}]
report_timing -setup -max_paths 25 -from_clock [get_clocks {pclk}] -to_clock [get_clocks {pclk}]
# 2026-10-23: o Z80 principal anda com o CLKEN (no maximo 14 MHz: um a cada 3 ou 4 ciclos de 54 MHz):
# dentro dele os caminhos tem 3 ciclos
# 2026-10-24: com os 27 MHz (ce de 2 em 2 ciclos, nunca seguidos) passa a 2 ciclos
set_multicycle_path -from [get_regs {timmy_g.core/cpu/u0/*}] -to [get_regs {timmy_g.core/cpu/u0/*}] -setup -end 2
set_multicycle_path -from [get_regs {timmy_g.core/cpu/u0/*}] -to [get_regs {timmy_g.core/cpu/u0/*}] -hold -end 1
# 2026-10-24: o Z80 do GS anda com ce de 2 em 2 ciclos de 54 MHz (27 MHz no maximo)
set_multicycle_path -from [get_regs {timmy_g.core/gsnd/cpu/u0/*}] -to [get_regs {timmy_g.core/gsnd/cpu/u0/*}] -setup -end 2
set_multicycle_path -from [get_regs {timmy_g.core/gsnd/cpu/u0/*}] -to [get_regs {timmy_g.core/gsnd/cpu/u0/*}] -hold -end 1
# o reset do Z80 so' muda ao ligar e com o reset do ESP
set_false_path -from [get_regs {cpu_rst_n_s0}]
# registos da DivTIESUS feitos com posedge iorq_wr / negedge mreq_n (como no CPLD): mudam no fim de um OUT
# ou no inicio de um MREQ; o acesso seguinte a' memoria chega pelo menos uma T-state depois (3-4 ciclos)
set_multicycle_path -from [get_regs {timmy_g.core/dv/el_3e/* timmy_g.core/dv/el_zxuno_esta_por_aqui/* timmy_g.core/dv/bancos_128k/* timmy_g.core/dv/el_divmmc/*}] -setup -end 2
set_multicycle_path -from [get_regs {timmy_g.core/dv/el_3e/* timmy_g.core/dv/el_zxuno_esta_por_aqui/* timmy_g.core/dv/bancos_128k/* timmy_g.core/dv/el_divmmc/*}] -hold -end 1
