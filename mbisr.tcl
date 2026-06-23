################################################################################
# Tessent MBIST + Memory Repair (BISR) insertion script
#
# Adds redundancy analysis + fuse-box infrastructure on top of the plain MBIST
# flow in mbist.tcl. Two repair modes are configured:
#   - Soft repair: redundancy registers loaded on every power-up via BIST.
#   - Hard repair: results burned into an eFuse box, replayed at boot.
#
# Flow: RTL -> declare DFT signals -> spec controllers WITH Repair{} blocks
#       -> spec FuseBox + connect controllers to it
#       -> process_dft_specification -> patterns (BIST + repair + diagnosis)
#
# Usage: tessent -shell -dofile mbisr.tcl
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

set_context dft -rtl -design_id mbisr_insertion
set_log_handling -log_file $LOG_DIR/mbisr.log -replace

# ---------------------------------------------------------------------------- #
# 1. Read libraries
#    Memory libs MUST declare redundancy attributes (rows, columns, IO bits)
#    in their .lib / .tcell entries for repair to be possible.
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
read_design $DESIGN -design_id mbisr_insertion

# ---------------------------------------------------------------------------- #
# 3. DFT signals
#    fuse_* signals drive the eFuse box for hard repair.
# ---------------------------------------------------------------------------- #
add_clocks    clk          -period 10
add_clocks    tck          -period 100 -internal
add_clocks    fuse_clk     -period 40  -internal

add_dft_signals  test_clock      -source_node clk         -create_from_port
add_dft_signals  ltest_en        -source_node ltest_en    -create_from_port
add_dft_signals  mbist_en        -source_node mbist_en    -create_from_port
add_dft_signals  mbist_done      -create_with_dft_specification 1
add_dft_signals  bisr_en         -source_node bisr_en     -create_from_port
add_dft_signals  bisr_done       -create_with_dft_specification 1
add_dft_signals  fuse_program    -source_node fuse_program -create_from_port

# ---------------------------------------------------------------------------- #
# 4. Identify repairable memories
#    Filter by the memory_type attribute exported by the .lib; only memories
#    declared with redundancy can be bound to a repair-enabled controller.
# ---------------------------------------------------------------------------- #
report_memory_instances -hierarchical

set REPAIRABLE  [get_memory_instances -filter has_redundancy==true]
set CPU_MEMS    [get_memory_instances -filter {clock==clk_cpu && has_redundancy==true}]
set PRPH_MEMS   [get_memory_instances -filter {clock==clk_periph && has_redundancy==true}]
set NONREPAIR   [get_memory_instances -filter has_redundancy==false]

# ---------------------------------------------------------------------------- #
# 5. DFT specification
#    Two repair-enabled controllers + one FuseBox.
#    Repair { } block declares the analyzer; FuseBox { } declares persistent
#    storage of the repair solution.
# ---------------------------------------------------------------------------- #
set spec [create_dft_specification -sri_sib_list mbisr]

read_config_data -in_wrapper $spec -from_string {
    MemoryBist {
        # ---- c0: CPU-domain repairable memories --------------------------- #
        Controller(c0) {
            ClockDomain      : clk_cpu ;
            OperationSet     : march_c_plus_repair ;
            StepThroughMode  : off ;

            Connections {
                bist_clk : clk_cpu ;
                bist_rst : test_rst_n ;
                bist_en  : mbist_en ;
                bisr_en  : bisr_en ;
            }

            Steps {
                Step(0) { Algorithm : MarchC_Plus ;          }   # detect
                Step(1) { Algorithm : RedundancyAnalysis ;   }   # locate spares
                Step(2) { Algorithm : MarchC_Plus -post_repair ; }  # re-verify
            }

            # Per-controller repair behaviour
            Repair {
                Mode             : soft_and_hard ;
                Analyzer         : built_in ;       # internal RA engine
                AllocationPolicy : row_first ;      # try row spares before column
                DiagnosisOutput  : on ;             # leak fault locations to ATE
            }
        }

        # ---- c1: peripheral-domain repairable memories -------------------- #
        Controller(c1) {
            ClockDomain      : clk_periph ;
            OperationSet     : march_y_repair ;

            Connections {
                bist_clk : clk_periph ;
                bist_rst : test_rst_n ;
                bist_en  : mbist_en ;
                bisr_en  : bisr_en ;
            }

            Steps {
                Step(0) { Algorithm : MarchY ; }
                Step(1) { Algorithm : RedundancyAnalysis ; }
                Step(2) { Algorithm : MarchY -post_repair ; }
            }

            Repair {
                Mode             : soft_only ;     # no eFuse for periph
                Analyzer         : built_in ;
                AllocationPolicy : column_first ;
            }
        }

        # ---- Shared fuse box for hard repair persistence ------------------ #
        FuseBox(fb0) {
            Type             : efuse ;
            BitWidth         : 1024 ;          # provision per memory count
            Connections {
                fuse_clk     : fuse_clk ;
                fuse_program : fuse_program ;  # asserted during burn-in
            }
            Clients {
                Controller   : c0 ;            # only c0 burns to eFuse
            }
        }
    }
}

# Bind memories to controllers (attribute drives the wrapper inserter)
foreach m $CPU_MEMS  { set_attribute_value $m -name mbist_controller -value c0 }
foreach m $PRPH_MEMS { set_attribute_value $m -name mbist_controller -value c1 }

# Non-repairable memories: still test them, but bind to a plain controller if
# you want coverage. Left unbound here = excluded from MBIST.
if {[llength $NONREPAIR] > 0} {
    puts "INFO: [llength $NONREPAIR] memory instances have no redundancy and are excluded from BISR."
}

# ---------------------------------------------------------------------------- #
# 6. Process and insert
# ---------------------------------------------------------------------------- #
process_dft_specification

report_dft_inserted_logic        > $LOG_DIR/inserted_logic.rpt
report_dft_violations -verbose   > $LOG_DIR/dft_violations.rpt
report_memory_bist_repair        > $LOG_DIR/repair_summary.rpt

# ---------------------------------------------------------------------------- #
# 7. Write netlist + IJTAG artifacts
# ---------------------------------------------------------------------------- #
write_design          $OUTPUT_DIR/${DESIGN}_mbisr.v    -replace
write_icl             $OUTPUT_DIR/${DESIGN}_mbisr.icl  -replace
write_pdl             $OUTPUT_DIR/${DESIGN}_mbisr.pdl  -replace
write_design_data     $OUTPUT_DIR/${DESIGN}_mbisr.tsdb

# ---------------------------------------------------------------------------- #
# 8. Pattern generation
#    Three pattern sets:
#      - mbist_with_repair: detect -> analyze -> verify in one shot
#      - repair_diagnosis: dump fault map for failing dies (yield analysis)
#      - fuse_program:    burn the repair solution into the eFuse
# ---------------------------------------------------------------------------- #
set_context patterns -ijtag
open_tsdb            $OUTPUT_DIR/${DESIGN}_mbisr.tsdb
read_design          $DESIGN -design_id mbisr_insertion

create_patterns      -type mbist_with_repair -ports auto
simulate_patterns    -simulator questa -mode rtl \
                     -log $LOG_DIR/mbisr_sim.log
write_patterns       $OUTPUT_DIR/${DESIGN}_mbisr.stil -stil -replace
write_patterns       $OUTPUT_DIR/${DESIGN}_mbisr.wgl  -wgl  -replace

create_patterns      -type repair_diagnosis -ports auto
write_patterns       $OUTPUT_DIR/${DESIGN}_mbisr_diag.stil -stil -replace

create_patterns      -type fuse_program -fuse_box fb0
write_patterns       $OUTPUT_DIR/${DESIGN}_mbisr_fuse.stil -stil -replace

puts "MBIST + repair insertion + pattern generation complete."
exit 0
