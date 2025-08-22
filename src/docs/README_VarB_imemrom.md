# Variante B – Integration über `imem_rom.sv`

Diese Variante hängt ein **ROM‐Modul** an den **Harvard I‑Port** und lädt das Programm per `$readmemh` aus einer **HEX**.

## Dateien
- `rtl/imem_rom.sv` – ROM mit Param `HEXFILE` (Default `hello.hex`).
- `sim/tb_harvos_core_imemrom.sv` – Testbench, die `imem_rom` instanziert und einen einfachen DMEM verwendet.

## Verwendung
1. Baue die HEX (siehe P2.7 Tooling):
   ```bash
   cd sw/boot
   make       # erzeugt hello.hex
   ```
2. Simuliere (Beispiel Questa, vorausgesetzt dein Tree liegt in `../../HarvOS-main/src/rtl`):
   ```bash
   cd ../../sim
   vlog ../rtl/imem_rom.sv ../../HarvOS-main/src/rtl/*.sv tb_harvos_core_imemrom.sv
   vsim -c tb_harvos_core_imemrom -do "run -all; quit"
   ```
3. Ergebnis prüfen: In den Wellen den Fetch aus dem ROM sehen oder RAM‐Seitenwirkungen (z. B. Counter bei `0x2000_0000`) beobachten.

> Vorteil: Wiederverwendbares ROM‐Modul, das du in allen TBs/SoC-Top‐Leveln identisch verwenden kannst.
