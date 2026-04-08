"""
tb_generator.py - Use an LLM backend to generate Verilog testbenches from
specs and test plans.
"""

import json
import re
from spec_parser import load_prompt_template


def _compact_json(data: dict) -> str:
    """Serialize JSON compactly to keep LLM prompts smaller."""
    return json.dumps(data, separators=(",", ":"), sort_keys=True)


def _summarize_test_plan(test_plan: dict) -> dict:
    """
    Keep the most discriminating parts of the test plan while avoiding
    oversized prompts that can cause Codex CLI timeouts.
    """
    summary = {
        "module_type": test_plan.get("module_type"),
        "exhaustive_possible": test_plan.get("exhaustive_possible"),
        "total_input_bits": test_plan.get("total_input_bits"),
        "key_discriminators": test_plan.get("key_discriminators", []),
        "random_tests": test_plan.get("random_tests", {}),
        "reset_tests": test_plan.get("reset_tests", [])[:3],
        "normal_tests": test_plan.get("normal_tests", [])[:3],
        "corner_case_tests": test_plan.get("corner_case_tests", [])[:5],
        "sequence_tests": test_plan.get("sequence_tests", [])[:4],
    }
    return {k: v for k, v in summary.items() if v not in (None, [], {})}


def _build_sync_reset_guard(parsed_spec: dict) -> str:
    """
    Build a passive monitor that fails simulation if registered outputs change
    immediately when a synchronous active-high reset is asserted between clocks.
    """
    if parsed_spec.get("reset_type") != "sync_active_high":
        return ""

    clock_name = parsed_spec.get("clock_name")
    reset_name = parsed_spec.get("reset_name")
    output_behavior = parsed_spec.get("output_behavior", {})
    registered_outputs = output_behavior.get("registered_outputs", [])
    ports = {port.get("name"): port for port in parsed_spec.get("ports", [])}

    if not clock_name or not reset_name or not registered_outputs:
        return ""

    output_exprs = []
    total_width = 0
    for name in registered_outputs:
        port = ports.get(name)
        if not port or port.get("direction") != "output":
            continue
        width = int(port.get("width", 1) or 1)
        total_width += width
        output_exprs.append(name)

    if not output_exprs or total_width <= 0:
        return ""

    concat_expr = output_exprs[0] if len(output_exprs) == 1 else "{" + ", ".join(output_exprs) + "}"

    return f"""

    // Injected guard: synchronous reset must not change registered outputs
    // until the next active clock edge.
    reg [{total_width - 1}:0] tb_sync_reset_snapshot;
    time tb_sync_reset_last_clock_edge;

    initial tb_sync_reset_last_clock_edge = 0;

    always @(posedge {clock_name}) begin
        tb_sync_reset_last_clock_edge = $time;
    end

    always @(posedge {reset_name}) begin
        if (($time - tb_sync_reset_last_clock_edge) > 0) begin
            tb_sync_reset_snapshot = {concat_expr};
            #1;
            if ({concat_expr} !== tb_sync_reset_snapshot) begin
                $display("FAIL: synchronous reset changed registered outputs before clock edge at %0t", $time);
                $finish;
            end
        end
    end
"""


def _inject_before_endmodule(verilog_code: str, snippet: str) -> str:
    """Insert a snippet before the final endmodule if possible."""
    if not snippet:
        return verilog_code
    index = verilog_code.rfind("endmodule")
    if index == -1:
        return verilog_code + "\n" + snippet
    return verilog_code[:index] + snippet + "\n" + verilog_code[index:]


def enforce_spec_guards(verilog_code: str, parsed_spec: dict) -> str:
    """Add deterministic monitors for behaviors that the LLM often misses."""
    return _inject_before_endmodule(verilog_code, _build_sync_reset_guard(parsed_spec))


def generate_testbench(llm_backend, spec_text: str,
                       parsed_spec: dict, test_plan: dict,
                       module_header: str = None,
                       previous_tb: str = None,
                       failure_feedback: str = None) -> str:
    """
    Generate a complete Verilog testbench using the LLM.

    Args:
        llm_backend: Backend implementing complete()
        spec_text: Original spec text
        parsed_spec: Structured spec from spec_parser
        test_plan: Test plan from spec_parser
        module_header: Optional Verilog module header for port matching
        previous_tb: Optional previous testbench (for refinement iterations)
        failure_feedback: Optional feedback about which mutants still passed

    Returns:
        String containing the complete Verilog testbench code
    """
    system_prompt = load_prompt_template("gen_testbench")
    spec_summary = {
        "module_name": parsed_spec.get("module_name"),
        "ports": parsed_spec.get("ports", []),
        "has_clock": parsed_spec.get("has_clock"),
        "clock_name": parsed_spec.get("clock_name"),
        "has_reset": parsed_spec.get("has_reset"),
        "reset_name": parsed_spec.get("reset_name"),
        "reset_type": parsed_spec.get("reset_type"),
        "is_sequential": parsed_spec.get("is_sequential"),
        "behavior_summary": parsed_spec.get("behavior_summary"),
        "edge_cases": parsed_spec.get("edge_cases", []),
        "priorities": parsed_spec.get("priorities", []),
        "output_behavior": parsed_spec.get("output_behavior", {}),
    }
    plan_summary = _summarize_test_plan(test_plan)

    user_content = f"""## Original Specification
{spec_text}

## Parsed Behavior (JSON)
```json
{_compact_json(spec_summary)}
```

## Test Plan
```json
{_compact_json(plan_summary)}
```
"""

    if module_header:
        user_content += f"\n## Module Header (from RTL)\n```verilog\n{module_header}\n```\n"

    if previous_tb and failure_feedback:
        user_content += f"""
## Previous Testbench (needs improvement)
```verilog
{previous_tb[:4000]}
```

## Failure Feedback
{failure_feedback[:2000]}

IMPORTANT: The previous testbench was not discriminating enough. Analyze the feedback
and add stronger test cases that target the specific behaviors where mutants are passing
incorrectly. Focus on edge cases, timing, and corner conditions.
"""

    raw = llm_backend.complete(
        system_prompt,
        user_content,
        temperature=0.2,
        want_json=False,
    )

    # Extract Verilog code from response
    verilog_code = extract_verilog(raw)

    return enforce_spec_guards(verilog_code, parsed_spec)


def extract_verilog(text: str) -> str:
    """Extract Verilog code from LLM response (handles markdown code blocks)."""

    # Try to find verilog code block
    patterns = [
        r'```verilog\s*([\s\S]*?)```',
        r'```v\s*([\s\S]*?)```',
        r'```\s*([\s\S]*?)```',
    ]

    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            code = match.group(1).strip()
            # Verify it looks like Verilog
            if 'module' in code or '`timescale' in code or 'initial' in code:
                return code

    # If no code block found, check if the whole response is Verilog
    if 'module' in text or '`timescale' in text:
        # Strip any non-code preamble
        lines = text.split('\n')
        code_lines = []
        in_code = False
        for line in lines:
            if '`timescale' in line or 'module' in line:
                in_code = True
            if in_code:
                code_lines.append(line)
        if code_lines:
            return '\n'.join(code_lines)

    return text  # Return as-is if we can't parse it


def extract_module_header(rtl_content: str) -> str:
    """Extract the module declaration from a Verilog file."""
    # Match module ... endmodule or just the port declaration
    match = re.search(
        r'(module\s+\w+\s*(?:#\s*\([\s\S]*?\))?\s*\([\s\S]*?\)\s*;)',
        rtl_content
    )
    if match:
        return match.group(1)

    # Simpler pattern
    match = re.search(r'(module\s+\w+[\s\S]*?;)', rtl_content)
    if match:
        return match.group(1)

    return ""


def build_failure_feedback(sim_results: list, iteration: int) -> str:
    """
    Build feedback string from simulation results for the LLM.

    Args:
        sim_results: List of SimulationResult objects
        iteration: Current iteration number

    Returns:
        Formatted feedback string
    """
    passing = [r for r in sim_results if r.passed]
    failing = [r for r in sim_results if not r.passed and r.compiled]
    compile_errors = [r for r in sim_results if not r.compiled]

    feedback = f"## Iteration {iteration} Results\n\n"
    feedback += f"- **{len(passing)} mutants PASSED** (should ideally be 1)\n"
    feedback += f"- **{len(failing)} mutants FAILED** (good)\n"
    feedback += f"- **{len(compile_errors)} compile errors**\n\n"

    if compile_errors:
        feedback += "### Compile Errors\n"
        for r in compile_errors[:3]:  # Show up to 3
            feedback += f"**{r.mutant_name}**: {r.compile_error[:500]}\n\n"

    if len(passing) > 1:
        feedback += f"### Mutants that still PASS (need to be caught)\n"
        for r in passing:
            feedback += f"- {r.mutant_name}\n"
        feedback += "\nThe testbench needs additional test cases to distinguish these.\n"

        # Include sample output from a passing mutant for the LLM to analyze
        if passing:
            feedback += f"\n### Sample output from {passing[0].mutant_name}:\n"
            feedback += f"```\n{passing[0].sim_output[:1000]}\n```\n"

    return feedback
