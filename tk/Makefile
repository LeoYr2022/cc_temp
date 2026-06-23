# ============================================================================
# DFT driver Makefile — fans tasks out across the top wrappers.
# Add or remove a name in BLOCKS and every target picks it up automatically.
# ============================================================================

BLOCKS ?= codec_top_wrap flexible_top_wrap wlan_top_wrap btc_top_wrap

# Team filesystem paths — override on the command line if layout differs.
DFT_IN      ?= /home/projects/projects/DFT_IN/projects
RELEASE_SRC ?= /home/projects/projects/leo/projects/release_to_dft

# Flist files cleaned before Verdi / inspected by chk_files.
FLISTS := ./*/.*/rtl/flist/flist_*.f

# LSF + xterm options for ltest.
BSUB_OPTS  := -Ip -q dig -R"rusage[mem=51200]" -M 51200!
XTERM_OPTS := -bg gray -fa 'Monospace' -fs 14

RELEASE_TARGETS := $(addprefix release-,$(BLOCKS))
VERDI_TARGETS   := $(addprefix verdi-,$(BLOCKS))
LTEST_TARGETS   := $(addprefix ltest-,$(BLOCKS))

.PHONY: default help \
        gen_dft_files chk_files verdi ltest \
        prep_top_common strip_flist \
        $(RELEASE_TARGETS) $(VERDI_TARGETS) $(LTEST_TARGETS)

default: help

help:
	@echo "Targets:"
	@echo "  gen_dft_files  refresh top_common in DFT_IN, then release each block in its own xterm"
	@echo "  chk_files      open every release flist in vim tabs"
	@echo "  verdi          strip '#' lines from flists, launch Verdi per block"
	@echo "  ltest          submit per-block DRC check to LSF queue 'dig'"
	@echo ""
	@echo "Per-block targets (run one block only):"
	@echo "  make release-btc_top_wrap | verdi-btc_top_wrap | ltest-btc_top_wrap"
	@echo ""
	@echo "Override on the command line:"
	@echo "  make verdi BLOCKS='btc_top_wrap codec_top_wrap'"
	@echo "  make gen_dft_files DFT_IN=/path RELEASE_SRC=/path"

# ----------------------------------------------------------------------------
# gen_dft_files — refresh top_common then spawn a release xterm per block
# ----------------------------------------------------------------------------
gen_dft_files: prep_top_common $(RELEASE_TARGETS)

prep_top_common:
	@echo "-- Gen DFT RTL --"
	rm -rf $(DFT_IN)/top_common/
	cp -r $(RELEASE_SRC)/top_common $(DFT_IN)/top_common/

release-%:
	xterm -e "./.run/release_block.csh $*" &

# ----------------------------------------------------------------------------
# chk_files — eyeball the released flists
# ----------------------------------------------------------------------------
chk_files:
	@echo "-- Check copy files --"
	vim -p $(FLISTS)

# ----------------------------------------------------------------------------
# verdi — strip flist comments then spawn a Verdi xterm per block
# ----------------------------------------------------------------------------
verdi: strip_flist $(VERDI_TARGETS)

strip_flist:
	@echo "-- Build Verdi --"
	sed -i "/^#.*/d" $(FLISTS)

verdi-%:
	xterm -title "verdi_$*" -e 'cd $*/verdi && run_verdi' &

# ----------------------------------------------------------------------------
# ltest — submit a DRC-check LSF job per block
# ----------------------------------------------------------------------------
ltest: $(LTEST_TARGETS)

ltest-%:
	bsub $(BSUB_OPTS) xterm $(XTERM_OPTS) -title "ltest_$*" -e 'cd $*/ts && .run_drc_check' &
