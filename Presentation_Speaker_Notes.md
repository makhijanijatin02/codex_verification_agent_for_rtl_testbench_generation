# Presentation Speaker Notes
## Codex Verification Agent for RTL Testbench Generation
### 6-Minute Delivery Guide

---

## Slide 1 — Title (30 seconds)

**Say:**
> "Hi everyone. Our project is about automating hardware verification using an AI agent. The task is — given a natural-language spec for a hardware module and 31 candidate RTL implementations, can our agent figure out which one is correct? We built a full agent pipeline using Codex and Icarus Verilog to do exactly that."

**Key point to land:** This is not just prompting — it's a full agent pipeline with tool use and feedback.

---

## Slide 2 — Problem Definition (60 seconds)

**Say:**
> "Let me explain the problem precisely. The ICLAD Google Verification benchmark gives you two things: a specification in plain English, and 31 Verilog implementations of that module. Only one is correct — the rest have injected bugs. Your job is to generate a self-checking testbench that passes exactly the correct design and fails all the buggy ones."

> "The scoring metric is Score = 1 divided by the number of passing implementations. If your testbench is too strict and rejects everything including the correct one, score is 0. If it's too loose and passes all 31, score is 1/31. The ideal result is exactly one passing — a perfect score of 1.0."

**If asked: "Why is this hard?"**
> "Because the spec is written in English — it's ambiguous, incomplete, and uses informal language. You can't just copy-paste the spec into a testbench. The LLM has to interpret what the hardware is supposed to do, decide what to assert, and generate simulatable Verilog — all from natural language."

---

## Slide 3 — Agent Architecture (75 seconds)

**Say:**
> "Our system is a structured five-stage pipeline, not a one-shot prompt. Stage one: we parse the spec into structured JSON using Codex, extracting not just interface and behavior, but also oracle-planning fields — what is explicitly guaranteed, what is ambiguous, and what the agent should never assume."

> "Stage two builds a test plan with safe checks versus unsafe checks. Stage three generates the testbench — routing simpler modules to one prompt and protocol-heavy modules to a stricter prompt. Stage four is a guardrail check: before we even simulate, we structurally inspect the generated testbench for dangerous patterns. If it's unsafe, we ask Codex to regenerate. Stage five simulates with iverilog and vvp across all 31 mutants, scores, and triggers a repair pass if something goes wrong."

**If asked: "How is this different from just prompting Codex?"**
> "A plain prompt produces one output — you get what you get. Our agent reads simulator output, understands compile errors, knows why a testbench failed, and uses that feedback to improve. There are intermediate artifacts at every stage — parsed JSON, test plan JSON, simulation logs — so the agent always knows where it is in the process."

**If asked: "What does the repair step do?"**
> "If the testbench has a compile error, the repair prompt gets the Verilog plus the error message and fixes it. If everything fails at runtime, there's a rescue refinement that simplifies the oracle rather than rebuilding from scratch. The repair prompt is separate from the generation prompt — they have different goals."

---

## Slide 4 — Prompt Engineering Strategy (90 seconds)

**Say:**
> "This is the core contribution. The insight is: generating syntactically valid Verilog is not the hard part. The hard part is generating a trustworthy oracle — a testbench that is selective enough to catch bugs but not so strict that it invents timing constraints the spec never promised."

> "We engineered four specific mechanisms for this. First, structured spec parsing: the parser doesn't just summarize the spec — it forces Codex to separate guaranteed behaviors from ambiguous ones and list assumptions the testbench must never make."

> "Second, oracle-style selection: every problem gets routed to one of three modes. Formula mode for combinational logic, cycle-accurate mode for simple sequential modules, and protocol-invariant mode for FIFO, CDC, and credit-handshake modules."

> "Third, the test plan explicitly labels safe checks versus unsafe checks. The testbench is only allowed to assert the safe ones. Fourth, for protocol modules, we run guardrails before simulation — if the generated testbench contains bounded wait loops or exact counter assumptions, we reject it and ask for a safer version."

**If asked: "Why not just use a reference model?"**
> "We intentionally avoid hardcoding reference checkers per problem. That would be trivially easy but not a valid research result — the whole point is that Codex must generate the oracle from the spec, not from a human-written ground truth. The system stays professor-safe."

**If asked: "How did this actually help?"**
> "The clearest example is the counter module. In an earlier run it failed — the oracle was asserting something the spec didn't guarantee. After adding ambiguity-aware parsing, the counter went from 0/31 to 1/31. That's a direct causal improvement from prompt engineering."

---

## Slide 5 — Results (60 seconds)

**Say:**
> "Across 10 visible benchmark problems, we achieved a 0.7 average score. Seven out of ten problems were solved cleanly — exactly one passing implementation out of 31, with zero compile errors. The seven successes span both combinational modules like enc_bin2gray and enc_bin2onehot, and sequential modules like the LFSR and the counter."

> "The three failures — credit_receiver, fifo_flops, and cdc_fifo_flops_push_credit — are all protocol-heavy modules. And importantly, they have zero compile errors. The testbenches run successfully, they just reject every single implementation including the correct one. That means the problem is not Verilog generation. It's oracle semantics."

**If asked: "Why do the protocol modules fail if there are no compile errors?"**
> "Because Codex is over-confident. It reads 'credit-based flow control' and generates an assertion like 'credit must return exactly 3 cycles after consumption.' That assumption might be wrong for the correct implementation — the spec never said 3 cycles. So the correct mutant fails, score drops to zero. The testbench is syntactically fine but semantically wrong."

**If asked: "What does 1/31 mean exactly?"**
> "It means out of 31 candidates, exactly one passed the testbench — which is the intended correct implementation. That's the ideal outcome. Score = 1 / 1 = 1.0."

---

## Slide 6 — What Worked, What's Hard & Next Steps (45 seconds)

**Say:**
> "To summarize: the pipeline executes end-to-end reliably, it's strong on formula and cycle-accurate problems, and compile stability is solid. The counter result proves that prompt engineering can causally fix failures."

> "The remaining gap is protocol oracle generation. When the spec is ambiguous about timing — like exactly when a FIFO status signal updates or how long a credit pulse lasts — Codex invents plausible but wrong assumptions. That's a research problem, not an engineering shortcut. For Phase 3 we plan to run the full visible benchmark, collect aggregate metrics, and explore weaker invariant-style assertions for protocol modules."

> "The honest takeaway is: this is not just a code generation problem. The real challenge is building a verification oracle that respects the limits of what the spec actually guarantees."

**If asked: "What would you do differently?"**
> "We'd explore property synthesis — rather than generating assertions in one shot, iteratively weaken the oracle by observing which mutants pass and fail, and use that signal to prune over-constraining checks. That would let the agent learn from simulation rather than relying entirely on prompt engineering to get the oracle right the first time."

---

## Time Budget (6 minutes total)

| Slide | Topic | Time |
|-------|-------|------|
| 1 | Title | 30s |
| 2 | Problem Definition | 60s |
| 3 | Agent Architecture | 75s |
| 4 | Prompt Engineering | 90s |
| 5 | Results | 60s |
| 6 | Summary & Next Steps | 45s |
| **Total** | | **6 min 0s** |

---

## Quick-Reference Q&A

| Question | One-line answer |
|----------|----------------|
| Why not one-shot prompting? | We use simulator feedback to repair and refine — stateful loop, not stateless generation |
| What is iverilog? | Open-source Verilog simulator used to compile and run the testbench against each mutant |
| What is oracle generation? | Deciding what to assert — too strict = correct mutant fails, too loose = bugs slip through |
| Why 31 mutants? | That's the ICLAD benchmark structure — one correct design plus 30 injected-bug variants |
| Is this generalized? | Yes — the agent reads any spec file and any mutant directory; no problem-specific hardcoding |
| What model is used? | gpt-5.4 via Codex CLI, running in WSL |
