derive_pll_clocks
derive_clock_uncertainty

# Reset/control-release paths are intentionally asynchronous.
# Cut them so TimeQuest reports real datapaths.
set_false_path -from [get_registers {*cpu_reset_n*}]
set_false_path -from [get_registers {*reset_sync_r*}]
set_false_path -from [get_registers {*boot_done*}]

# The z386 core advances only on a 16 MHz enable, at least three clk_sys
# apart for any profile clock >= 48 MHz. Paths that start and end inside the
# core get three clocks of setup and two of hold; paths through the z386_pc
# bus shim keep the single-clock default.
set_multicycle_path -setup 3 -from [get_registers {*|core386|*}] -to [get_registers {*|core386|*}]
set_multicycle_path -hold  2 -from [get_registers {*|core386|*}] -to [get_registers {*|core386|*}]
