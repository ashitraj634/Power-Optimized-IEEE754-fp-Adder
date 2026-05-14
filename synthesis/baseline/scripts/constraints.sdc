#set sdc_version 2.1
reset_design

# Target Speed (Relaxed to 5.0ns for a clean first pass)
set PERIOD  5.0
set INPUT_DELAY  1.0
set OUTPUT_DELAY 1.0
set CLOCK_LATENCY 0.25
set SOURCE_LATENCY 0.25
set UNCERTAINTY 0.1
set MAX_TRANSITION 0.2
set MIN_CLOCK_LATENCY 0.05
set MIN_SOURCE_LATENCY 0.05
set MIN_IO_DELAY 0.1

## CLOCK BASICS
create_clock -name "clock" -period $PERIOD [get_ports clk]

set_clock_latency $CLOCK_LATENCY [get_clocks clock]
set_clock_latency -min $MIN_CLOCK_LATENCY [get_clocks clock]
set_clock_latency -source $SOURCE_LATENCY [get_clocks clock]
set_clock_latency -source -min $MIN_SOURCE_LATENCY [get_clocks clock]

set_clock_uncertainty -setup $UNCERTAINTY [get_clocks clock]
set_clock_uncertainty -hold $UNCERTAINTY [get_clocks clock]
set_clock_transition 0.05 [get_clocks clock]

## GROUPING
group_path  -name CLOCK \
            -to [get_clocks clock] \
            -weight 1

group_path  -name INPUTS \
            -through [all_inputs] \
            -weight 1

group_path  -name OUTPUTS \
            -to [all_outputs] \
            -weight 1

group_path  -name COMBO \
            -from [all_inputs] \
            -to [all_outputs] \
            -weight 1

## IN/OUT
# We remove BOTH 'clk' and 'rst_n' from the data input delay calculations
set INPUTPORTS [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set OUTPUTPORTS [all_outputs]
 
set_input_delay -clock "clock" -max $INPUT_DELAY $INPUTPORTS
set_output_delay -clock "clock" -max $OUTPUT_DELAY $OUTPUTPORTS
set_input_delay -clock "clock" -min $MIN_IO_DELAY $INPUTPORTS
set_output_delay -clock "clock" -min $MIN_IO_DELAY $OUTPUTPORTS

## EXCEPTIONS
# Prevent the tool from optimizing the asynchronous reset tree
set_false_path -from [get_ports rst_n]

## DRC
set_max_transition $MAX_TRANSITION [current_design]
set_max_fanout 20 [current_design]
set_max_capacitance 80 [current_design]
