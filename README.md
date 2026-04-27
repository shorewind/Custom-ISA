# Custom-ISA

Custom 16-bit RISC-style instruction set architecture and Verilog CPU
implementation for a small unified-memory processor.

The design targets a simple teaching-scale machine:

- 16-bit instructions and 16-bit data path
- 8 programmer-visible registers
- 16 total instructions
- 1024-word unified memory
- Single-cycle style datapath with separate control and datapath modules

The repository includes synthesizable RTL, simulation testbenches, and a full
technical report describing the ISA, encoding, implementation, and results.

## Architecture Summary

The processor uses three instruction formats:

- `R-type`: register-register ALU ops plus short-immediate ALU ops
- `LS-type`: base+offset load/store
- `IJ-type`: large immediate, branch, and jump operations

Register set:

- `r0` / `$zero`: hardwired zero
- `r1`-`r6`: general-purpose registers
- `r7` / `$ra`: link register for subroutine return

Instruction set:

| Opcode / funct | Mnemonic | Description |
| --- | --- | --- |
| `000 / 000` | `ADD` | `rd <- rs + rt` |
| `000 / 001` | `SUB` | `rd <- rs - rt` |
| `000 / 010` | `AND` | `rd <- rs & rt` |
| `000 / 011` | `OR` | `rd <- rs \| rt` |
| `000 / 100` | `SLT` | `rd <- (rs < rt)` |
| `000 / 101` + `iflag=1` | `SLL` | `rd <- rs << imm3` |
| `000 / 110` + `iflag=1` | `SRL` | `rd <- rs >> imm3` |
| `000 / 000` + `iflag=1` | `ADDI` | `rd <- rs + imm3` |
| `001` | `ST` | `M[rs + imm7] <- rt` |
| `010` | `LD` | `rt <- M[rs + imm7]` |
| `011` | `LDI` | `rd <- imm10` |
| `100` | `BEZ` | branch if register is zero |
| `101` | `BNZ` | branch if register is non-zero |
| `110` | `JL` | jump and link |
| `111` | `JR` | jump to register |
| `000 / 111` | `HALT` | stop execution |

## Repository Layout

```text
.
├── README.md
├── Report/
│   ├── Custom ISA Technical Report.pdf
│   └── main.tex
├── Synthesis/
│   ├── cpu.v
│   ├── control_unit.v
│   ├── unified_mem.v
│   ├── isa.v
│   └── ...
└── Testbench/
    ├── cpu_tb.v
    ├── cpu_flow_tb.v
    └── ...
```

Key files:

- `Synthesis/cpu.v`: top-level CPU datapath and control integration
- `Synthesis/control_unit.v`: opcode/funct decode and control signals
- `Synthesis/unified_mem.v`: 1024-word unified instruction/data memory
- `Synthesis/isa.v`: FPGA wrapper for the CPU
- `Testbench/cpu_tb.v`: instruction-by-instruction execution test
- `Testbench/cpu_flow_tb.v`: control-flow-oriented program test
- `Report/main.tex`: full written design report

## Simulation

The repository does not include a build script, but the testbench directory is
set up to compile directly with a Verilog simulator.

Example with Icarus Verilog:

```sh
iverilog -g2012 -o tb_cpu.out Testbench/*.v -s tb_cpu
vvp tb_cpu.out
```

```sh
iverilog -g2012 -o tb_cpu_flow.out Testbench/*.v -s tb_cpu_flow
vvp tb_cpu_flow.out
```

What the included testbenches cover:

- `tb_cpu`: arithmetic, logic, shifts, memory, branches, jump-and-link, return
- `tb_cpu_flow`: if/else, while loop, for loop, and function call/return flow

Note: simulator binaries are not installed in this workspace, so the example
commands above were documented from the source layout but not executed here.

## FPGA Synthesis

The Quartus project files in `Synthesis/` target:

- Intel Quartus Prime Lite 22.1
- `Cyclone IV E`
- Device `EP4CE115F29C7`

The top-level FPGA module is `Synthesis/isa.v`. It divides the `CLOCK_50`
input down to a slower CPU clock and drives `LEDG8` as a visible heartbeat.

## Design Notes

- Memory is unified: instructions and data share the same 1024-word array.
- Register `r0` is forced to zero on every clock edge.
- `JL` writes `PC + 1` into `r7`, and `JR` returns through a register target.
- Short immediates use the `iflag` bit in the `R-type` encoding.

## Report

For the full project documentation, see:

- [Technical report PDF](./Report/Custom%20ISA%20Technical%20Report.pdf)
- [LaTeX source](./Report/main.tex)

The report includes:

- ISA specification and encodings
- mapping from C constructs to the custom ISA
- RTL design discussion
- simulation output
- synthesis and hardware implementation results
