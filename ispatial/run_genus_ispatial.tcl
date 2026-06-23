################################################################################
# Cadence Genus iSpatial Flow
#
# iSpatial is Genus' physical-aware synthesis flow built on a unified
# Genus/Innovus session. The Innovus placement engine and NanoRoute estimator
# run inside Genus, so placement, legalization, and parasitic estimates are
# real (not PLE-style estimates). Handoff to Innovus implementation is a
# shared Innovus database.
#
# Required env vars:
#   DESIGN_NAME       top-level module name
#   PROCESS_NODE      process node in nm (e.g. 7, 16, 28)
#   RTL_LIST          space-separated list of HDL files
#   SDC_FILE          path to top-level SDC
#   LEF_LIST          tech LEF + std cell LEFs (+ macro LEFs)
#   LIB_LIST_TYP      typical-corner .lib files
#   LIB_LIST_FAST     fast-corner .lib files (optional, MMMC)
#   LIB_LIST_SLOW     slow-corner .lib files (optional, MMMC)
#   QRC_TECH_TYP      typical-corner QRC techfile
#   FLOORPLAN_DEF     floorplan DEF (strongly recommended for iSpatial)
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

# -- iSpatial mode -----------------------------------------------------------
# What actually selects the iSpatial flow:
#   common_ui true              - unified Genus/Innovus session
#   design_flow_effort extreme  - turns on physical synthesis with the
#                                 embedded Innovus placement engine
# NOTE: do NOT set interconnect_mode to ple here -- PLE is the older
# pre-iSpatial estimation mode and conflicts with real iSpatial placement.
set_db common_ui                true
set_db design_flow_effort       extreme
set_db design_process_node      $env(PROCESS_NODE)
set_db design_power_effort      high
set_db lp_insert_clock_gating   true

# -- physical libraries ------------------------------------------------------
read_physical -lefs $env(LEF_LIST)

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

# -- MMMC (timing only -- physical libs already loaded above) ----------------
create_library_set -name LIB_TYP -timing $env(LIB_LIST_TYP)
if {[info exists env(LIB_LIST_FAST)]} {
    create_library_set -name LIB_FAST -timing $env(LIB_LIST_FAST)
}
if {[info exists env(LIB_LIST_SLOW)]} {
    create_library_set -name LIB_SLOW -timing $env(LIB_LIST_SLOW)
}

create_rc_corner       -name RC_TYP -qx_tech_file $env(QRC_TECH_TYP)
create_delay_corner    -name DC_TYP -library_set LIB_TYP -rc_corner RC_TYP
create_constraint_mode -name FUNC   -sdc_files $env(SDC_FILE)
create_analysis_view   -name AV_TYP -constraint_mode FUNC -delay_corner DC_TYP
set_analysis_view -setup {AV_TYP} -hold {AV_TYP}

# -- init design (Innovus engine attaches here) ------------------------------
init_design
if {[info exists env(CPF_FILE)]} { commit_power_intent }
check_design -all > $REPORTS_DIR/check_design.rpt

# -- floorplan ---------------------------------------------------------------
# A real DEF is what makes iSpatial worthwhile -- the embedded Innovus engine
# places into this floorplan and feeds back accurate timing/congestion.
if {[info exists env(FLOORPLAN_DEF)] && [file exists $env(FLOORPLAN_DEF)]} {
    read_def $env(FLOORPLAN_DEF)
} else {
    puts "WARNING: no FLOORPLAN_DEF supplied; iSpatial QoR will be approximate."
    set_db floorplan_target_utilization 0.70
    set_db floorplan_aspect_ratio       1.0
    create_floorplan -site core
}

# -- synthesis stages (all placement-aware once design_flow_effort=extreme) --
syn_generic
time_info Generic
write_snapshot -outdir $REPORTS_DIR -tag generic
report_summary -directory $REPORTS_DIR

syn_map
time_info Map
write_snapshot -outdir $REPORTS_DIR -tag map
report_summary -directory $REPORTS_DIR

syn_opt
time_info Opt
write_snapshot -outdir $REPORTS_DIR -tag opt
report_summary -directory $REPORTS_DIR

# -- reporting ---------------------------------------------------------------
report_timing -late  -max_paths 50 > $REPORTS_DIR/${DESIGN}_timing_setup.rpt
report_timing -early -max_paths 50 > $REPORTS_DIR/${DESIGN}_timing_hold.rpt
report_power                       > $REPORTS_DIR/${DESIGN}_power.rpt
report_area                        > $REPORTS_DIR/${DESIGN}_area.rpt
report_gates  -power               > $REPORTS_DIR/${DESIGN}_gates.rpt
report_congestion                  > $REPORTS_DIR/${DESIGN}_congestion.rpt
report_clock_gating                > $REPORTS_DIR/${DESIGN}_clkgate.rpt
report_messages                    > $REPORTS_DIR/${DESIGN}_messages.rpt

# -- handoff to Innovus ------------------------------------------------------
# iSpatial's canonical handoff is the shared Innovus DB produced by
# write_design -innovus. The .v/.sdc/.sdf are emitted for ECO and sign-off
# tools, not for Innovus to re-place from.
write_design -innovus -base_name $OUTPUTS_DIR/${DESIGN}
write_hdl  > $OUTPUTS_DIR/${DESIGN}.v
write_sdc  > $OUTPUTS_DIR/${DESIGN}.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge \
           > $OUTPUTS_DIR/${DESIGN}.sdf

write_db $DBS_DIR/${DESIGN}_final.db

puts "iSpatial flow complete for design: $DESIGN"
quit
