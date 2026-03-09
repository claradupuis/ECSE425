vlib work

vcom memory.vhd
vcom cache.vhd
vcom cache_tb.vhd

vsim cache_tb
set NumericStdNoWarnings 1
force -deposit clk 0 0 ns, 1 0.5 ns -repeat 1 ns
run 10000ns