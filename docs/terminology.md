# Verification Terminology Guide

When presenting or reviewing this project, it is critical to break down EDA verification terminology into clear, understandable concepts. Here are detailed definitions of the core concepts driving our verification agent.

---

## 1. What is an "Oracle"?
In hardware verification, an **Oracle** (also known as a Reference Model or Scoreboard) is the ultimate source of truth. It is the mechanism inside the testbench that dictates exactly what the correct output of the hardware *should* be at any given moment. 

### How is the Oracle defined?
In traditional workflows, a human engineer manually writes the Oracle in a high-level language (like C++ or Python). In our project, **the LLM is tasked with defining the Oracle automatically**. It does this by reading the natural-language specification, understanding the mathematical or logical intent, and writing Verilog code that independently calculates the expected results. The testbench then compares the actual hardware's output against the LLM-generated Oracle's expected output to determine a Pass or Fail.

---

## 2. The Three "Oracle Styles" (How the LLM checks correctness)

Depending on the complexity of the hardware, the LLM cannot use the same checking strategy for everything. We force the LLM to classify the problem into one of three **Oracle Styles** to ensure it generates safe, reliable checks.

### Style A: "Formula" (Combinational Logic)
*   **What it means:** The output depends *only* on the current inputs, exactly like a mathematical equation. There is no memory, no clocks, and no past states to remember.
*   **How it works:** The Oracle is simply a direct mathematical formula. If the input is `A` and `B`, the expected output is instantly `A + B`. 
*   **Example in our project:** The `enc_bin2gray` module. The LLM doesn't need to track time; it just applies the exact mathematical formula `Gray = Binary ^ (Binary >> 1)` and immediately checks if the RTL output matches.

### Style B: "Cycle-Accurate" (Simple Sequential Logic)
*   **What it means:** The hardware has a clock and memory (flip-flops), and the specification explicitly tells you exactly what must happen on *every single clock cycle*. 
*   **How it works:** The Oracle acts like a synchronized shadow of the hardware. For every clock tick that happens in the hardware, the Oracle updates its own internal variables. It expects the hardware's output to match its internal state perfectly, cycle by cycle.
*   **Example in our project:** The `counter` or `lfsr` modules. If the spec says "increment by 1 on every clock edge," the Oracle knows that on cycle 5, the value *must* be 5. If the RTL says 4, the Oracle fails it.

### Style C: "Protocol-Invariant" (Complex Asynchronous Logic)
*   **What it means:** The hardware involves complex, multi-step handshakes (like pushing/popping data) or multiple different clocks running at different speeds (like our CDC FIFO). You *cannot* know exactly which clock cycle an output will appear on.
*   **How it works:** The Oracle cannot be a rigid cycle-by-cycle shadow because it doesn't know the exact timing. Instead, it defines **Invariants**—universal rules that must never be broken, regardless of timing. 
*   **Example in our project:** The `cdc_fifo_flops_push_credit` module. The Oracle cannot predict exactly what cycle data will pop out because the clocks are asynchronous. Instead, the Oracle maintains a high-level list (a queue). Its invariant rule is: *"Whenever a pop occurs, the data must match the oldest data pushed."* It doesn't care *when* the pop happens, it only cares that the protocol's fundamental truth is never violated.
