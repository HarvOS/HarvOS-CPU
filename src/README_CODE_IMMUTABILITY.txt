HarvOS Code-Speicher-Immutabilität (Overlay)
===========================================

Ziel
----
Nach dem Boot sollen Code-/XIP-Bereiche **hardwareseitig** schreibgeschützt sein. Updates erfolgen nur noch
vor Setzen von LOCK (oder in der Fertigung per Strap), idealerweise über A/B-Slot und Reboot.

Bausteine
---------
1. `code_wp_latch.sv` — Sticky Write-Protect-Latch (setzt sich bei `LOCK=1` oder bei MMIO `WP_SET=1`; nie rücksetzbar ohne Reset).
2. `code_guard.sv`    — Schreibschutzlogik: blockiert **alle** Writes in Code-Fenster, außer im expliziten Update-Fenster vor LOCK.
3. `code_sec_ctrl.sv` — MMIO-Steuerregister mit zwei Write-1-to-Set-Bits: `UPDATE_EN_SET` und `WP_SET`.
4. `tb_code_guard_lock.sv` — Testbench, die den Ablauf zeigt (Update-Fenster -> WP_SET -> LOCK).

Einbindung (Kurz)
-----------------
- Platziere `code_guard` im Interconnect-Pfad für **CPU-Datenbus** und ggf. Peripherie, die Code-Fenster ansprechen kann (Flash-Controller).
- Deny/Allow erfolgt über `allow_write`. Bei `0` gibst du eine Bus-Fehlerantwort (z. B. SLVERR/DECERR) oder nackt NACK zurück.
- `code_wp_latch` erhält `lock_i` (z. B. `smpuctl[0]`) und den Puls `wp_set_pulse` aus `code_sec_ctrl`.
- `code_sec_ctrl` als MMIO-Register einbinden; Boot-ROM schreibt:
  1) `UPDATE_EN_SET=1` (öffnet Update-Fenster),
  2) Programmierung/Copy in den Code-Slot,
  3) `WP_SET=1` (setzt permanente WP),
  4) `LOCK=1` (CSR `smpuctl`), dann Sprung in den Kernel.

A/B-Update (Empfehlung)
-----------------------
- Reserviere zwei Code-Slots (A/B) und setze den aktiven Slot über einen **separaten, sticky** Boot-Selector (nicht im Paket enthalten).
- Update schreibe in den inaktiven Slot, dann setze `WP_SET`, setze `LOCK`, **Reboot** → Boot-ROM wählt den neuen Slot.

Test
----
- Simuliere `tb_code_guard_lock.sv`: Vor LOCK ohne `UPDATE_EN_SET` sind Writes in Code verboten; mit Update-Enable erlaubt;
  nach `WP_SET` und nach `LOCK` sind sie hardwareseitig verboten.

Hinweise
--------
- In Kombination mit der DMA-Firewall (I-Space Hard-Deny) wird verhindert, dass DMA am Schutz vorbeischreibt.
- Falls ein Debug-Port (JTAG/SWD) in den Flash schreiben kann, muss auch dort eine **post-LOCK**-Sperre verdrahtet werden
  (z. B. Debug-AP blockiert Programmierkommandos, solange `wp_q=1`).

