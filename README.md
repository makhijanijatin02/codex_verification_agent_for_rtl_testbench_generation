# Codex Verification Agent for RTL Testbench Generation

This repository contains a Codex-driven verification agent for the ICLAD / Google verification-style RTL benchmark. The system reads a natural-language hardware specification plus a directory of candidate Verilog implementations, generates a self-checking Verilog testbench, runs it against all mutants, and reports how selectively that testbench isolates a single implementation.

This README is written for project demonstration and presentation use. It explains the current architecture, the prompt-engineering strategy, what is working well, and where the system still struggles.

## Project Goal

Each benchmark problem contains:

- `specification.md`: natural-language behavior specification
- `mutant_*.v`: candidate RTL implementations

Only one implementation is intended to be correct. The agent must generate a Verilog testbench that:

- passes the correct implementation
- fails buggy mutants
- compiles and runs automatically under `iverilog` / `vvp`

The ideal outcome is that exactly one implementation passes.

## Current Approach

The repository implements a structured generate-evaluate-refine workflow:

1. Parse the natural-language specification into structured JSON.
2. Generate a test plan from the parsed behavior.
3. Generate a self-checking Verilog testbench using Codex.
4. Compile and simulate that testbench against all RTL mutants.
5. Score the result and optionally refine the testbench.

This is not a one-shot prompt. It is an agent pipeline with intermediate artifacts, simulator feedback, prompt routing, and regeneration logic.

## Repository Structure

```text
codex_verification_agent_for_rtl_testbench_generation/
├── agent.py
├── run_pipeline.py
├── run_sim.py
├── spec_parser.py
├── tb_generator.py
├── simulator.py
├── prompts/
│   ├── parse_spec.txt
│   ├── gen_testplan.txt
│   ├── gen_testbench.txt
│   ├── gen_testbench_protocol.txt
│   └── repair_testbench.txt
├── sample_problem/
├── tb/
└── artifacts/
```

## Pipeline Components

### `spec_parser.py`

Uses Codex to extract structured behavior from the English spec. The parsed JSON now includes not only interface and behavior, but also explicit oracle-planning fields:

- `oracle_style`
- `executable_reference`
- `guaranteed_properties`
- `ambiguous_properties`
- `forbidden_assumptions`

This is important because the main failure mode on sequential/protocol modules was not syntax. It was overconfident oracle generation.

### `tb_generator.py`

Builds the prompt input for testbench generation and repair. It also:

- routes protocol-heavy problems to a stricter instruction set
- enforces light deterministic post-processing for Icarus compatibility
- applies guardrails to reject unsafe FIFO/CDC testbench structures
- passes ambiguity-aware spec fields into generation and repair

Two prompt modes are used:

- `gen_testbench.txt` for general datapath / simpler sequential modules
- `gen_testbench_protocol.txt` for FIFO / CDC / credit / handshake style modules

### `simulator.py`

Compiles generated testbenches with `iverilog -g2012` and executes them with `vvp` across all mutants.

### `agent.py`

Coordinates the full loop:

- load problem
- parse spec
- generate plan
- generate testbench
- apply protocol guardrails and regenerate if the testbench is structurally unsafe
- run compile screen
- simulate all mutants
- compute score
- do one immediate rescue refinement if everything fails

## Prompt Engineering Strategy

The main contribution in this version is prompt engineering aimed at making Codex generate a more trustworthy oracle, not just a syntactically valid testbench.

### 1. Structured spec interpretation

The parser prompt does not only summarize behavior. It forces Codex to separate:

- behaviors explicitly guaranteed by the spec
- plausible but ambiguous behaviors
- assumptions that should not be asserted strictly

This is the foundation for better testbench generation.

### 2. Oracle-style selection

Each problem is pushed into one of three reasoning modes:

- `formula`
  Use for direct combinational formulas and mappings.
- `cycle_accurate`
  Use for simple sequential modules whose state update is explicitly defined cycle by cycle.
- `protocol_invariant`
  Use for FIFO / CDC / credit / handshake modules where only interface-level guarantees are safe.

### 3. Safe vs unsafe checks

The test-plan prompt now explicitly produces:

- `safe_checks`: checks that are grounded in guaranteed behavior
- `unsafe_checks`: tempting but ambiguous checks that the generated testbench should avoid asserting strictly

### 4. Protocol-specific prompting

For protocol-heavy modules, the dedicated prompt instructs Codex to avoid:

- exact CDC latency assumptions
- exact counter arithmetic assumptions
- exact queue-depth/status equalities
- exact credit pulse windows
- bounded “must happen within N cycles” logic unless the spec explicitly guarantees it

### 5. Repair-mode prompting

Repairs now use `repair_testbench.txt` rather than reusing the generation prompt. This keeps compile fixes and broad-mismatch repairs focused on simplifying an over-strong oracle rather than blindly regenerating more complexity.

### 6. Guardrail-driven regeneration

For protocol-heavy modules, the system does not blindly trust the first generated testbench. It performs structural checks to catch common unsafe patterns such as:

- bounded protocol wait loops
- exact status-counter reconstruction
- exact credit-pulse reconstruction
- risky FIFO/CDC assumptions that are not clearly guaranteed by the spec

If those patterns appear, the agent asks Codex to regenerate a safer testbench before simulation.

## Why These Prompt Changes Were Needed

The system performs well on modules where the intended behavior maps cleanly to a formula or a straightforward cycle-accurate reference model.

It struggles on protocol-heavy modules because Codex tends to invent overly precise assumptions such as:

- exact synchronization latency
- exact internal counter values
- exact queue depth exposure
- exact credit-return timing

When those assumptions are wrong, the generated testbench rejects every mutant, including the intended one. The current prompt changes are designed to reduce that failure mode.

## Environment and Setup

### Requirements

- Python 3.10+
- `iverilog` (Icarus Verilog)
- `vvp`
- a working `codex exec` installation in WSL / bash
- Valid API keys configured for the LLM backend (Codex)

### Input/Output Description

**Inputs:**
- A problem directory containing:
  - `specification.md`: A natural-language description of the hardware behavior.
  - `mutant_*.v`: Multiple candidate Verilog RTL implementations (where only one is fully correct).

**Outputs:**
- A generated Verilog testbench `tb/<problem_name>_tb.v`.
- Intermediate LLM artifacts (`parsed_spec.json`, `test_plan.json`).
- Simulation results (`run_sim_results.json`, `final_result.json`) detailing which mutants passed and which failed.

### Current `.env` configuration

The repository currently uses:

```env
CODEX_CLI_COMMAND=codex exec
CODEX_MODEL=gpt-5.4
CODEX_TIMEOUT_SECONDS=600
```

Important environment note:

- `codex exec` worked in WSL / bash
- it was not available in native Windows PowerShell in this setup

## How To Run

From the repository root, you can run the complete end-to-end pipeline using the single entry script:

```bash
python3 run_pipeline.py --problem-dir sample_problem --max-iters 1
```

Example for a visible benchmark problem:

```bash
python3 run_pipeline.py --problem-dir "/mnt/c/Users/makhi/OneDrive - Arizona State University/Mini_Project_2/phase2/ICLAD-Hackathon-2025/visible_problems/enc_bin2gray" --max-iters 1
```

## How to Run the Hidden Testcases

To evaluate the system on hidden or held-out testcases, simply point the `--problem-dir` argument to the absolute or relative path of the hidden problem folder. The workflow is entirely automated with no manual steps required.

```bash
# Example for running a hidden testcase
python3 run_pipeline.py --problem-dir "/path/to/hidden_problems/new_mystery_module" --max-iters 3
```
*Note: Increasing `--max-iters` gives the agent more attempts to refine its testbench if multiple mutants initially pass.*

## Expected Results (Verification)

When the pipeline completes successfully on a provided problem directory, you should expect:
1. **Successful Testbench Compilation:** The agent writes `tb/<problem_name>_tb.v` and compiles it using `iverilog` without syntax errors.
2. **Mutant Discrimination:** The testbench simulates against all provided mutants. The ideal and expected result is a score of `1.0`, meaning exactly **1** mutant passes (the correct RTL) and all other mutants fail. 
3. **Artifact Generation:** A `final_result.json` file is produced containing the exact score and the names of the passing/failing mutants.

## Output Artifacts

For each problem, the pipeline writes:

- `tb/<problem_name>_tb.v`
- `artifacts/<problem_name>/parsed_spec.json`
- `artifacts/<problem_name>/test_plan.json`
- `artifacts/<problem_name>/iteration_<n>_results.json`
- `artifacts/<problem_name>/final_result.json`
- `artifacts/<problem_name>/run_sim_results.json`

For full-batch runs it also writes:

- `artifacts/batch_summary.json`
- `artifacts/batch_results.json`
- `artifacts/batch_summary.md`

## Current Results

### Full visible benchmark summary available in this repo

The previous visible batch summary in `artifacts/batch_summary.md` reports:

- problems evaluated: `10`
- average score: `0.9000`
- clean selective solves: `9/10`

Representative results from that batch:

| Problem | Score | Passing | Compile Errors |
|---------|------:|--------:|---------------:|
| `ecc_sed_encoder` | 1.0000 | 1/31 | 0 |
| `enc_bin2gray` | 1.0000 | 1/31 | 0 |
| `enc_bin2onehot` | 1.0000 | 1/31 | 0 |
| `lfsr` | 1.0000 | 1/31 | 0 |
| `shift_left` | 1.0000 | 1/31 | 0 |
| `shift_right` | 1.0000 | 1/31 | 0 |
| `counter` | 1.0000 in latest rerun | 1/31 | 0 |
| `credit_receiver` | 1.0000 | 1/31 | 0 |
| `fifo_flops` | 1.0000 | 1/31 | 0 |
| `cdc_fifo_flops_push_credit` | 0.0000 | 0/31 | 0 |

### Selected-Problem Presentation View

The full visible benchmark contains `10` problems.

Across the full visible benchmark, the current stable result is:

- `9/10` problems solved cleanly with `1/31`
- `1/10` protocol-heavy problems still unresolved

The presentation emphasizes the following strongest results:

- `enc_bin2gray`
- `enc_bin2onehot`
- `lfsr`
- `shift_left`
- `shift_right`
- `counter`
- `ecc_sed_encoder`
- `credit_receiver`
- `fifo_flops`

For each of these 9 problems, the agent generated a compiling self-checking testbench that isolated exactly one passing implementation out of 31 candidates, corresponding to a score of `1.0`.

The remaining difficult case is:

- `cdc_fifo_flops_push_credit`

This unresolved problem is a complex protocol-heavy module, where the main challenge is not Verilog syntax generation but constructing a trustworthy verification oracle from a massive, ambiguous natural-language specification that routinely causes the LLM backend to timeout due to context size. This is currently the primary limitation of the prompt-only approach.

### Stable presentation takeaway

The current stable presentation result is:

- `9` visible problems solved cleanly with `1/31`
- `1` protocol-heavy problem still unresolved
- `0` compile-error failures on the selected set

So the main remaining gap is not tool compatibility. It is semantic oracle generation and context-window limitations for extremely massive protocol specifications.

## Honest Interpretation of Results

What is working well:

- the full pipeline executes end-to-end
- compile stability is much better than earlier versions
- prompt-engineered Codex generation is strong on many combinational and simpler sequential problems
- the artifact trail is reproducible and presentation-friendly
- ambiguity-aware prompt engineering clearly improved at least one formerly failing visible problem: `counter`

What is still difficult:

- CDC / handshake modules with extremely large specifications that exceed LLM timeout bounds
- cases where the spec is behaviorally rich but timing semantics are not fully explicit
- preventing the LLM from inventing overly specific internal oracle assumptions

This is an important part of the project story: the challenge is not only generating Verilog, but generating a trustworthy oracle from ambiguous English specifications.

## What Was Improved During This Iteration

Relative to the earlier version of the repo, this version now includes:

- deterministic module-header extraction from RTL instead of asking the LLM
- stronger discriminative prompt wording
- compile-repair and rescue flow
- protocol-specific generation prompt
- protocol guardrails for unsafe bounded-wait logic
- explicit ambiguity-aware spec parsing
- explicit safe-check / unsafe-check planning
- repair-mode prompt separation
- a verified `counter` fix from ambiguity-aware prompt refinement, improving it from an earlier failing run to `1/31`

## Current Limitation

This project intentionally stays professor-safe:

- no hand-written module-specific oracle injection
- no hardcoded reference testbench per benchmark problem
- Codex still generates the actual testbench

That means difficult protocol modules remain a real research/engineering problem rather than being solved by manually embedding a known-good checker.

## Recommended Presentation Narrative

If you need to present this work, the clean story is:

1. We built an agent pipeline, not a one-shot prompt.
2. We engineered prompts to separate guaranteed vs ambiguous behavior.
3. That improved the semantic quality of generated testbenches.
4. The system is strong on formula-like and simpler sequential modules, with `counter` recovered through prompt refinement.
5. The main remaining research challenge is protocol-heavy oracle generation under ambiguity.

## Useful Files For Demo

- `run_pipeline.py`
- `agent.py`
- `spec_parser.py`
- `tb_generator.py`
- `prompts/parse_spec.txt`
- `prompts/gen_testplan.txt`
- `prompts/gen_testbench.txt`
- `prompts/gen_testbench_protocol.txt`
- `prompts/repair_testbench.txt`
- `artifacts/batch_summary.md`
- `artifacts/counter/final_result.json`
- `artifacts/enc_bin2gray/final_result.json`
- `artifacts/enc_bin2onehot/final_result.json`
- `artifacts/lfsr/final_result.json`
- `artifacts/shift_left/final_result.json`
- `artifacts/shift_right/final_result.json`

## One-Line Demo Command

```bash
python3 run_pipeline.py --problem-dir "/mnt/c/Users/makhi/OneDrive - Arizona State University/Mini_Project_2/phase2/ICLAD-Hackathon-2025/visible_problems/enc_bin2gray" --max-iters 1
```

That command is currently one of the cleanest ways to show the system working end to end.
