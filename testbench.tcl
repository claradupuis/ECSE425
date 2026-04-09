proc AddWaves {} {
    add wave -position end sim:/processor_tb/clk
    add wave -position end sim:/processor_tb/reset

    ;# Optional internal signals
    ;# add wave -position end sim:/processor_tb/dut/pc
    ;# add wave -position end sim:/processor_tb/dut/instruction_mem/address
    ;# add wave -position end sim:/processor_tb/dut/data_mem/address
}

vlib work

vcom memory.vhd
vcom processor.vhd
vcom processor_tb.vhd

vsim processor_tb

AddWaves

;# Load program.txt into instruction memory
set prog [open "program.txt" "r"]
set addr 0

while {[gets $prog line] >= 0} {
    set line [string trim $line]

    if {$line eq ""} {
        continue
    }

    if {[string length $line] != 32} {
        puts "Bad instruction line: $line"
        quit -f
    }

    ;# each line is one 32-bit instruction word
    force -deposit sim:/processor_tb/dut/instruction_mem/ram_block($addr) 2#$line

    incr addr
}
close $prog

;# Run
run 5000 ns

;# Dump data memory as 32-bit words
set mem_file [open "memory.txt" "w"]
for {set i 0} {$i < 8192} {incr i} {
    set word [examine -radix hex sim:/processor_tb/dut/data_mem/ram_block($i)]
    regsub -all {[^0-9A-Fa-f]} $word "" word
    puts $mem_file $word
}
close $mem_file

;# Dump 32 registers
set reg_file [open "register_file.txt" "w"]
for {set i 0} {$i < 32} {incr i} {
    set val [examine -radix hex sim:/processor_tb/dut/reg_file($i)]
    regsub -all {[^0-9A-Fa-f]} $val "" val
    puts $reg_file $val
}
close $reg_file

quit -f