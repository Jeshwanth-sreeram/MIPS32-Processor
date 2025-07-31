# MIPS32 5-Stage Pipelined Processor

This project implements a **MIPS32 architecture-based 5-stage pipelined processor** in Verilog. The design models the key features of instruction pipelining, hazard detection, and basic control flow. It includes support for arithmetic operations, memory access, and branching.

---

##  Features

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

##  File Structure
```
mips32_pipeline/
├── mips32_pipeline.v   # Main processor module
├── testbench.v         # Optional testbench for simulation
├── program.mem         # Instruction memory content (hex format)
└── README.md           # This file
```

---

##  How to Simulate

### Using Icarus Verilog + GTKWave:

```sh
iverilog -o mips_sim mips32_pipeline.v testbench.v
vvp mips_sim
gtkwave dump.vcd
```

> Make sure `testbench.v` includes:
> ```verilog
> $readmemh("program.mem", mips32_pipeline.InstrMem);
> ```

---

##  Sample Program

Here’s a simple sample program in assembly:

```assembly
ADDI R1, R0, 5     ; R1 = 5
ADDI R2, R0, 10    ; R2 = 10
ADD  R3, R1, R2    ; R3 = R1 + R2
SW   R3, 0(R0)     ; Store R3 at memory[0]
HLT                ; Halt processor
```

### Corresponding machine code (in `program.mem`):
```text
0x28_00_01_0005
0x28_00_02_000A
0x00_01_02_03_00
0x29_00_03_0000
0x3F_00_00_0000
```

---

##  Educational Concepts Covered

- Instruction pipelining
- Data hazards and RAW detection
- Control flow hazards
- Instruction decoding
- Register file and memory access
- Jump and branch handling

---

## ⚠ Notes

- `$zero` (`R0`) is hardwired to zero.
- `HLT` instruction halts the processor by setting the `HALTED` flag.
- Branches and jumps flush the next instruction in the pipeline.
- RAW hazards are handled with stalls — no forwarding logic is implemented.

