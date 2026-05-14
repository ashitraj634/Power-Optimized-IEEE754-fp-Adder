# run_synth.tcl (BASELINE WITH WRAPPER)

# 1. Setup University Technology Libraries (USE YOUR ABSOLUTE PATH!)
set_db init_lib_search_path ./lib/timing
read_libs {fast_vdd1v0_basicCells_hvt.lib  slow_vdd1v0_basicCells_hvt.lib fast_vdd1v0_basicCells.lib      slow_vdd1v0_basicCells.lib fast_vdd1v0_basicCells_lvt.lib  slow_vdd1v0_basicCells_lvt.lib fast_vdd1v2_basicCells_hvt.lib  slow_vdd1v2_basicCells_hvt.lib fast_vdd1v2_basicCells.lib      slow_vdd1v2_basicCells.lib fast_vdd1v2_basicCells_lvt.lib  slow_vdd1v2_basicCells_lvt.lib}

# 2. Read the RTL 
read_hdl fp_adder_baseline.v
read_hdl fp_adder_wrapper.v

# 3. Elaborate the WRAPPER module
elaborate fp_adder_wrapper

# 4. Read Constraints
read_sdc constraints.sdc

# 5. Read the VCD (The baseline power proof)
read_vcd baseline.vcd

# 6. Enable High-Effort Power Analysis
set_db / .lp_power_analysis_effort high
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

# 7. Synthesize
syn_generic
syn_map
syn_opt

# 8. Generate the Reports
report_timing > report_timing.rpt
report_power  > report_power.rpt
report_area   > report_area.rpt

puts "================================================="
puts "   BASELINE SYNTHESIS COMPLETE!"
puts "================================================="
#exit
