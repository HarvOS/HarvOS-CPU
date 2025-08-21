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
HarvOS has been created using ChatGPT 5
---

## 📧 Contact

Feel free to open an **issue** or **discussion** in the repository to collaborate.  
