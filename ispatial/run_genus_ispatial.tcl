################################################################################
# Cadence Genus iSpatial Flow
#
# iSpatial is Genus' physical-aware synthesis flow. It runs synthesis and
# placement-aware optimization inside Genus using Innovus' placement and
# routing engines under the hood, producing a netlist + DEF that correlates
# tightly with the downstream Innovus implementation.
#
# Required env vars (export before sourcing this script):
#   DESIGN_NAME       top-level module name
#   RTL_LIST          space-separated list of HDL files (or use a filelist)
#   SDC_FILE          path to top-level SDC
#   LEF_LIST          space-separated tech LEF + std cell LEFs (+ macro LEFs)
#   LIB_LIST_TYP      space-separated typical-corner .lib files
#   LIB_LIST_FAST     fast-corner .lib files (optional, for MMMC)
#   LIB_LIST_SLOW     slow-corner .lib files (optional, for MMMC)
#   QRC_TECH_TYP      typical-corner QRC techfile
#   FLOORPLAN_DEF     optional floorplan DEF; if unset, an auto floorplan is created
#   CPF_FILE          optional CPF/UPF for low-power flows
################################################################################

# -- house-keeping ------------------------------------------------------------
set DESIGN          $env(DESIGN_NAME)
set REPORTS_DIR     ./reports/${DESIGN}
set OUTPUTS_DIR     ./outputs/${DESIGN}
set DBS_DIR         ./dbs/${DESIGN}
file mkdir $REPORTS_DIR $OUTPUTS_DIR $DBS_DIR

set_db max_cpus_per_server      16
set_db super_thread_servers     {localhost}
set_db information_level        7
set_db hdl_error_on_blackbox    true
set_db hdl_track_filename_row_col true

# iSpatial is enabled by selecting the physical flow effort.
# "extreme" turns on the full iSpatial (physical synthesis with Innovus engines).
set_db design_flow_effort       extreme
set_db design_power_effort      high

# Use the unified flow (Genus + Innovus shared DB)
set_db invs_temp_dir            ./invs_tmp

# -- libraries ---------------------------------------------------------------
# MMMC setup -- adjust corner/mode/view names to match your project
create_library_set -name LIB_TYP  -timing $env(LIB_LIST_TYP)
if {[info exists env(LIB_LIST_FAST)]} {
    create_library_set -name LIB_FAST -timing $env(LIB_LIST_FAST)
}
if {[info exists env(LIB_LIST_SLOW)]} {
    create_library_set -name LIB_SLOW -timing $env(LIB_LIST_SLOW)
}

create_rc_corner   -name RC_TYP -qx_tech_file $env(QRC_TECH_TYP)
create_delay_corner -name DC_TYP -library_set LIB_TYP -rc_corner RC_TYP

# constraint + mode
create_constraint_mode -name FUNC -sdc_files $env(SDC_FILE)
create_analysis_view   -name AV_TYP -constraint_mode FUNC -delay_corner DC_TYP

set_analysis_view -setup {AV_TYP} -hold {AV_TYP}

# physical libraries
set_db library                  $env(LIB_LIST_TYP)
set_db lef_library              $env(LEF_LIST)
set_db qrc_tech_file            $env(QRC_TECH_TYP)

# optional low-power
if {[info exists env(CPF_FILE)]} {
    read_power_intent -cpf $env(CPF_FILE)
}

# -- RTL ---------------------------------------------------------------------
read_hdl -sv $env(RTL_LIST)
elaborate $DESIGN
time_info Elaboration

check_design -unresolved
write_db -all_root_attributes $DBS_DIR/${DESIGN}_elab.db

# -- constraints -------------------------------------------------------------
init_design
if {[info exists env(CPF_FILE)]} { commit_power_intent }
check_design -all > $REPORTS_DIR/check_design.rpt

# -- floorplan ---------------------------------------------------------------
# iSpatial requires physical context. Either read a real DEF or let Genus
# create an auto floorplan from the std-cell area + utilization target.
if {[info exists env(FLOORPLAN_DEF)] && [file exists $env(FLOORPLAN_DEF)]} {
    read_def $env(FLOORPLAN_DEF)
} else {
    # Auto-floorplan: 70% util, square aspect ratio. Tune for your design.
    set_db floorplan_target_utilization 0.70
    set_db floorplan_aspect_ratio       1.0
    create_floorplan -site core
}

# -- generic synthesis -------------------------------------------------------
syn_generic
time_info Generic
write_snapshot   -outdir $REPORTS_DIR -tag generic
report_summary   -directory $REPORTS_DIR

# -- map to technology -------------------------------------------------------
syn_map
time_info Map
write_snapshot   -outdir $REPORTS_DIR -tag map
report_summary   -directory $REPORTS_DIR

# -- iSpatial physical optimization ------------------------------------------
# syn_opt with design_flow_effort=extreme performs placement + congestion +
# route-aware optimization using the Innovus engines.
syn_opt
time_info Opt
write_snapshot   -outdir $REPORTS_DIR -tag opt
report_summary   -directory $REPORTS_DIR

# -- reporting ---------------------------------------------------------------
report_timing -late  -max_paths 50 > $REPORTS_DIR/${DESIGN}_timing_setup.rpt
report_timing -early -max_paths 50 > $REPORTS_DIR/${DESIGN}_timing_hold.rpt
report_power                       > $REPORTS_DIR/${DESIGN}_power.rpt
report_area                        > $REPORTS_DIR/${DESIGN}_area.rpt
report_gates  -power               > $REPORTS_DIR/${DESIGN}_gates.rpt
report_congestion                  > $REPORTS_DIR/${DESIGN}_congestion.rpt
report_clock_gating                > $REPORTS_DIR/${DESIGN}_clkgate.rpt
report_messages                    > $REPORTS_DIR/${DESIGN}_messages.rpt

# -- write outputs for Innovus handoff ---------------------------------------
write_hdl                          > $OUTPUTS_DIR/${DESIGN}.v
write_script                       > $OUTPUTS_DIR/${DESIGN}.script
write_sdc                          > $OUTPUTS_DIR/${DESIGN}.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge \
                                     > $OUTPUTS_DIR/${DESIGN}.sdf

# iSpatial handoff: DEF + Innovus DB so P&R can resume from this placement.
write_design -innovus -base_name $OUTPUTS_DIR/${DESIGN}_invs
write_def                          > $OUTPUTS_DIR/${DESIGN}.def

# Save the final Genus DB for incremental ECO runs
write_db $DBS_DIR/${DESIGN}_final.db

puts "iSpatial flow complete for design: $DESIGN"
quit
