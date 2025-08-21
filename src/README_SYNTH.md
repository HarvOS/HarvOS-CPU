# HarvOS Synthesis Guide

yosys -s synth_harvos.ys | tee synth_xc7.log

## Notes
- Target family: xc7 (Xilinx Artix/Kintex/Zynq-7000).
- Edit scripts for other families (e.g., `synth_ecp5`, `synth_intel`).
- See `stat` report in log for LUT/FF/BRAM usage.
