# ============================================================================
# Workspace Makefile - DFT flow
# ============================================================================

DESIGN       ?= top
WORK_DIR     ?= work
OUTPUT_DIR   ?= output
LOG_DIR      ?= log

TESSENT      ?= tessent
TESSENT_OPTS ?= -shell -logfile $(LOG_DIR)/$@.log -replace

SCRIPT_DIR   ?= .
MBIST_TCL    ?= $(SCRIPT_DIR)/mbist.tcl
MBISR_TCL    ?= $(SCRIPT_DIR)/mbisr.tcl

# ---------------------------------------------------------------------------
# Phony targets
# ---------------------------------------------------------------------------
.PHONY: all dirs mbist mbisr clean distclean help

all: mbist

dirs:
	@mkdir -p $(WORK_DIR) $(OUTPUT_DIR) $(LOG_DIR)

# ---------------------------------------------------------------------------
# MBIST insertion + pattern generation
# Output: $(OUTPUT_DIR)/$(DESIGN)_mbist.{v,icl,pdl,stil}
# ---------------------------------------------------------------------------
mbist: dirs $(OUTPUT_DIR)/$(DESIGN)_mbist.v

$(OUTPUT_DIR)/$(DESIGN)_mbist.v: $(MBIST_TCL)
	@echo "[mbist] running $(MBIST_TCL)"
	$(TESSENT) $(TESSENT_OPTS) -dofile $(MBIST_TCL) \
		2>&1 | tee $(LOG_DIR)/mbist.console.log
	@echo "[mbist] done -> $@"

# ---------------------------------------------------------------------------
# MBIST + memory repair (BISR) insertion + pattern generation
# Output: $(OUTPUT_DIR)/$(DESIGN)_mbisr.{v,icl,pdl,stil,wgl}
# ---------------------------------------------------------------------------
mbisr: dirs $(OUTPUT_DIR)/$(DESIGN)_mbisr.v

$(OUTPUT_DIR)/$(DESIGN)_mbisr.v: $(MBISR_TCL)
	@echo "[mbisr] running $(MBISR_TCL)"
	$(TESSENT) $(TESSENT_OPTS) -dofile $(MBISR_TCL) \
		2>&1 | tee $(LOG_DIR)/mbisr.console.log
	@echo "[mbisr] done -> $@"

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------
clean:
	rm -rf $(LOG_DIR) $(WORK_DIR)

distclean: clean
	rm -rf $(OUTPUT_DIR)

help:
	@echo "Targets:"
	@echo "  make mbist      - run Tessent MBIST insertion + pattern gen"
	@echo "  make mbisr      - run Tessent MBIST + memory repair (BISR) flow"
	@echo "  make clean      - remove logs and work dir"
	@echo "  make distclean  - also remove generated netlist/patterns"
	@echo ""
	@echo "Overrides: DESIGN=<name>  TESSENT=<path>  MBIST_TCL=<file>  MBISR_TCL=<file>"
