################################################################################
# Tessent MBIST insertion script
#
# Flow: RTL  -> add DFT signals -> specify MBIST controllers
#       -> create_dft_specification -> process_dft_specification
#       -> extract_icl / create_patterns -> write netlist + patterns
#
# Usage: tessent -shell -dofile mbist.tcl
################################################################################

# ---------------------------------------------------------------------------- #
# 0. User variables
# ---------------------------------------------------------------------------- #
set DESIGN          top
set RTL_DIR         ../rtl
set LIB_DIR         ../lib
set MEM_LIB_DIR     ../lib/memory
set OUTPUT_DIR      ./output
set LOG_DIR         ./log

file mkdir $OUTPUT_DIR $LOG_DIR

set_context dft -rtl -design_id mbist_insertion
set_log_handling -log_file $LOG_DIR/mbist.log -replace

# ---------------------------------------------------------------------------- #
# 1. Read libraries (standard cells + memory wrappers / Tessent cell libs)
# ---------------------------------------------------------------------------- #
read_cell_library  $LIB_DIR/stdcell.tcell
foreach mem_lib [glob -nocomplain $MEM_LIB_DIR/*.lib] {
    read_cell_library $mem_lib
}

# ---------------------------------------------------------------------------- #
# 2. Read RTL and elaborate
# ---------------------------------------------------------------------------- #
foreach f [glob -nocomplain $RTL_DIR/*.v $RTL_DIR/*.sv] {
    read_verilog $f
}
set_current_design $DESIGN
read_design $DESIGN -design_id mbist_insertion

# ---------------------------------------------------------------------------- #
# 3. Declare DFT signals (clocks, resets, test mode pins)
# ---------------------------------------------------------------------------- #
add_clocks    clk      -period 10
add_clocks    tck      -period 100 -internal

add_dft_signals  test_clock     -source_node clk     -create_from_port
add_dft_signals  ltest_en       -source_node ltest_en -create_from_port
add_dft_signals  mbist_en       -source_node mbist_en -create_from_port
add_dft_signals  mbist_done     -create_with_dft_specification 1

# ---------------------------------------------------------------------------- #
# 4. Identify memories and group them per controller
#    (group memories that share clock domain / power domain / collar style)
# ---------------------------------------------------------------------------- #
report_memory_instances -hierarchical

# Example: two controllers, grouped by clock domain
set CTRL0_MEMS [get_memory_instances -filter clock==clk_cpu]
set CTRL1_MEMS [get_memory_instances -filter clock==clk_periph]

# ---------------------------------------------------------------------------- #
# 5. DFT specification - create wrapper for MBIST
# ---------------------------------------------------------------------------- #
set spec [create_dft_specification -sri_sib_list mbist]

# --- controller 0 -----------------------------------------------------------
read_config_data -in_wrapper $spec -from_string {
    MemoryBist {
        Controller(c0) {
            ClockDomain      : clk_cpu ;
            OperationSet     : march_c_plus ;
            StepThroughMode  : off ;
            Connections {
                bist_clk : clk_cpu ;
                bist_rst : test_rst_n ;
                bist_en  : mbist_en ;
            }
            Steps {
                Step(0) { Algorithm : MarchC_Plus ; }
                Step(1) { Algorithm : Checkerboard ; }
            }
        }
        Controller(c1) {
            ClockDomain      : clk_periph ;
            OperationSet     : march_y ;
        }
    }
}

# Bind memories to controllers
foreach m $CTRL0_MEMS { set_attribute_value $m -name mbist_controller -value c0 }
foreach m $CTRL1_MEMS { set_attribute_value $m -name mbist_controller -value c1 }

# ---------------------------------------------------------------------------- #
# 6. Process and insert
# ---------------------------------------------------------------------------- #
process_dft_specification
report_dft_inserted_logic       > $LOG_DIR/inserted_logic.rpt
report_dft_violations -verbose  > $LOG_DIR/dft_violations.rpt

# ---------------------------------------------------------------------------- #
# 7. Write out modified netlist + ICL + PDL for downstream patterns
# ---------------------------------------------------------------------------- #
write_design                 $OUTPUT_DIR/${DESIGN}_mbist.v   -replace
write_icl                    $OUTPUT_DIR/${DESIGN}_mbist.icl -replace
write_pdl                    $OUTPUT_DIR/${DESIGN}_mbist.pdl -replace
write_design_data            $OUTPUT_DIR/${DESIGN}_mbist.tsdb

# ---------------------------------------------------------------------------- #
# 8. Switch to pattern context, generate manufacturing patterns
# ---------------------------------------------------------------------------- #
set_context patterns -ijtag
open_tsdb            $OUTPUT_DIR/${DESIGN}_mbist.tsdb
read_design          $DESIGN -design_id mbist_insertion

create_patterns      -type mbist -ports auto
simulate_patterns    -simulator questa -mode rtl \
                     -log $LOG_DIR/mbist_sim.log
write_patterns       $OUTPUT_DIR/${DESIGN}_mbist.stil -stil -replace
write_patterns       $OUTPUT_DIR/${DESIGN}_mbist.wgl  -wgl  -replace

puts "MBIST insertion + pattern generation complete."
exit 0
