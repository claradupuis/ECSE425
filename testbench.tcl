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

;# keep reset while loading prog into mem
force -deposit sim:/processor_tb/reset 1

;# Load program.txt into instruction memory
set prog [open "program.txt" "r"]
set addr 0

while {[gets $prog line] >= 0} {
    set line [string trim $line]

    if {$line eq ""} {
        continue
    }

    ;# remove optional 0x prefix
    regsub {^0[xX]} $line "" line

    if {[string length $line] != 8} {
        puts "Bad instruction line: $line"
        quit -f
    }

    set b0 [string range $line 0 1]
    set b1 [string range $line 2 3]
    set b2 [string range $line 4 5]
    set b3 [string range $line 6 7]

    ;# big-endian storage
    force -deposit sim:/processor_tb/dut/instruction_mem/ram_block($addr)     16#$b0
    force -deposit sim:/processor_tb/dut/instruction_mem/ram_block([expr {$addr+1}]) 16#$b1
    force -deposit sim:/processor_tb/dut/instruction_mem/ram_block([expr {$addr+2}]) 16#$b2
    force -deposit sim:/processor_tb/dut/instruction_mem/ram_block([expr {$addr+3}]) 16#$b3

    set addr [expr {$addr + 4}]
}
close $prog

;# let reset go
run 10 ns
noforce sim:/processor_tb/reset

;# Run
run 5000 ns

;# Dump data memory
set mem_file [open "memory.txt" "w"]
for {set i 0} {$i < 8192} {incr i} {
    set base [expr {$i * 4}]

    set b0 [examine -radix hex sim:/processor_tb/dut/data_mem/ram_block($base)]
    set b1 [examine -radix hex sim:/processor_tb/dut/data_mem/ram_block([expr {$base+1}])]
    set b2 [examine -radix hex sim:/processor_tb/dut/data_mem/ram_block([expr {$base+2}])]
    set b3 [examine -radix hex sim:/processor_tb/dut/data_mem/ram_block([expr {$base+3}])]

    ;# strip prefix/space
    regsub -all {[^0-9A-Fa-f]} $b0 "" b0
    regsub -all {[^0-9A-Fa-f]} $b1 "" b1
    regsub -all {[^0-9A-Fa-f]} $b2 "" b2
    regsub -all {[^0-9A-Fa-f]} $b3 "" b3

    puts $mem_file "${b0}${b1}${b2}${b3}"
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