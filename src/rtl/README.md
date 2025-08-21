# HarvOS
A secure server ecosystem

# HarvOS — A Secure Harvard-Architecture Operating System & CPU

HarvOS is a research concept for a **secure, minimalistic operating system and processor design** that prioritizes *trustworthiness over raw performance*.  
It introduces a novel combination of **Harvard separation**, **MMU**, and **MPU**, aiming to make entire classes of software exploits *structurally impossible*.

---

## 🔑 Key Features

- **Strict Harvard Separation**  
  Instructions and data exist in physically separate memory spaces.  
  No possibility of executing data as code.

- **MMU + MPU (Dual-Layer Protection)**  
  - MMU: Enforces per-process isolation, virtual memory, W^X, and ASLR.  
  - MPU: Global physical region protections (e.g., RAM is non-executable forever).  

- **Immutable & Verifiable Boot**  
  OS core stored in ROM/EEPROM, verified at startup.  
  Secure A/B updates supported.

- **Exploit Mitigations by Design**  
  - **W^X everywhere**  
  - **ASLR**  
  - **Stack canaries**  
  - **Guard pages**  
  - **No speculative execution attacks**

- **Microkernel OS Architecture**  
  - Only scheduling, IPC, VM, and traps in kernel mode.  
  - Drivers, filesystems, and services run in user space with *capabilities*.  

- **Deterministic Performance**  
  - In-order pipeline, bounded latencies, no speculation.  
  - Suitable for embedded + server workloads.

- **Formal Verifiability**  
  ISA, CSRs, and MMU/MPU invariants expressed in formal semantics.  
  Enables proof-carrying code and model checking.

---

## 📜 Whitepaper

A full technical whitepaper (~100 pages) is available in the repo under  
[`docs/HarvOS_Whitepaper.pdf`](docs/HarvOS_Whitepaper.pdf).  

It includes:
- Instruction semantics with pseudocode
- CSR bitfield tables
- Formal MMU/MPU invariants
- Example security policies
- FPGA prototyping path
- Comparison vs. x86 / ARM / RISC-V / AVR

---

## 🛠 Project Roadmap

1. **ISA & Toolchain**  
   - Define the instruction set  
   - LLVM backend & assembler  
   - Emulator implementation  

2. **OS Core (HarvOS Kernel)**  
   - Microkernel with VM, IPC, scheduling  
   - Capability-based policy system  

3. **FPGA Prototype**  
   - RTL core implementation  
   - SMP scaling tests  
   - Hardware/OS co-design validation  

4. **ASIC Exploration**  
   - MPW shuttle tape-out (130 nm / 28 nm)  
   - Secure supply chain considerations  

---

## 📊 Use Cases

- **Secure Microservers**  
  Run DNS, HTTP, or TLS endpoints with minimal attack surface.  

- **Industrial / IoT Gateways**  
  Deterministic, tamper-resistant edge nodes.  

- **Research & Education**  
  Platform for studying secure processor & OS co-design.  

---

## 🤝 Contributing

HarvOS is at a **research/vision stage**. Contributions are welcome in:

- ISA / compiler backend design  
- Formal verification (Coq, Isabelle/HOL, etc.)  
- Emulator or FPGA prototype  
- OS microkernel & user-space services  

---

## ⚠️ Disclaimer

This is an experimental project and not production-ready.  
It is intended for research, prototyping, and exploration of secure system design.  

---

## 📧 Contact

Feel free to open an **issue** or **discussion** in the repository to collaborate.  


## Chat-bedingte Änderungen (August 2025)

Folgende Dateien wurden in diesem Chat geändert:

- **mpu.sv**  
  - Lock-Bit (`lock_q`) implementiert, verhindert weitere Programmierung nach Setzen.

- **mmu_sv32.sv**  
  - Neue Eingabe `csr_sstatus_q` (für MXR/SUM).  
  - MXR (`sstatus[19]`): erlaubt Loads von X-Pages als Reads.  
  - SUM (`sstatus[18]`): erlaubt S-Mode Zugriff auf U-Pages.  
  - Assertions für W^X-Invarianten ergänzt.

- **icache.sv**  
  - Annotiert als „execute-only“.  
  - Hook für HARVOS_ASSERT eingefügt (prüft, dass `mem_we=0`).

- **ptw_sv32.sv**  
  - PTW vervollständigt (Sv32 Zwei-Level-Walk).  
  - Superpages (L1-Leafs) unterstützt.  
  - A/D-Enforcement: Fault, wenn `A=0` oder (`D=0` bei Store).  
  - Assertions für „W → R“ ergänzt.

- **csr_file.sv**  
  - Schreibmaske für SSTATUS erweitert (SUM/MXR Bits).

- **tb_mmu_wx_neg.sv**  
  - Angepasst auf neuen Port `csr_sstatus_q` (derzeit fix auf `0`).

- **TODO_HarvOS_BringUp.md**  
  - Aktualisiert: MPU Lock ✔, PTW fertig ✔, MXR/SUM ✔, A/D ✔.

---

- **dcache_2way.sv**: 2‑Way Set-Associative D‑Cache vervollständigt (LRU, 4‑Word Lines, Write‑Through/Allocate, Early‑Restart für Loads).



### Harvard/Trap SVA Bindfile

Neue Dateien:
- `src/rtl/harvos_sva_bind.sv`: Assertions-Modul
- `src/rtl/bind_harvos_core.sv`: Bind-Anweisung für `harvos_core`

**Verwendung (Simulation/Formal):**
1. Beide Dateien in den Compile aufnehmen.
2. Optional Makros setzen, um Trap-Signale zu verbinden (Beispiele im Header von `bind_harvos_core.sv`):
   ```sv
   `define HARVOS_TRAP_TAKEN  (trap_taken)
   `define HARVOS_PC_Q        (if_pc_q)
   `define HARVOS_NEXT_PC     (if_next_pc)
   `define HARVOS_STVEC_Q     (u_csr.stvec_q)
   `define HARVOS_SEPC_Q      (u_csr.sepc_q)
   ```
3. Alternativ ohne Makros bauen → Trap-Checks sind dann inaktiv, Harvard-Checks trotzdem aktiv.

**Was geprüft wird:**
- **Harvard**: Kein DMEM-Write ohne Request; keine simultanen IMEM-Rückgaben + DMEM-Write-Returns (sanity).
- **Trap (optional)**: Vektorisierung zu `stvec`, `sepc` fängt faulting `pc`.

Aktivierung zusätzlicher Assertions im RTL:
- Baue mit `+define+HARVOS_ASSERT` um die lokalen Invarianten im MMU/I$/Trap-Unit zu aktivieren.


- **MMU/TLB:** ASID (Sv32 `satp[30:22]`) ausgewertet; `sfence`-Ports an MMU hinzugefügt und bis in TLB verdrahtet (Flush all/addr/asid). TLB vergleicht ASID außer bei Global-Pages (`G=1`).

- **SFENCE.VMA:** neues Modul `sfence_vma_decode.sv` (Decoder-Pfad). Liefert `sfence_*`-Pulse (flush_all / addr / asid). In `mmu_sv32.sv` wird zusätzlich **auto-flush bei `satp`-Änderung** ausgelöst.

- **harvos_core**: exportiert jetzt `sfence_*`-Signale (flush_all/addr/asid). Im Core verdrahtet: `sfence_vma_decode.sv` treibt die `sfence_*`-Signale in Richtung MMU/TLB.

- **I-Cache:** `icache.sv` jetzt implementiert (direct-mapped, 4-Word Lines, Burst-Refill, Early-Restart for Fetch).
- **MPU-Tests:** neue TBs `tb_mpu_nx_ram.sv` (NX-RAM Fetch-Fault) und `tb_mpu_umode_mmio.sv` (U→MMIO Store-Fault).

- **FENCE.I**: `fence_i_decode.sv` im Core verdrahtet → treibt `icache_flush_all`; I$ (`icache.sv`) hat `flush_all_i` und invalidiert alle Lines.

### Minimal SoC-Top
- `src/rtl/harvos_imem_if.sv`, `src/rtl/harvos_dmem_if.sv`: einfache Harvard-Interfaces für Core↔Caches.
- `src/rtl/harvos_soc.sv`: minimaler Top (Core ↔ I$/D$ ↔ Arbiter ↔ `simple_ram`), `icache_flush_all` ist angebunden.
- `src/rtl/mem_arbiter2.sv`: 2‑Master Arbiter (D$ > I$).
- `src/rtl/simple_ram.sv`: 64 KiB Single-Port RAM (1‑Cycle Latenz, Byte-Enables).
