# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

This directory (`tk/`) is a driver workspace, not a self-contained project. The only tracked artifact in this folder is `Makefile`; everything it operates on lives outside the repo:

- Source RTL release tree: `/home/projects/projects/leo/projects/release_to_dft/`
- DFT input tree: `/home/projects/projects/DFT_IN/projects/`
- Per-block working dirs (expected as siblings of the Makefile): `btc_top_wrap/`, `codec_top_wrap/`, `flexible_top_wrap/`, `wlan_top_wrap/` — none of these are checked in.

Because the Makefile shells out to external scripts (`.run/release_block.csh`, `run_verdi`, `.run_drc_check`) and an LSF cluster (`bsub -q dig`), targets cannot be exercised on this Windows host. Treat the Makefile as a launcher that only runs in the team's Linux + Synopsys + LSF environment.

## Common commands

All targets are fan-outs across the four top wrappers (`btc`, `codec`, `flexible`, `wlan`). They are not idempotent — each spawns multiple `xterm` windows in parallel.

| Target | What it does |
| --- | --- |
| `make gen_dft_files` | Wipes `DFT_IN/.../top_common/`, copies fresh `top_common/` from the release tree, then launches `release_block.csh <block>` in an xterm per block. |
| `make chk_files` | Opens all `*/.*/rtl/flist/flist_*.f` in vim tabs for manual inspection. |
| `make verdi` | Strips `#` comment lines from every `flist_*.f`, then launches Verdi (`run_verdi`) per block in its own xterm. |
| `make ltest` | Submits a per-block `.run_drc_check` job to LSF queue `dig` (51 GB reservation) via `bsub -Ip`, each in its own xterm. |
| `make` / `make default` | Runs `clean` — but no `clean` target is defined here, so this currently errors. |

## Things to know before editing

- **Side effects are destructive.** `gen_dft_files` does `rm -rf /home/projects/.../DFT_IN/.../top_common/` before copying. Do not reorder or run partial commands without understanding which tree is being overwritten.
- **`verdi` mutates source flists in place** via `sed -i "/^#.*/d"` — comment-stripping is permanent. If you change the sed pattern, remember it edits the team's release flists, not local copies.
- **Block list is hard-coded** in four parallel `xterm -e` lines per target. Adding/removing a block means editing each target.
- **`default: clean` is broken** — there is no `clean` rule. Either add one or change the default before relying on bare `make`.
- The sibling `.Makefile.swp` indicates an active vim session; check before overwriting `Makefile`.

## Relationship to the parent workspace

The parent directory `D:\GitHub\cc_temp\` is the actual git repo root and contains a *different* Makefile plus Tessent MBIST/MBISR TCL flows (`mbist.tcl`, `mbisr.tcl`, `ispatial/`). That work is unrelated to this `tk/` launcher — do not conflate the two Makefiles.
