# MiniProject 2 — Phase 3 Final Report

**Course:** EEE 598 — AI/ML for EDA  
**Student:** Jatin Makhijani  
**GitHub:** https://github.com/makhijanijatin02/codex_verification_agent_for_rtl_testbench_generation

---

## 1. Motivation for the Problem

Hardware verification is the most time-consuming phase in the chip design cycle, often consuming over 60% of total project effort. Today, verification engineers must manually read natural-language specifications, mentally interpret every edge case, and then hand-write cycle-accurate SystemVerilog or UVM testbenches to check that the RTL behaves correctly. This process is slow, error-prone, and does not scale.

Traditional automation in EDA is insufficient for this task. Existing scripting tools (Tcl, Makefiles) can compile and simulate hardware, but they cannot *reason* about the meaning of an English specification. They cannot determine which behaviors are guaranteed, which are ambiguous, or which edge cases the spec leaves undefined. This semantic reasoning gap is exactly where AI and agent-based approaches are needed. A Large Language Model (LLM) can read the English specification, extract structured behavioral intent, and generate Verilog testbench code — tasks that no traditional script can accomplish. By embedding the LLM inside a feedback-driven agent pipeline (rather than using it as a one-shot code generator), we can iteratively refine the testbench using real EDA simulator output, closing the loop between AI reasoning and concrete hardware simulation results.

## 2. Problem Definition

We are addressing the ICLAD Hackathon 2025 verification challenge. The task is to automatically generate a discriminating Verilog testbench that isolates the single correct RTL implementation from a pool of 31 flawed candidate mutants.

- **Inputs:** A problem directory containing:
  - `specification.md` — a natural-language description of the hardware module's intended behavior.
  - `mutant_0.v` through `mutant_30.v` — 31 candidate Verilog RTL implementations, where exactly one is correct and the remaining 30 contain subtle bugs.

- **Outputs:**
  - A self-checking Verilog testbench (`tb/<problem_name>_tb.v`).
  - Intermediate reasoning artifacts: `parsed_spec.json` (structured behavior model) and `test_plan.json` (safe/unsafe check plan).
  - A simulation results file (`final_result.json`) reporting which mutants passed and which failed.

- **Objective:** Achieve a discrimination score of 1.0 — meaning exactly one mutant passes (the correct RTL) and all 30 others fail — fully automatically, with no manual intervention.

## 3. System Overview

Our system is a fully automated, iterative pipeline. The high-level data flow is:

**Input → Agent (Planning) → Agent (Execution) → EDA Tool → Feedback → Output**

1. **Input:** The pipeline reads the natural-language `specification.md` and deterministically extracts the Verilog module header (port names, widths, directions) directly from one of the candidate RTL files.

2. **Agent (Planning):** The agent sends the raw specification text and module header to the LLM with a structured prompt. The LLM returns a JSON object (`parsed_spec.json`) classifying every behavior as "guaranteed," "ambiguous," or "forbidden." A second LLM call converts this into a `test_plan.json` containing explicit lists of `safe_checks` (to assert) and `unsafe_checks` (to avoid).

3. **Agent (Execution):** A third LLM call generates the complete Verilog testbench. Before passing the code to the simulator, deterministic Python guardrails automatically scrub the LLM's output for known syntax hallucinations (e.g., replacing illegal `always @(posedge clk1 and clk2)` with the correct `always @(posedge clk1 or posedge clk2)`).

4. **EDA Tool:** The testbench is compiled and simulated against all 31 mutants using Icarus Verilog (`iverilog` for compilation, `vvp` for simulation).

5. **Feedback:** Simulation results — compile errors, runtime assertion failures, and pass/fail counts — are captured. If the score is not perfect, the agent feeds the failing testbench code and truncated error logs back to the LLM for an iterative repair attempt.

6. **Output:** Once a perfect score is achieved or the iteration budget is exhausted, the pipeline writes `final_result.json` with the score and the names of the passing/failing mutants.

## 4. Agent Architecture

Our agent is composed of four distinct modules. This multi-stage decomposition is what separates our approach from simple one-shot prompting.

- **Planner / Decision Module (`spec_parser.py`):** This module does not ask the LLM to write Verilog immediately. Instead, it forces the LLM to first *reason* about the specification by extracting structured JSON. It classifies each behavior as "guaranteed" (safe to assert), "ambiguous" (do not assert strictly), or "forbidden" (the testbench must never assume this). This prevents the LLM from making overly rigid assumptions that would cause correct implementations to fail.

- **Executor (`tb_generator.py`):** This module invokes the LLM to write the actual Verilog testbench, but wraps the output in deterministic Python guardrails. These guardrails include: (a) regex-based syntax sanitization to fix hallucinated sensitivity lists, (b) injection of synchronous reset monitors, and (c) stripping of markdown code-block wrappers that the LLM sometimes includes.

- **Parser (`simulator.py`):** After simulation, this module parses the raw terminal output from `iverilog`/`vvp`. It categorizes each mutant as "compile error," "runtime fail," or "pass" by scanning for `$finish`, assertion failure messages, and error strings. It then computes the discrimination score.

- **Feedback Loop (`agent.py`):** This is the iterative reasoning engine. If too many mutants pass (score < 1.0), the agent constructs a new prompt that includes the current testbench code, the list of still-passing mutants, and a request to add stronger checks. If all mutants fail due to a compile error, it triggers a dedicated repair prompt. This tool-in-the-loop execution with adaptive decision-making is what fundamentally distinguishes our system from one-shot prompting.

**How decisions are made:** The agent routes each problem into one of three Oracle styles — `formula` (for combinational logic), `cycle_accurate` (for simple sequential logic), or `protocol_invariant` (for complex asynchronous handshake modules). This classification determines which prompt template is used for testbench generation. A detailed explanation of these terms is provided in our repository's `docs/terminology.md`.

## 5. Tools & Frameworks

| Tool | Role in the System |
|------|-------------------|
| `iverilog` (Icarus Verilog) | Compiles the generated Verilog testbench together with each mutant RTL file. |
| `vvp` | Executes the compiled simulation binary and captures runtime output. |
| `codex-cli` with `gpt-5.4` | Serves as the core LLM reasoning engine for parsing specifications, generating test plans, writing Verilog testbenches, and repairing broken code. |
| Custom Python agent (`agent.py`, `run_pipeline.py`) | Orchestrates the full pipeline: file I/O, subprocess management, prompt construction, metric tracking, iterative feedback loops, and result serialization. |

No external agent framework (e.g., LangChain, AutoGen) was used. The entire agent infrastructure was built from scratch in Python to maintain full control over prompt routing, timeout handling, and guardrail injection.

## 6. Context Engineering

- **What information is provided to the agent:**
  - The full text of `specification.md` (the natural-language behavior description).
  - The Verilog module header (port list with names, widths, and directions), extracted deterministically from the RTL — not generated by the LLM.
  - During feedback iterations: the current failing testbench code and truncated simulation log output.

- **How context is structured:**
  - **Raw text → JSON → JSON:** The raw English specification is first distilled into a structured `parsed_spec.json` (with fields for inputs, outputs, resets, guaranteed behaviors, ambiguous behaviors, and forbidden assumptions). This JSON is then compacted into a `test_plan.json` (with explicit `safe_checks` and `unsafe_checks` lists). This two-stage distillation prevents token bloat when the final testbench generation prompt is constructed.

- **How we manage context:**
  - *Size:* We aggressively truncate simulation feedback logs to only the first few failing lines. We drop verbose random-test suggestions from the JSON payload to stay within LLM context limits and avoid timeouts.
  - *Relevance:* We route prompts based on problem classification. Protocol-heavy modules (CDC FIFOs, credit receivers) receive a dedicated `gen_testbench_protocol.txt` prompt that explicitly warns the LLM against unsafe assumptions. Simple datapath modules receive the standard `gen_testbench.txt` prompt.
  - *Noise Filtering:* Python regex filters scrub out markdown code-block wrappers (` ```verilog ... ``` `) and sanitize reserved Verilog keywords before the generated code is passed to `iverilog`.

## 7. Improvements from Phase 2

In Phase 2, our system had three critical weaknesses: (1) the LLM would invent overly specific latency assumptions for protocol modules, causing correct implementations to fail; (2) it frequently got trapped in "repair loops" where it hallucinated the same Verilog syntax error repeatedly; and (3) it could only solve 7 out of 10 visible problems.

In Phase 3, we implemented the following upgrades:

1. **Aggressive Python Sanitization:** We added deterministic regex-based guardrails in `tb_generator.py` that globally scan the LLM's Verilog output and automatically fix invalid syntax *before* it reaches the compiler. For example, `always @(posedge clk1 and clk2)` is rewritten to `always @(posedge clk1 or posedge clk2)`. This completely broke the hallucination-driven repair loop.

2. **Ambiguity-Aware Planning:** The spec parser now explicitly identifies "forbidden assumptions" (such as exact clock-cycle latencies for asynchronous FIFOs) during the planning phase. This forces the LLM to generate passive, event-driven scoreboards instead of rigid cycle-accurate checks.

3. **Timeout Hardening:** We increased the `codex-cli` backend timeout from 180 seconds to 1800 seconds, preventing the pipeline from crashing during large specification processing.

4. **Result:** These changes improved our success rate from **7/10 to 9/10** visible problems solved with a perfect 1.0 score.

## 8. Results

Our agent was evaluated on all 10 visible benchmark problems from the ICLAD Hackathon suite. For each problem, the testbench was compiled and simulated against all 31 candidate mutant RTL implementations. The objective was to isolate exactly 1 correct mutant (score = 1.0).

| Problem | Score | Correct Mutant Identified | Compile Errors |
|---------|------:|:--------------------------|:--------------:|
| `ecc_sed_encoder` | 1.0 | `mutant_18` | 0 |
| `enc_bin2gray` | 1.0 | `mutant_25` | 0 |
| `enc_bin2onehot` | 1.0 | `mutant_27` | 0 |
| `lfsr` | 1.0 | `mutant_29` | 0 |
| `shift_left` | 1.0 | `mutant_1` | 0 |
| `shift_right` | 1.0 | `mutant_9` | 0 |
| `counter` | 1.0 | `mutant_11` | 0 |
| `credit_receiver` | 1.0 | `mutant_18` | 0 |
| `fifo_flops` | 1.0 | `mutant_23` | 0 |
| `cdc_fifo_flops_push_credit` | 0.0 | None (timeout) | 0 |

**Overall: 9/10 problems solved with perfect discrimination (score 1.0).**

**Analysis — Why it improved:** The ambiguity-aware test plan prevented the LLM from over-constraining assertions. In Phase 2, modules like `credit_receiver` and `fifo_flops` failed because the generated oracle assumed exact cycle counts that varied between correct implementations. By explicitly classifying these as "unsafe checks," the Phase 3 agent generated flexible, protocol-invariant scoreboards that correctly discriminated the mutants.

**Analysis — Where it failed:** The `cdc_fifo_flops_push_credit` module has the largest and most complex specification in the benchmark suite. The LLM backend (`codex-cli`) consistently timed out after 1800 seconds during the initial specification parsing step, indicating that the raw specification exceeds the practical context processing capacity of the current model. This is a fundamental scalability limitation rather than a logic or prompt engineering failure.

## 9. Challenges, Limitations, Improvements

**Key Challenges Encountered (Technical/System-Level):**
- **LLM Syntax Hallucinations:** The LLM frequently generated invalid Verilog syntax, particularly for multi-clock sensitivity lists. This required us to build deterministic Python regex sanitizers as a safety net between the LLM and the EDA compiler.
- **Anchoring Bias in Repair Loops:** When the LLM was asked to fix a broken testbench, it often anchored onto its previous broken code and made superficial tweaks instead of fundamentally rewriting the flawed logic. This required us to implement "rescue" prompts that provide a fresh context without the old broken code.
- **Semantic Oracle Generation:** For protocol-heavy modules, writing a correct oracle from an ambiguous English specification is an unsolved research problem. The LLM tends to invent specific latency assumptions that are not guaranteed by the spec.

**Limitations of Current Approach:**
- *Scalability:* The pipeline cannot handle specifications that exceed the LLM's context processing timeout (as demonstrated by `cdc_fifo_flops_push_credit`).
- *Generalization:* The system works best on combinational and simple sequential modules. Complex asynchronous protocols with multiple clock domains remain challenging.
- *Robustness:* The LLM's output is inherently non-deterministic. Different runs on the same problem may produce slightly different testbenches, though the final discrimination results have been reproducible.
- *Runtime:* Each problem takes 2–10 minutes for spec parsing and testbench generation (dominated by LLM latency), plus a few seconds for simulation.

**Concrete Improvements for Future Work:**
- *Scalability:* Implement specification chunking — break massive specs into smaller sections and parse them independently before merging.
- *Generalization:* Introduce UVM-lite testbench harnesses with pre-written transaction tasks (push, pop, credit handshake) so the LLM only needs to generate high-level sequences.
- *Robustness:* Add a majority-voting mechanism: generate 3 testbenches in parallel and use the one with the best discrimination score.
- *Runtime:* Parallelize mutant simulations across multiple CPU cores to reduce the EDA bottleneck.

## 10. AI Usage & Insights / Experience with AI

**Role of AI in the system:**
- *Decision-Making:* The LLM classifies each problem as `formula`, `cycle_accurate`, or `protocol_invariant` to determine the appropriate oracle strategy.
- *Script Generation:* The LLM writes the entire Verilog testbench — hundreds of lines of stimulus generation, clock drivers, reset sequences, and assertion-based checking logic.
- *Debugging:* During repair iterations, the LLM reads `iverilog` compiler error messages and attempts to fix the broken testbench code.

**Deep Insights — Where AI works well:**
- The LLM excels at parsing natural-language specifications and identifying mathematical corner cases for combinational logic (e.g., Gray code formulas, one-hot encodings, LFSR polynomials).
- It generates structurally sound testbench scaffolding (module instantiation, clock generation, `$dumpfile`/`$dumpvars`) with very high reliability.

**Deep Insights — Where AI fails:**
- The LLM frequently hallucinates Verilog syntax for dual-clock sensitivity lists (using `and` instead of `or`).
- It struggles with reasoning about parallel, concurrent execution in Verilog. It tends to write sequential, blocking logic even when the specification describes concurrent processes.
- It routinely ignores negative constraints. Even when the prompt explicitly states "Do NOT use exact cycle latency," the LLM will often generate `repeat(5) @(posedge clk)` assertions.

**Where human intervention was required:**
- Building all Python scaffolding: regex sanitizers, subprocess wrappers, timeout handlers, and prompt routing logic.
- Designing the two-stage spec parsing strategy (raw text → structured JSON → test plan) to prevent token bloat.
- Identifying and codifying the three oracle styles as prompt engineering patterns.

**Experience and Reflections:**
Building this agent fundamentally changed my perspective on using AI in engineering. The key lesson is that the LLM is not a reliable code generator — it is an unreliable but highly capable subsystem that requires robust deterministic wrappers. The AI dramatically accelerated productivity by writing thousands of lines of Verilog boilerplate in seconds, but it also introduced an entirely new class of debugging: tracing *why* the LLM anchored onto a specific hallucinated syntax pattern and figuring out how to break that anchoring. Ultimately, I learned that the secret to building effective agentic workflows is not better prompts alone, but better tool-in-the-loop validation and rigid Python guardrails to catch the AI when it inevitably makes mistakes. The combination of AI reasoning power with deterministic engineering safeguards is what made this system achieve 90% accuracy on a non-trivial hardware verification benchmark.
