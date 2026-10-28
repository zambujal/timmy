# Timmy timmy na Gowin EDA: gw_sh timmy.tcl  (correr dentro desta pasta)
# Resultado: impl/pnr/timmy_timmy_1024_1645.fs
set_device GW2AR-LV18QN88C8/I7 -name GW2AR-18C -device_version C
add_file src/sid/sid_all.v
add_file src/sid/sid_timmy.v
add_file src/divt/divmmc_mcleod.v
add_file src/divt/tres_e.v
add_file src/divt/modo.v
add_file src/divt/bancos128.v
add_file src/divt/zxunoregs.v
add_file src/divt/divtiesus_tang.v
add_file src/T80_Pack.vhd
add_file src/T80_ALU.vhd
add_file src/T80_MCode.vhd
add_file src/T80_Reg.vhd
add_file src/T80.vhd
add_file src/T80se.vhd
add_file src/tmds_enc.vhd
add_file src/hdmi_tx.vhd
add_file src/camada_esp.vhd
add_file src/som.vhd
add_file src/i2s_rx.vhd
add_file src/ulaplus.vhd
add_file src/ym2149.vhd
add_file src/video_timex.vhd
add_file src/sdram.vhd
add_file src/divmmc.vhd
add_file src/core_timex.vhd
add_file src/core_penta.vhd
add_file src/teclas_seq.vhd
add_file src/teclas_auto.vhd
add_file src/teclas_arranque.vhd
add_file src/gs.vhd
add_file src/core_timmy.vhd
add_file src/mcu_spi.vhd
add_file src/sysctrl.vhd
add_file src/hid_teclado.vhd
add_file src/ponte_rapida.vhd
add_file src/ponte_esp.vhd
add_file src/cassete.vhd
add_file src/top.vhd
add_file mem.v
add_file timmy.cst
add_file timmy.sdc
set_option -synthesis_tool gowinsynthesis
set_option -output_base_name timmy_timmy_1024_1645
set_option -verilog_std v2001
set_option -vhdl_std vhd2008
set_option -top_module top
set_option -use_mspi_as_gpio 0
set_option -use_sspi_as_gpio 1
# troca de core: pino 73 -> fio -> TP1 (RECONFIG_N dedicado); o core seguinte esta' em 0x100000
set_option -use_reconfign_as_gpio 0
set_option -multi_boot 1
set_option -multiboot_address_width 24
set_option -multiboot_mode single
set_option -multiboot_spi_flash_address 100000
set_option -rw_check_on_ram 1
set_option -place_option 2
set_option -route_option 1
# registos de entrada e saida dentro dos blocos de I/O (tempo fixo nos pinos da SDRAM)
set_option -ioreg_in_iob 1
set_option -gen_text_timing_rpt 1
run all
