# Contributing to HarvOS

Thank you for your interest in **HarvOS** — a secure Harvard-architecture OS and CPU design project.  
This is an **early-stage research effort**, so contributions are highly welcome in many areas.

---

## 🛠 Areas You Can Contribute

- **Instruction Set Architecture (ISA)**
  - Define/refine instructions
  - Write pseudocode semantics

- **Compiler & Toolchain**
  - LLVM backend or assembler/linker
  - Verified compilation (CompCert, Coq, etc.)

- **Operating System (HarvOS Kernel)**
  - Microkernel services (IPC, scheduling, VM)
  - Capability-based policy engine
  - User-space drivers (network, storage, crypto)

- **Emulator & FPGA**
  - Develop emulators
  - HDL/FPGA prototypes

- **Formal Verification**
  - Prove MMU/MPU invariants
  - Model-check scheduling & isolation

- **Documentation**
  - Improve the whitepaper
  - Write tutorials

---

## 🚀 Getting Started

1. Fork the repo  
2. Create a branch:  
   ```bash
   git checkout -b feature/my-contribution
   ```
3. Commit your changes:  
   ```bash
   git commit -m "Add: new instruction semantics"
   ```
4. Push:  
   ```bash
   git push origin feature/my-contribution
   ```
5. Open a Pull Request  

---

## ✅ Guidelines

- Keep PRs **modular** (one feature per PR)  
- Include **tests/docs** where relevant  
- Document architectural decisions  
- Be respectful & collaborative  

---

## 📜 Code of Conduct

We follow the [Contributor Covenant](https://www.contributor-covenant.org/).  
