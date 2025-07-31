# MIPS32 5-Stage Pipelined Processor

This project implements a **MIPS32 architecture-based 5-stage pipelined processor** in Verilog. The design models the key features of instruction pipelining, hazard detection, and basic control flow. It includes support for arithmetic operations, memory access, and branching.

---

## 🔧 Features

- **5 Pipeline Stages:**
  - IF (Instruction Fetch)
  - ID (Instruction Decode)
  - EX (Execute)
  - MEM (Memory Access)
  - WB (Write Back)

- **Instruction Types:**
  - **RR-ALU (Register-Register ALU):** `ADD`, `SUB`, `AND`, `OR`, `SLT`, `MUL`
  - **RM-ALU (Register-Immediate ALU):** `ADDI`, `SUBI`, `SLTI`
  - **Load/Store:** `LW`, `SW`
  - **Branch:** `BEQZ`, `BNEQZ`
  - **Jump/Link:** `J`, `JAL`, `JR`
  - **Control:** `HLT`

- **Hazard Detection Logic:**
  - Detects RAW (Read After Write) hazards and stalls pipeline (bubble insertion).

- **Memory:**
  - 1024 x 32-bit Instruction Memory
  - 1024 x 32-bit Data Memory

- **Register File:**
  - 32 general-purpose registers (`R0` to `R31`), with `$zero = R0 = 0`

---

## 📁 File Structure

