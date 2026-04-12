proc AddWaves {} {
    add wave -position end sim:/processor_tb/clk
    add wave -position end sim:/processor_tb/reset

    ;# Optional internal signals
    ;# add wave -position end sim:/processor_tb/dut/pc
    ;# add wave -position end sim:/processor_tb/dut/instruction_mem/address
    ;# add wave -position end sim:/processor_tb/dut/data_mem/address
}

vlib work

vcom types.vhd
vcom memory.vhd
vcom processor.vhd
vcom processor_tb.vhd

vsim processor_tb

AddWaves

;# Run until processor_tb finishes (all processes reach "wait")
run -all

;# Dump data memory as 32-bit hex words (8192 words)
set mem_file [open "memory.txt" "w"]
for {set i 0} {$i < 8192} {incr i} {
    set word [examine -radix hex sim:/processor_tb/dut/data_mem/ram_block($i)]
    regsub -all {[^0-9A-Fa-f]} $word "" word
    puts $mem_file $word
}
close $mem_file

quit -f