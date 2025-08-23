HarvOS W^X + NX-RAM Overlay (SVA)
=================================

Ziel
----
- **W^X**: Schreibbare Seiten dürfen nie ausführbar sein.
- **NX-RAM**: Physisches RAM darf nicht als ausführbar gemappt werden.
- **D-Pfad NX**: DTLB/X-Flag muss immer 0 bleiben.

Inhalt
------
- `harvos_wx_nx_sva.sv`   — Assertions, die in `mmu_sv32` hineinbinden und drei Checks durchsetzen:
  1) W^X: Raw-PTE darf nicht `W&X` gesetzt haben (zeigt OS-Fehlkonfig).
  2) DTLB X-Bit bleibt 0 (D-Pfad NX).
  3) I-seitige Ausführung aus RAM wird geflaggt (NX-RAM).
- `harvos_wx_nx_bind.sv`  — `bind`-Modul, das die SVA an `mmu_sv32` anhängt (RAM-Fenster parametrisierbar).
- `tb_wx_nx_skeleton.sv`  — Sim-Skelett; in der Praxis bindest du die Files einfach zu deinem SoC-TB hinzu.

Einbindung
----------
1) Lege die Dateien unter `src/rtl/` und `src/tb/` ab (oder beliebig in deinem Sim-Filelist).
2) Passe in `harvos_wx_nx_bind.sv` die `RAM_BASE/LIMIT` auf eure SRAM-Range an.
3) Füge in deiner Sim-Filelist hinzu:
   - `src/rtl/harvos_wx_nx_sva.sv`
   - `src/rtl/harvos_wx_nx_bind.sv`
4) Baue & simuliere deine bestehenden Tests; Violations erscheinen als `$error(...)`-Meldungen.

Hinweise
--------
- Das Overlay nutzt nur existierende Symbole aus `mmu_sv32` (u. a. `dtlb_v/_idx/_p_x`, `itlb_v/_idx/_paddr`,
  `ptw_rdata`, `pte_*`-Funktionen). Sollten die Namen bei dir abweichen, editiere `harvos_wx_nx_sva.sv` entsprechend.
- Für formale Verifikation kannst du die `$error`-Blöcke in SVA-Properies überführen; hier bleiben wir Verilog-2005-kompatibel.
- In Kombination mit den vorherigen Overlays (DMA-Firewall, Code-Immutabilität, Alias-Guard, satp.MODE) ergibt sich die
  geforderte, **durchgängige** W^X/NX-Garantie.
