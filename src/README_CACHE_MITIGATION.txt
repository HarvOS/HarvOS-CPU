HarvOS Cache-Mitigation (Kontext-Flush + Way-Mask Hooks)
========================================================

Ziel
----
Cross-Context-Leakage aus I/D-Caches reduzieren. Zwei Wege:
1) **Kontextwechsel-Flush**: I- & D-Cache bei ASID-Wechsel (SATP) oder globalem SFENCE invalidieren.
2) **Way-Partitioning** (optional): Per-ASID (oder global) Way-Masken vorgeben, sodass Kontexte getrennte Ways nutzen.

Bausteine
---------
- `asid_change_pulse.sv` — 1‑Zyklus‑Puls bei ASID‑Wechsel auf SATP‑Write.
- `cache_sec_ctrl.sv` — MMIO‑Control: Sticky‑Enables (Flush on ASID/SFENCE), manuelle Flush‑Trigger, Way‑Masken (I/D) und LOCK‑Respect.
- `cache_flush_adapter.sv` — streckt `flush_req` zu einem `invalidate_all`‑Signal mit Haltefenster/ACK.
- `cache_waymask_if.sv` — simples IF für Way‑Mask‑Durchreichung in die Caches.
- `cache_flush_asserts.sv` — Assertions: nach ASID‑Pulse müssen Flush‑Requests zeitnah kommen.
- `tb_cache_ctrl.sv` — TB‑Skeleton, zeigt Sequenz.

Einbindung (Kurz)
-----------------
- In **CSR/SATP‑Pfad**: `satp_wr_en`, `csr_satp_q`, `satp_wr_wdata` an `asid_change_pulse` → Puls.
- In **SoC‑Top**: `cache_sec_ctrl` instanzieren, `asid_change_pulse` und `sfence_global` (falls vorhanden) anschließen. `lock_i = smpuctl.LOCK`.
- Zu den **Caches**:
  - `ic_flush_req`/`dc_flush_req` über `cache_flush_adapter` auf eure Invalid‑All‑Eingänge führen.
  - `ic_way_mask`/`dc_way_mask` in die Replacement‑Logik einkoppeln (z. B. Round‑Robin über aktivierte Ways).
- **MMIO‑Reg** des `cache_sec_ctrl` an eine freie Adresse mappen; Boot setzt Policy und kann bei Bedarf Force‑Flush triggern.

Empfohlene Policy
-----------------
- Default **Flush on ASID** und **Flush on SFENCE** aktiv (im Modul schon so voreingestellt).
- Replacement‑Politik **deterministisch** (Round‑Robin) konfigurieren.
- Optional: Statische Way‑Masken (z. B. I/D je 4 Ways → ASID%2 steuert 0b0011/0b1100). Diese Logik liegt in euren Caches; `cache_sec_ctrl` liefert nur die Masken.

Hinweis
------
Die Module sind **bus-/cache-agnostisch**. Für AXI‑ICache/DCache brauchst du lediglich einen Invalid‑All‑Input oder iteratives Invalidate.
LOCK verhindert, dass Policies nach dem Boot manipuliert werden.
