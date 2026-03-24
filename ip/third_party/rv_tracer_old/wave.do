onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb_te_reg/rdata
add wave -noupdate -radix hexadecimal /tb_te_reg/clk_i
add wave -noupdate -radix hexadecimal /tb_te_reg/rst_ni
add wave -noupdate -radix hexadecimal /tb_te_reg/psel_i
add wave -noupdate -radix hexadecimal /tb_te_reg/penable_i
add wave -noupdate -radix hexadecimal /tb_te_reg/pwrite_i
add wave -noupdate -radix hexadecimal /tb_te_reg/paddr_i
add wave -noupdate -radix hexadecimal /tb_te_reg/pwdata_i
add wave -noupdate -radix hexadecimal /tb_te_reg/prdata_o
add wave -noupdate -radix hexadecimal /tb_te_reg/pready_o
add wave -noupdate -radix hexadecimal /tb_te_reg/trace_req_on_i
add wave -noupdate -radix hexadecimal /tb_te_reg/trace_req_off_i
add wave -noupdate -radix hexadecimal /tb_te_reg/trace_enable_o
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {162592 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 198
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {215712 ps}
