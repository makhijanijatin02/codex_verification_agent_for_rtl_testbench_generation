# Codex Verification Agent for RTL Testbench Generation

**Mini Project 2, Topic 2: AI for Design Verification (Google Track)**

This repository contains a Codex-based verification agent that reads a natural-language RTL specification plus candidate Verilog implementations, generates a self-checking Verilog testbench, runs simulation, and iteratively refines the testbench until only the correct RTL passes.

## Setup Instructions

### Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install iverilog

# macOS
brew install icarus-verilog
```

You also need a working Codex CLI installation in your shell.

### Environment

Set the following environment variables before running the pipeline:

```bash
export CODEX_MODEL=gpt-5-codex
export CODEX_CLI_COMMAND="codex exec"
export CODEX_TIMEOUT_SECONDS=600
```

If your shell cannot launch `codex exec` directly, set `CODEX_CLI_COMMAND` to the correct launcher for your environment.

## Single Command To Run The System

The complete workflow is automated through one command:

```bash
python3 run_pipeline.py --problem-dir sample_problem --max-iters 1
```

This single command:
1. reads the selected problem
2. generates the testbench
3. runs simulation on all mutant RTL files
4. writes outputs to `tb/` and `artifacts/`

## Input / Output Description

### Inputs

- `sample_problem/specification.md`: natural-language RTL specification
- `sample_problem/mutant_*.v`: candidate implementations

For real ICLAD visible or hidden problems, pass a different problem directory to `--problem-dir`.

### Outputs

- `tb/<problem_name>_tb.v`: generated testbench
- `artifacts/<problem_name>/parsed_spec.json`: structured parsed specification
- `artifacts/<problem_name>/test_plan.json`: generated test plan
- `artifacts/<problem_name>/iteration_1_results.json`: simulation results for the iteration
- `artifacts/<problem_name>/final_result.json`: final score summary
- `artifacts/<problem_name>/run_sim_results.json`: standalone simulation summary

## Exact Commands To Reproduce Results

### Sample Problem

```bash
python3 run_pipeline.py --problem-dir sample_problem --max-iters 1
```

### Standalone Simulation Recheck

```bash
python3 run_sim.py --problem-dir sample_problem --tb tb/sample_problem_tb.v
```

## Expected Results

For `sample_problem`, the expected result is:

- score: `1.0000`
- passing mutants: `1/6`
- compile errors: `0`

The generated outputs should include:

- `tb/sample_problem_tb.v`
- `artifacts/sample_problem/final_result.json`
- `artifacts/sample_problem/run_sim_results.json`

Real benchmark example outputs are also included for:

- `artifacts/enc_bin2gray/`
- `artifacts/enc_bin2onehot/`
- `artifacts/shift_right/`

A compact summary is provided in `real_benchmark_results.md`.

## Brief Workflow Description

1. `agent.py` reads the specification and candidate RTL files.
2. `spec_parser.py` converts the natural-language spec into structured JSON.
3. `tb_generator.py` creates a discriminating self-checking testbench.
4. `simulator.py` compiles and runs the testbench against each mutant using `iverilog` and `vvp`.
5. `run_sim.py` records reproducible simulation metrics.
6. If needed, the agent can refine the generated testbench in later iterations.

## How To Run Hidden Testcases

If hidden benchmark problem directories are available locally in the same format as the sample problem, run:

```bash
python3 run_pipeline.py --problem-dir /path/to/hidden/problem_X --max-iters 1
```

The expected directory structure is:

```text
problem_X/
├── specification.md
└── mutant_*.v
```

No manual editing is required. The pipeline is fully automated as long as the hidden testcase follows the same input format.
