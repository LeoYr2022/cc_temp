#!/usr/bin/env bash
# Wrapper to launch Genus in iSpatial mode.
# Edit the exports below for your project, then: ./run_ispatial.sh
set -euo pipefail

# ---- project setup ---------------------------------------------------------
export DESIGN_NAME="my_top"
export PROCESS_NODE="7"   # process node in nm (7, 16, 28, ...)

export RTL_LIST="$(ls ./rtl/*.v ./rtl/*.sv 2>/dev/null | xargs)"
export SDC_FILE="./constraints/${DESIGN_NAME}.sdc"

export LEF_LIST="$(ls ./pdk/lef/*.lef | xargs)"
export LIB_LIST_TYP="$(ls ./pdk/lib/typ/*.lib | xargs)"
# Optional MMMC corners:
# export LIB_LIST_FAST="$(ls ./pdk/lib/fast/*.lib | xargs)"
# export LIB_LIST_SLOW="$(ls ./pdk/lib/slow/*.lib | xargs)"

export QRC_TECH_TYP="./pdk/qrc/typ/qrcTechFile"

# Optional floorplan + power intent:
# export FLOORPLAN_DEF="./floorplan/${DESIGN_NAME}.def"
# export CPF_FILE="./power/${DESIGN_NAME}.cpf"

# ---- launch ----------------------------------------------------------------
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"

genus -legacy_ui -files run_genus_ispatial.tcl \
      -log    "${LOG_DIR}/genus_${DESIGN_NAME}_${STAMP}.log" \
      -cmdfile "${LOG_DIR}/genus_${DESIGN_NAME}_${STAMP}.cmd" \
      -no_gui
