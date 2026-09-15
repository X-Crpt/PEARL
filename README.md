# PEARL — PRNG Evaluation for Area, Randomness, and Leakage

PEARL is a repeatable evaluation framework for hardware-oriented pseudo-random number
generators (PRNGs). It collects a set of PRNG architectures, each with RTL sources, a C++
golden model, a SystemVerilog testbench and project filelists, and drives them all through the
same command-line workflows: functional simulation against the golden model, NIST SP 800-22
statistical validation, ASIC synthesis, FPGA synthesis, and cross-architecture comparison plots.

**Bringing your own PRNG hardware?** The framework's automation does not assume the internals of
any specific generator — see [Evaluating Your Own PRNG (Bring Your Own Hardware)](#evaluating-your-own-prng-bring-your-own-hardware)
for how to plug your own RTL into the same simulation/NIST/synthesis/comparison flow used by the
architectures already in this repository.

This file is the only documentation you should need, from first clone to extending the
repository; there is no separate developer guide or per-script README.

## Table of Contents

- [What's Included](#whats-included)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Evaluating an Existing Architecture](#evaluating-an-existing-architecture)
- [Evaluating Your Own PRNG (Bring Your Own Hardware)](#evaluating-your-own-prng-bring-your-own-hardware)
- [Script Reference](#script-reference)
- [Local Synthesis](#local-synthesis)
- [Repository Layout and Outputs](#repository-layout-and-outputs)
- [Repository Internals](#repository-internals)
- [Citing PEARL](#citing-pearl)
- [Acknowledgments](#acknowledgments)

## What's Included

### Implemented PRNG Architectures

| PRNG | Implementation reference |
|---|---|
| `ctr_drbg` | NIST SP 800-90A CTR-DRBG (AES-based core is standards-compliant; the Keccak-based core reuses the same control structure as an architectural comparison point, and is **not** claimed to be SP 800-90A-compliant) |
| `DP` | Inspired by Dziembowski and Pietrzak, "Leakage-Resilient Cryptography"; this implementation retains the alternating-extraction refresh mechanism but not the original construction's separate next-state/output key split, so it does not carry the same forward-security guarantee as the original paper — referred to as **DP-AE** in the accompanying paper for this reason |
| `MersenneTwister` | Matsumoto and Nishimura, "Mersenne Twister" |

These architectures are the top-level generators targeted by the generic simulation, NIST
validation and synthesis workflows. Additional PRNGs can be added by following
[Evaluating Your Own PRNG](#evaluating-your-own-prng-bring-your-own-hardware) below.

### Supporting Cryptographic Primitives

Cryptographic primitives are reusable blocks used to build more complex PRNG architectures. In
this repository, the selectable primitive cores are cryptographic transforms with an `n`-bit
input and an `n`-bit output. AES and Keccak come from different cryptographic families, but they
can both be wrapped behind this transform interface.

Only primitives compatible with this interface should share the same selector. If a future
primitive has a different black-box interface, it should use a separate selector and wrapper
instead of being added to this list directly.

| Primitive | Implementation reference |
|---|---|
| `AES_128` | NIST FIPS 197, Advanced Encryption Standard |
| `Keccak` | See the Keccak source package and notes in [keccak/README.md](keccak/README.md) |

## Requirements

The local machine is used to run setup, simulation, NIST validation, plotting and the client
side of the synthesis scripts. It should provide:

- Bash;
- Make;
- `g++`;
- Verilator (5.x — the testbenches use `--timing`);
- Python 3, with `matplotlib` and `numpy` for plots;
- `jq`;
- `ssh` and `rsync`, only when *remote* synthesis is used (see [Local Synthesis](#local-synthesis)
  if you have Design Compiler/Vivado installed locally instead).

Additional project dependencies, including libraries used by the C++ golden models and
Python/Bash helper scripts, are handled by [setup.sh](setup.sh) where possible. Open the script
for the exact list of checks and installation commands.

ASIC and FPGA synthesis are executed on a configured remote synthesis server by default. The
server (or your local machine, see [Local Synthesis](#local-synthesis)) must provide:

- Synopsys Design Compiler for ASIC synthesis;
- Xilinx Vivado for FPGA synthesis.

### Troubleshooting Setup on Shared/HPC Machines

`setup.sh` tries `apt-get`, `dnf` or `yum`, in that order, and falls back to printing manual
instructions if none of them are usable with passwordless `sudo` (common on shared research
servers). A few things you may still need to handle by hand:

- **Verilator**: if it is not on your `PATH`, check whether your cluster already has one (e.g.
  under `/software/`, via `module avail`, or an `init_verilator`-style script) before building
  your own; Verilator 5.x is required (`--timing` support).
- **Crypto++** (`libcryptopp`, required by the C++ golden models): if no package manager/`sudo`
  combination is available, install it into a local [conda](https://docs.conda.io) environment
  instead (`conda create -n prng-cryptopp -c conda-forge cryptopp`) and point the compiler at it
  with `CPATH`/`LIBRARY_PATH`/`LD_LIBRARY_PATH`. If your system compiler is old (e.g. GCC 8), a
  conda-forge Crypto++ build may need a newer compiler to link against (a libstdc++ ABI mismatch
  shows up as `undefined reference to std::__throw_bad_array_new_length()`); switching to a newer
  GCC (e.g. via `scl_source enable gcc-toolset-12` on RHEL, or a conda-provided compiler)
  resolves it.
- **Submodules**: if `git submodule update --init --recursive` fails partway, `setup.sh` still
  initializes the remaining ones individually; you can also do this yourself with
  `git submodule update --init <path>`.

## Quick Start

After cloning the repository (`git clone --recurse-submodules ...`, or `git submodule update
--init --recursive` afterwards), run the setup script from the repository root:

```bash
./setup.sh
```

After setup, the simplest way to use the repository as it is currently configured is to launch
the target list:

```bash
./scripts/run_targets.sh
```

This command runs the configured workflows for all modules and variants listed in
[scripts/config/targets.json](scripts/config/targets.json). It generates the per-workflow
outputs and, when the required data is available, the comparison plots for NIST and synthesis
results.

The individual workflow scripts can also be launched manually when developing, debugging or
evaluating one PRNG architecture at a time. For example, using `DP` as the target PRNG:

```bash
./scripts/run_SIM.sh -module DP                # functional simulation vs. the golden model
./scripts/run_NISTTest.sh -module DP           # NIST SP 800-22 statistical validation
./scripts/run_SYNTH_ASIC.sh -module DP         # ASIC synthesis (remote server)
./scripts/run_SYNTH_FPGA.sh -module DP         # FPGA synthesis (remote server)
```

Full command-line options, parameters and output folders for every script are documented in
[Script Reference](#script-reference) below.

## Evaluating an Existing Architecture

### Common Command-Line Concepts

Every single-target workflow script (`run_SIM.sh`, `run_NISTTest.sh`, `run_SYNTH_ASIC.sh`,
`run_SYNTH_FPGA.sh`, and their `_LOCAL` variants) runs one selected PRNG architecture at a time,
using the same three concepts:

| Concept | Command-line form | Meaning |
|---|---|---|
| Module | `-module <name>` | Selects the PRNG architecture to run, such as `DP` or `ctr_drbg`. |
| Variant | `-variant <name>` | Names one configuration of a module and keeps its generated results in a separate output folder. Defaults to `default`. |
| Parameter override | `-param NAME=VALUE` | Assigns the PRNG parameter `NAME` to `VALUE`. Forwarded as `+NAME=VALUE` to the C++ golden model, `-GNAME=VALUE` to Verilator, and to the synthesis scripts. Can be repeated. |

When no `-param` option is used, every exposed PRNG parameter keeps its default value and the
scripts automatically use the `default` variant. When at least one `-param` override is used, an
explicit `-variant <name>` is required, so that results from different configurations are never
written to the same output folder.

The currently implemented modules are:

| Module name | Typical use |
|---|---|
| `ctr_drbg` | CTR-DRBG simulation, NIST tests and synthesis. |
| `DP` | DP-AE (Dziembowski-Pietrzak-inspired alternating-extraction) generator simulation, NIST tests and synthesis. |
| `MersenneTwister` | Mersenne Twister simulation, NIST tests and synthesis. |

Each PRNG architecture can expose design parameters that directly impact its internal circuitry
— sizes, initialization values, or the selected internal cryptographic primitive. Changing the
primitive core, for example from Keccak to AES, can change both the cryptographic behavior and
the hardware cost of the PRNG under analysis.

For example, this command runs the simulation of the `ctr_drbg` architecture with the internal
primitive core set to Keccak, storing results in `sim/ctr_drbg/KECCAK_CORE/`:

```bash
./scripts/run_SIM.sh -module ctr_drbg -variant KECCAK_CORE -param ENCRYPTION_CORE=0
```

The numeric values used for primitive-core parameters are shared between RTL and golden models
through `rtl/PRNG_common/primitive_pkg.sv` and `golden_model/Common/PrimitiveCore.hpp`.

### Workflows and Comparison Automation

The base workflow scripts are intended for developing, debugging or evaluating one architecture
at a time: `run_SIM.sh`, `run_NISTTest.sh`, `run_SYNTH_ASIC.sh` (or `_LOCAL`), `run_SYNTH_FPGA.sh`
(or `_LOCAL`).

For comparison experiments, `run_targets.sh` runs those same workflows over every module/variant
listed in [scripts/config/targets.json](scripts/config/targets.json), so different architectures
and configurations are evaluated under identical conditions and become directly comparable. When
comparison data is available, it also generates summary plots (NIST results, synthesis Pareto
plots).

The default target list contains:

| Module | Variant | Parameters |
|---|---|---|
| `ctr_drbg` | `KECCAK_CORE` | `ENCRYPTION_CORE=0` |
| `ctr_drbg` | `AES_CORE` | `ENCRYPTION_CORE=1` |
| `DP` | `KECCAK_EXT_KECCAK_PRG` | `EXTRACTOR_CORE=0`, `PRG_CORE=0` |
| `DP` | `KECCAK_EXT_AES_PRG` | `EXTRACTOR_CORE=0`, `PRG_CORE=1` |
| `DP` | `AES_EXT_KECCAK_PRG` | `EXTRACTOR_CORE=1`, `PRG_CORE=0` |
| `DP` | `AES_EXT_AES_PRG` | `EXTRACTOR_CORE=1`, `PRG_CORE=1` |
| `MersenneTwister` | `default` | none |

A target entry in `targets.json` looks like:

```json
{
  "modules": {
    "MyPRNG": {
      "variants": {
        "default": {
          "params": {}
        }
      }
    }
  }
}
```

`modules` lists the PRNG architectures included in the batch flow (keys must match the module
name used by the workflow scripts); `variants` are named configurations, each stored in its own
output folder; `params` are the parameter overrides for that variant (empty means all defaults).
Add a new module/variant here once its configuration is stable and should be compared regularly;
for early development, use the single-target scripts directly.

### Outputs

Each workflow writes results under a module and variant folder:

| Workflow | Output folder |
|---|---|
| Simulation | `sim/<module>/<variant>/` |
| NIST tests | `NIST_test/<module>/<variant>/` |
| ASIC synthesis | `synth/<module>/<variant>/ASIC/` |
| FPGA synthesis | `synth/<module>/<variant>/FPGA/` |

`run_targets.sh` additionally writes comparison plots to `NIST_test/plots/` and `synth/plots/`.
See [Script Reference](#script-reference) for the exact contents of each folder.

## Evaluating Your Own PRNG (Bring Your Own Hardware)

The framework's automation (build, simulate, validate, synthesize, compare) is generic: it does
not assume the internals of any specific generator. To evaluate your own PRNG hardware with it,
you supply a handful of files for a canonical name `<module>` of your choosing, and the existing
scripts do the rest.

### What "common interface" actually means here

There is no single rigid port list every DUT must implement, and no shared generic testbench
that auto-adapts to arbitrary ports — `MersenneTwister`, `ctr_drbg` and `DP` each have their own
`TB_<module>.sv` written against their own DUT's ports. Compare
[`rtl/mersenne_twister/MersenneTwister.sv`](rtl/mersenne_twister/MersenneTwister.sv) and
[`rtl/ctr_drbg/ctr_drbg.sv`](rtl/ctr_drbg/ctr_drbg.sv) and you will see, for example,
`request_RandomNumber`/`RandomNumber`/`nRST` on one and `request_RN_i`/`output_RN_o`/`rst_n_i` on
the other — real signal names differ between architectures already in this repository. Your RTL's
ports do not need to match any of them.

What IS consistent across all three, and is a genuinely useful handshake style to follow for your
own RTL (it is what every existing testbench, and `tb_performance_monitor.sv`, is written
against):

| Role | Example name used in this repo | Direction | Meaning |
|---|---|---|---|
| Request | `request_RandomNumber` / `request_RN_i` | In | Ask the generator to produce the next output. |
| Ready | `ready_o` | Out | The generator can accept a new request. |
| Busy | `busy_o` | Out | An internal operation is in progress. |
| Valid | `valid_o` | Out | The output data is valid this cycle. |
| Data out | `RandomNumber` / `output_RN_o` | Out | The generated random word. |

What the framework DOES enforce, because the automation scripts depend on it directly, is:

- the same `<module>` name used consistently for the RTL folder, testbench top module
  (`TB_<module>`), golden-model folder, Makefile and project filelists;
- a C++ golden model with two specific command-line entry points (`main_SIM.cpp`, `main_NIST.cpp`);
- `-param NAME=VALUE` overrides forwarded identically to the golden model, Verilator and
  synthesis, so parameter names must match between your RTL and your golden model.

### Step by Step

1. **Pick a canonical module name**, `<module>` (e.g. `MyPRNG`). Use it everywhere below.

2. **Add your RTL** under `rtl/<module>/`. Internal port names/widths are entirely up to you —
   there is no required top-level interface beyond what your own testbench needs to drive.

3. **Write a C++ golden model** describing your generator's expected output, so the framework has
   something to check your RTL against and to feed the NIST suite:

   - `golden_model/<module>/main_SIM.cpp` — usage
     `<num_patterns> <input_vector_file> <output_vector_file> [+PARAM=VALUE ...]`; generates input
     vectors and the matching expected outputs.
   - `golden_model/<module>/main_NIST.cpp` — usage
     `<num_bits_requested> <output_bitstream_file> [+PARAM=VALUE ...]`; generates a single long
     bitstream from **one** seed for NIST characterization. See the warning below.
   - `golden_model/<module>/Makefile`, building either entry point. All modules share
     [`golden_model/common.mk`](golden_model/common.mk) for the actual compiler flags and
     target-building logic, so your per-module Makefile only needs to declare `MODULE_NAME`,
     `MAIN` (optional, defaults to `main.cpp`) and `SRC` (your module's own sources plus whichever
     `Common/*` files it needs), then `include ../common.mk` — copy an existing one (e.g.
     [`golden_model/MersenneTwister/Makefile`](golden_model/MersenneTwister/Makefile)) and adjust
     `SRC`.
   - Use [`ParameterParser.hpp`](golden_model/Common/ParameterParser.hpp) to parse `+PARAM=VALUE`
     overrides and [`bytesNumber.hpp`](golden_model/Common/bytesNumber.hpp) for values wider than
     a native C++ integer, instead of writing your own parser.
   - Implement your generator's actual behavior as a standalone class derived from
     [`PRNG.hpp`](golden_model/Common/PRNG.hpp) — and, if it uses an internal cryptographic
     primitive, that primitive as a class derived from
     [`BlockFunction.hpp`](golden_model/Common/BlockFunction.hpp) — rather than inline in the two
     `main_*` files. See [`MersenneTwister.hpp`](golden_model/MersenneTwister/MersenneTwister.hpp)
     or [`DP.hpp`](golden_model/DP/DP.hpp) for a concrete example to copy from.

   > **A specific, real mistake to avoid**: if `main_NIST.cpp` periodically reseeds the generator
   > from fresh entropy while producing the characterization bitstream (e.g. to model
   > deployment-time forward secrecy), you may get healthy-looking results at small sample sizes
   > and then have **every** NIST test fail its p-value-uniformity check at the full 100-stream
   > scale. NIST SP 800-22 assumes one long deterministic sequence from a single seed: reseed only
   > once, at the start of `main_NIST.cpp`. (A generator specifically designed to tolerate frequent
   > reseeding, like `DP`, is a deliberate exception — if in doubt, check pass rates at the full
   > 100-stream scale before trusting a smaller smoke test.)

4. **Write a SystemVerilog testbench** under `tb/<module>/`:

   - Top module named `TB_<module>`, exposing every parameter your RTL exposes.
   - A driver (conventionally `data_maker.sv`) that reads `inputVect.txt` and applies it to your
     DUT according to your own handshake.
   - A checker (conventionally `data_sink.sv`) that reads `outputVect_gold.txt`, samples your
     DUT's outputs, compares them against the golden model, and reports a final PASS/FAIL — this
     decision is entirely up to your testbench; the scripts only run Verilator and show you the
     result.
   - Read file paths from plusargs (`+INPUT_VECT_FILE=`, `+GOLD_VECT_FILE=`, `+VCD_FILE=`), not
     hard-coded strings, so the same testbench works across variants.
   - Instantiate [`tb/general/tb_performance_monitor.sv`](tb/general/tb_performance_monitor.sv),
     connected to your DUT's clock and valid-output signal, to get cycles-per-generation and
     bits-per-cycle numbers for free — see
     [`tb/MersenneTwister/TB_MersenneTwister.sv`](tb/MersenneTwister/TB_MersenneTwister.sv) for a
     working example.
   - [`tb/DP/`](tb/DP) is a good template to copy from for the full driver/checker structure.

5. **Add project filelists** under `prj/`:

   - `prj/<module>_SIM.prj` — every SystemVerilog file needed for simulation (RTL + testbench).
   - `prj/<module>_SYNTH_ASIC.prj` — only synthesizable RTL, no testbench files.
   - `prj/<module>_SYNTH_FPGA.prj` — the same synthesizable files, plus the FPGA wrapper (next
     step).

6. **(Optional, for FPGA synthesis) add a wrapper**, named exactly
   `rtl/<module>/xilinx_<module>_wrapper.sv` — this is the top module the FPGA flow expects.

7. **Run it**:

   ```bash
   ./scripts/run_SIM.sh -module MyPRNG
   ./scripts/run_NISTTest.sh -module MyPRNG
   ./scripts/run_SYNTH_ASIC_LOCAL.sh -module MyPRNG   # or run_SYNTH_ASIC.sh for the remote flow
   ./scripts/run_SYNTH_FPGA_LOCAL.sh -module MyPRNG   # or run_SYNTH_FPGA.sh for the remote flow
   ```

   Remember: if you override any parameter with `-param`, add `-variant <name>` too (see
   [Common Command-Line Concepts](#common-command-line-concepts)).

8. **(Optional) add it to the comparison flow**: add `MyPRNG` and any variants you care about to
   [`scripts/config/targets.json`](scripts/config/targets.json); `./scripts/run_targets.sh` then
   runs and compares it against the other architectures automatically, including the Pareto and
   NIST comparison plots.

### Reusing an Existing Cryptographic Primitive

If your PRNG is built around a selectable block-cipher-like primitive the same way `ctr_drbg` and
`DP` are, reuse the existing AES/Keccak primitive-core selector instead of inventing a new one:
[`rtl/PRNG_common/primitive_pkg.sv`](rtl/PRNG_common/primitive_pkg.sv) and
[`golden_model/Common/PrimitiveCore.hpp`](golden_model/Common/PrimitiveCore.hpp) define the
shared IDs (`0` = Keccak, `1` = AES) that both RTL and golden models must agree on. Only
primitives exposing the same stateless `n`-bit-in/`n`-bit-out interface belong in this selector; a
primitive with a different interface should get its own selector and wrapper instead. If you add
a new selectable primitive core, update both files, then update every golden model or RTL module
that validates allowed primitive core IDs.

## Script Reference

Run scripts from the repository root: `./scripts/<script_name>.sh <options>`.

| Script | Purpose |
|---|---|
| `run_SIM.sh` | Builds and runs the C++ golden model, generates input/reference vectors, builds the Verilator testbench and runs HDL simulation. |
| `run_NISTTest.sh` | Generates a bitstream with the C++ golden model, runs the NIST Statistical Test Suite and creates plots/summaries. |
| `run_SYNTH_ASIC.sh` | Sends source files to the remote synthesis server, runs ASIC synthesis and retrieves the results. |
| `run_SYNTH_ASIC_LOCAL.sh` | Same as `run_SYNTH_ASIC.sh`, but runs Design Compiler directly on this machine — no server, rsync or SSH. |
| `run_SYNTH_FPGA.sh` | Sends source files to the remote synthesis server, runs FPGA synthesis and retrieves the results. |
| `run_SYNTH_FPGA_LOCAL.sh` | Same as `run_SYNTH_FPGA.sh`, but runs Vivado directly on this machine — no server, rsync or SSH. |
| `run_targets.sh` | Runs selected workflows over every module/variant in a configurable target list, and generates comparison plots. |

The `utility_scripts/` folder contains helper scripts called by the main workflows (including
`summarize_NIST_results.py` and `plot_NIST_results.py`, described under `run_NISTTest.sh` below).
They are not documented in further detail here; advanced users can still run some of them
directly, but that usage is outside the standard workflow.

Synthesis workflow scripts used on the synthesis server (local or remote) live under
`scripts/synth/`. Generated synthesis outputs are written under `synth/`.

### `run_SIM.sh`

Runs the complete simulation workflow for one selected PRNG architecture: builds the C++ golden
model, runs it to generate input/expected-output vectors, builds the SystemVerilog testbench with
Verilator using `prj/<module>_SIM.prj`, runs the HDL simulation, and writes logs, vectors,
executables and the VCD waveform under `sim/<module>/<variant>/`. The pass/fail check itself is
performed inside the SystemVerilog testbench.

```bash
./scripts/run_SIM.sh -module <module> [-variant <variant>] [-param NAME=VALUE] [-num_patterns <N>]
```

| Option | Default | Description |
|---|---:|---|
| `-num_patterns <N>` | `10` | Number of input patterns generated by the golden model and passed to the HDL testbench. |

```bash
./scripts/run_SIM.sh -module ctr_drbg
./scripts/run_SIM.sh -module ctr_drbg -num_patterns 100 -variant KECCAK_CORE -param ENCRYPTION_CORE=0
```

Outputs, under `sim/<module>/<variant>/`:

```text
sim/<module>/<variant>/
├── logs/
│   ├── SIM_<module>.log          Complete script log
│   ├── goldenModel_<module>.log  Golden model C++ build log
│   ├── verilator_<module>.log    Verilator build log
│   └── <module>.vcd              VCD waveform generated by the HDL simulation
├── vectors/
│   ├── inputVect.txt             Input vectors generated by the C++ code
│   ├── outputVect_gold.txt       Expected outputs generated by the golden model
│   └── outputVect_hdl.txt        Output vectors generated by the HDL
├── build/                        Verilator build directory
└── executables/                  Golden model and simulation executables
```

### `run_NISTTest.sh`

Runs the NIST Statistical Test Suite on a bitstream generated by the C++ golden model: builds the
NIST golden model from `golden_model/<module>/main_NIST.cpp`, generates a bitstream with
`stream_length * stream_num` bits, generates the NIST STS configuration so the external suite runs
without manual interaction, builds/runs the suite, and creates summary plots and CSVs from the
final report.

```bash
./scripts/run_NISTTest.sh -module <module> [-variant <variant>] [-param NAME=VALUE] [-stream_length <N>] [-stream_num <N>]
```

| Option | Default | Description |
|---|---:|---|
| `-stream_length <N>` | `100000` | Number of bits in each NIST stream. |
| `-stream_num <N>` | `10` | Number of independent streams passed to the NIST suite. |

```bash
./scripts/run_NISTTest.sh -module ctr_drbg -variant AES_CORE -stream_length 100000 -stream_num 10 -param ENCRYPTION_CORE=1
```

The report's own guidance is that 100 streams gives the pass-rate/uniformity checks enough
statistical power to be meaningful (see the reseeding warning under [Evaluating Your Own
PRNG](#evaluating-your-own-prng-bring-your-own-hardware) for why sample size matters here).

Outputs, under `NIST_test/<module>/<variant>/`:

```text
NIST_test/<module>/<variant>/
├── nistInputBits.txt                Bitstream generated by the C++ golden model
├── NIST_test_config.txt             Configuration for the NIST STS
├── finalAnalysisReport.txt          Raw report from the external NIST suite
├── logs/
│   ├── goldenModel_<module>.log     Golden model C++ build log
│   ├── nist_build.log               NIST STS build log
│   ├── nist_run.log                 NIST STS execution log
│   └── nist_plot.log                Plot/summary generation log
├── executables/                     Golden model executable
└── plots/
    ├── total_pass_rate_by_test.png  Summary plot for pass rate by test
    ├── pass_rate_summary.csv        Per-test-type pass rate (numeric), incl. overall min--max
    ├── uniformity_summary.csv       CSV summary of the p-value uniformity checks
    └── uniformity_histograms/       Histograms for p-value uniformity checks
```

### `run_SYNTH_ASIC.sh` / `run_SYNTH_ASIC_LOCAL.sh`

Starts the ASIC synthesis workflow for one module. `run_SYNTH_ASIC.sh` reads local server
settings from `scripts/config/server.local.sh`, sends RTL/testbench/scripts/filelists and the
ASIC library links to the server, launches the remote Synopsys Design Compiler workflow, and
retrieves the results. `run_SYNTH_ASIC_LOCAL.sh` runs the identical synthesis logic
(`scripts/synth/ASIC/run_ASIC_synth_server.sh`) directly on this machine instead — see [Local
Synthesis](#local-synthesis).

By default, the ASIC library targeted is our own lab's reference PDK setup (a private submodule
wrapping a proprietary foundry library), which is **not included in this public repository** and
will not work outside the original lab. To synthesize against your own standard-cell library
instead, see [Bring Your Own ASIC Library](#bring-your-own-asic-library) — neither script needs a
code change for this, only a local config file.

```bash
./scripts/run_SYNTH_ASIC.sh -module <module> [-variant <variant>] [-param NAME=VALUE]
./scripts/run_SYNTH_ASIC_LOCAL.sh -module <module> [-variant <variant>] [-param NAME=VALUE]
```

```bash
./scripts/run_SYNTH_ASIC.sh -module DP -variant KECCAK_EXT_KECCAK_PRG -param EXTRACTOR_CORE=0 -param PRG_CORE=0
```

Outputs, under `synth/<module>/<variant>/ASIC/`:

```text
synth/<module>/<variant>/ASIC/
├── logs/
│   └── synth_log.log          Main synthesis log
├── reports/
│   ├── <module>_timing.rpt    Timing report
│   ├── <module>_area.rpt      Area report
│   └── summary.csv            Compact metrics consumed by Pareto plotting
└── netlist/
    ├── <module>.v             Synthesized netlist
    ├── <module>.sdc            Generated constraints
    └── <module>.sdf           Timing annotation file
```

### `run_SYNTH_FPGA.sh` / `run_SYNTH_FPGA_LOCAL.sh`

Starts the FPGA synthesis workflow for one module. `run_SYNTH_FPGA.sh` reads local server
settings from `scripts/config/server.local.sh`, sends RTL/testbench/scripts/filelists to the
server, launches the remote Vivado workflow, and retrieves the results.
`run_SYNTH_FPGA_LOCAL.sh` runs the identical synthesis logic directly on this machine instead —
see [Local Synthesis](#local-synthesis).

```bash
./scripts/run_SYNTH_FPGA.sh -module <module> [-variant <variant>] [-param NAME=VALUE]
./scripts/run_SYNTH_FPGA_LOCAL.sh -module <module> [-variant <variant>] [-param NAME=VALUE]
```

```bash
./scripts/run_SYNTH_FPGA.sh -module DP -variant KECCAK_EXT_AES_PRG -param EXTRACTOR_CORE=0 -param PRG_CORE=1
```

Outputs, under `synth/<module>/<variant>/FPGA/`:

```text
synth/<module>/<variant>/FPGA/
├── logs/
│   ├── synth_log.log             Main synthesis log
│   ├── vivado.jou                Vivado journal
│   └── vivado_stdout.log         Vivado terminal output
├── reports/
│   ├── <module>_timing.rpt       Timing report
│   ├── <module>_utilization.rpt  Resource utilization report
│   ├── <module>_power.rpt        Power report
│   └── summary.csv               Compact metrics consumed by Pareto plotting
└── netlist/
    ├── <module>.v                Synthesized netlist
    └── <module>.dcp              Vivado checkpoint
```

### `run_targets.sh`

Runs the configured target list from a JSON configuration file: loads the target list (default
[scripts/config/targets.json](scripts/config/targets.json), or another file via `-config`),
optionally filters by module/variant/workflow, launches the requested workflows for each
selected target, reports failed steps at the end, and generates comparison plots when the
required NIST or synthesis results are available.

```bash
./scripts/run_targets.sh [options]
```

| Option | Default | Description |
|---|---:|---|
| `-module <name>` | all modules in config | Run only one module from the target list. |
| `-variant <name>` | all variants of selected module | Run only one variant (requires `-module`). |
| `-flow <name>` | all workflows | Select a workflow; repeatable. Valid values: `sim`, `nist`, `synth_asic`, `synth_fpga`. |
| `-config <path>` | `scripts/config/targets.json` | Use a different JSON target list. |
| `-num_patterns <N>` | `10` | Passed to `run_SIM.sh`. |
| `-stream_length <N>` | `100000` | Passed to `run_NISTTest.sh`. |
| `-stream_num <N>` | `10` | Passed to `run_NISTTest.sh`. |
| `-keep_going` | disabled | Continue after a failed step and report failures at the end. |

```bash
./scripts/run_targets.sh
./scripts/run_targets.sh -module DP -variant AES_EXT_AES_PRG -flow sim
./scripts/run_targets.sh -module ctr_drbg -flow synth_fpga
```

In addition to each workflow's own outputs (above), `run_targets.sh` generates:

```text
NIST_test/plots/
└── NIST_comparison.png          Comparison plot generated from NIST reports

synth/plots/
├── pareto_asic.png              ASIC synthesis Pareto plot
└── pareto_fpga.png              FPGA synthesis Pareto plot
```

Synthesis Pareto plots are generated when the corresponding synthesis workflow is selected and
completes successfully; the NIST comparison plot is generated when NIST is selected for all
modules in the target list.

## Local Synthesis

`run_SYNTH_ASIC.sh` and `run_SYNTH_FPGA.sh` are built around a remote server reachable over
`rsync`/`ssh` (see [Requirements](#requirements)). If Design Compiler and/or Vivado are already
installed on the machine you are running the scripts from, use the local variants instead, which
run the exact same synthesis logic without any network round-trip — see [Script
Reference](#run_synth_asicsh-run_synth_asic_localsh) for their full options/outputs:

```bash
./scripts/run_SYNTH_ASIC_LOCAL.sh -module MersenneTwister
./scripts/run_SYNTH_FPGA_LOCAL.sh -module MersenneTwister
```

`run_SYNTH_FPGA_LOCAL.sh` looks for Vivado at `/path/to/xilinx/Vivado/2024.2/settings64.sh` by
default; override `VIVADO_LOCAL_SETTINGS` to point at your own install.

Note: the reported numbers for FPGA synthesis, in particular, can be sensitive to the exact tool
version (e.g. carry-chain/comparator inference differs measurably between Vivado releases), so
record which Vivado/Design Compiler version you used alongside any numbers you publish or
compare.

### Bring Your Own ASIC Library

By default, ASIC synthesis (both `run_SYNTH_ASIC.sh` and `run_SYNTH_ASIC_LOCAL.sh`) targets our
own lab's reference PDK setup (a private submodule wrapping a proprietary foundry library) that
is **not included in this public repository** — it needs both access to a private repository and
a license for that specific PDK, so it is not something an external user or reviewer can run
as-is.

To synthesize against your own standard-cell/pad/memory library instead:

```bash
cp scripts/config/asic_lib.example.sh scripts/config/asic_lib.local.sh
# edit scripts/config/asic_lib.local.sh: point LIB_SYNTH_ASIC_CELLS/PADS/MEMORIES
# at your own library directories (see the comments in that file)
./scripts/run_SYNTH_ASIC_LOCAL.sh -module MersenneTwister
```

`scripts/config/asic_lib.local.sh` is git-ignored, so your paths and any license details never
get committed. No other change is needed: every script in the ASIC flow reads the library
location from the `LIB_SYNTH_ASIC_*` environment variables set there, falling back to our lab's
private default only for variables you leave unset. This also works with open PDKs (e.g.
Nangate45 or SkyWater sky130, both usable with Design Compiler) — see the comments in
`scripts/config/asic_lib.example.sh` for the corner/view glob patterns you are likely to need to
adjust.

## Repository Layout and Outputs

```text
.
Source Code
├── rtl/                         SystemVerilog RTL implementations of PRNGs
├── tb/                          SystemVerilog testbenches for PRNGs (tb/general/ holds shared units)
├── golden_model/                C++ golden models
├── prj/                         HDL filelists for simulation and synthesis
├── scripts/                     Automation scripts for project workflows
Outputs (git-ignored, created by the scripts)
├── synth/                       Generated synthesis outputs
├── sim/                         Generated simulation outputs
├── NIST_test/                   Generated NIST validation outputs
Outside Resources
├── NIST-Statistical-Test-Suite/ External NIST Statistical Test Suite (public submodule)
└── keccak/                      Keccak RTL and golden models (public submodule)
```

Output folders are not expected to exist immediately after cloning; each workflow creates its own
as needed. See [Outputs](#outputs) above for the exact per-workflow layout, and [Script
Reference](#script-reference) for the full contents of each folder.

Continuous integration (`.github/workflows/ci.yml`) runs functional simulation and a NIST
regression check on every push; it intentionally does not cover ASIC/FPGA synthesis, since those
need proprietary tools CI does not have access to.

## Repository Internals

This section covers conventions and shared building blocks referenced above, for anyone working
inside the golden-model/testbench code rather than only running the scripts.

### C++ Golden Model Structure

Each PRNG's algorithmic behavior is implemented once, as a standalone C++ class, and instantiated
by both `main_SIM.cpp` and `main_NIST.cpp`. Two reusable base classes define the common
interfaces every compatible implementation follows:

- [`PRNG.hpp`](golden_model/Common/PRNG.hpp): base class for a complete pseudo-random number
  generator;
- [`BlockFunction.hpp`](golden_model/Common/BlockFunction.hpp): base class for a cryptographic
  primitive used as a block transformation inside a PRNG.

This separates the general interface from the concrete implementation, so simulation code can
interact with different PRNGs (or the primitives they select between) through a common API. Good
examples: [`DP.hpp`](golden_model/DP/DP.hpp) and
[`MersenneTwister.hpp`](golden_model/MersenneTwister/MersenneTwister.hpp).

Reusable patterns worth following (see [golden_model/MersenneTwister](golden_model/MersenneTwister)
for a simple standalone PRNG, [golden_model/ctr_drbg](golden_model/ctr_drbg) for one with a
selectable primitive, and [golden_model/DP](golden_model/DP) for a more parameterized one):

- keep the PRNG algorithm in dedicated source/header files, keeping `main_SIM.cpp`/`main_NIST.cpp`
  as thin workflow entry points;
- build the configuration from defaults first, then apply `-param` overrides with
  `ParameterParser`;
- use `bytesNumber` for arbitrary-width values that must match RTL vectors;
- (optional) source real randomness for PRNG inputs from a standard C++ TRNG facility.

### Testbench Structure

Beyond the top-module-naming and plusargs conventions already covered in [Evaluating Your Own
PRNG](#evaluating-your-own-prng-bring-your-own-hardware), a suggested internal organization
(followed by every testbench in this repository) is:

| Unit | Main responsibility | Notes |
|---|---|---|
| `TB_<module>` | Top-level testbench module. | Generates clock/reset, instantiates the DUT, connects it to `data_maker`/`data_sink`, initializes the waveform dump. |
| `data_maker` | Input driver. | Reads `inputVect.txt` and applies it to the DUT per its input handshake (e.g. new data only when the DUT is ready). |
| `data_sink` | Output checker and protocol monitor. | Reads `outputVect_gold.txt`, samples DUT outputs per its output handshake, compares against the golden model, and also checks control-signal correctness (unexpected `valid`, missing outputs, protocol violations) even when not explicitly covered by the golden output file. Reports the final PASS/FAIL status. |

Testbench parameters must stay aligned with the RTL top-level parameters, so Verilator's
`-GNAME=VALUE` overrides apply consistently to both. See
[`tb/DP/TB_DP.sv`](tb/DP/TB_DP.sv), [`data_maker.sv`](tb/DP/data_maker.sv) and
[`data_sink.sv`](tb/DP/data_sink.sv) for a complete example.

### Project Filelists

Beyond the three filelists per module already covered in [Evaluating Your Own
PRNG](#evaluating-your-own-prng-bring-your-own-hardware): keeping simulation, ASIC and FPGA
filelists separate avoids mixing simulation-only (testbench) files into a synthesis run. Examples
are in [`prj/`](prj/).

### Synthesis Wrapper Rules

ASIC synthesis targets the module RTL directly. FPGA synthesis expects a Xilinx wrapper named
exactly `xilinx_<module>_wrapper`, exposing the target FPGA-facing interface and instantiating
the real PRNG core internally; keep its parameters aligned with the parameters used by the
selected variants.

## Citing PEARL

If you use PEARL in your own work, please cite:

> V. Piscopo, A. Dolmeta, B. Farnaghinejad, E. Sanchez, S. Di Carlo, A. Savino, M. Martina, and
> G. Masera, "PEARL: An Open Framework for Reproducible Evaluation of Hardware PRG
> Architectures," submitted to SeHAS 2027.

A BibTeX entry will be added here once the paper is formally published.

## Acknowledgments

PEARL is developed and maintained by the **EDGE Group, VLSI Lab**, Department of Electronics and
Telecommunications, Politecnico di Torino, together with the Department of Control and Computer
Engineering, Politecnico di Torino.

Special thanks to **Andrea Viola** and
**Lorenzo Garbarino** as part of a Special Project at Politecnico di Torino.