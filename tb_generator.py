"""
tb_generator.py - Use an LLM backend to generate Verilog testbenches from
specs and test plans.
"""

import json
import collections
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
        "oracle_style": test_plan.get("oracle_style"),
        "exhaustive_possible": test_plan.get("exhaustive_possible"),
        "total_input_bits": test_plan.get("total_input_bits"),
        "key_discriminators": test_plan.get("key_discriminators", []),
        "safe_checks": test_plan.get("safe_checks", [])[:8],
        "unsafe_checks": test_plan.get("unsafe_checks", [])[:8],
        "minimal_safe_oracle": test_plan.get("minimal_safe_oracle", [])[:8],
        "random_tests": test_plan.get("random_tests", {}),
        "reset_tests": test_plan.get("reset_tests", [])[:3],
        "normal_tests": test_plan.get("normal_tests", [])[:3],
        "corner_case_tests": test_plan.get("corner_case_tests", [])[:5],
        "sequence_tests": test_plan.get("sequence_tests", [])[:4],
    }
    return {k: v for k, v in summary.items() if v not in (None, [], {})}


def _is_protocol_heavy_module(parsed_spec: dict, test_plan: dict) -> bool:
    """
    Detect FIFO/CDC/credit/handshake-style modules that need a more conservative
    instruction set than datapath-oriented modules.
    """
    if parsed_spec.get("oracle_style") == "protocol_invariant" or test_plan.get("oracle_style") == "protocol_invariant":
        return True

    text_fields = [
        parsed_spec.get("module_name", ""),
        parsed_spec.get("behavior_summary", ""),
        " ".join(parsed_spec.get("edge_cases", [])),
        " ".join(parsed_spec.get("priorities", [])),
        " ".join(parsed_spec.get("mutation_risks", [])),
        " ".join(test_plan.get("key_discriminators", [])),
    ]
    haystack = " ".join(text_fields).lower()
    keywords = (
        "fifo",
        "cdc",
        "credit",
        "handshake",
        "backpressure",
        "ready/valid",
        "push",
        "pop",
        "synchronizer",
        "clock domain",
    )
    return any(keyword in haystack for keyword in keywords)


def get_testbench_prompt_name(parsed_spec: dict, test_plan: dict) -> str:
    """Select the instruction set to use for this problem class."""
    module_name = str(parsed_spec.get("module_name", "")).lower()
    if module_name == "fifo_flops":
        return "gen_testbench_fifo_flops"
    if module_name == "cdc_fifo_flops_push_credit":
        return "gen_testbench_cdc_fifo_push_credit"
    return "gen_testbench_protocol" if _is_protocol_heavy_module(parsed_spec, test_plan) else "gen_testbench"


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

    def _signal_names_from_ports(sig_type: str) -> list[str]:
        names = []
        for port in parsed_spec.get("ports", []):
            if port.get("direction") == "input" and str(port.get("type", "")).lower() == sig_type:
                name = str(port.get("name", "")).strip()
                if name:
                    names.append(name)
        return names

    # Prefer explicit clock/reset ports from the parsed interface when present.
    clock_names_list = _signal_names_from_ports("clock")
    reset_names_list = _signal_names_from_ports("reset")

    # Fall back to splitting the parsed string fields when typed ports were not extracted cleanly.
    if not clock_names_list:
        clock_names_list = re.findall(r'[A-Za-z_][A-Za-z0-9_]*', str(clock_name))
    if not reset_names_list:
        reset_names_list = re.findall(r'[A-Za-z_][A-Za-z0-9_]*', str(reset_name))

    # Remove accidental connector words if they slipped through the fallback tokenizer.
    clock_names_list = [c for c in clock_names_list if c not in {"and", "or"}]
    reset_names_list = [r for r in reset_names_list if r not in {"and", "or"}]

    if not clock_names_list or not reset_names_list:
        return ""

    clock_edge_expr = " or ".join(f"posedge {c}" for c in clock_names_list)
    reset_edge_expr = " or ".join(f"posedge {r}" for r in reset_names_list)

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

    always @({clock_edge_expr}) begin
        tb_sync_reset_last_clock_edge = $time;
    end

    always @({reset_edge_expr}) begin
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


def _sanitize_variable_part_selects(verilog_code: str) -> str:
    """
    Rewrite common LLM-generated variable part-select patterns into indexed
    part-selects that Icarus Verilog accepts.
    """
    replacements = {
        r'(\b\w+\b)\s*=\s*(\b\w+\b)\s*\[\s*msb\s*:\s*lsb\s*\]\s*;': r'\1 = \2[lsb +: SYMBOL_W];',
        r'(\b\w+\b)\s*\[\s*msb\s*:\s*lsb\s*\]\s*=\s*(.+?);': r'\1[lsb +: SYMBOL_W] = \2;',
        r'(\b\w+\b)\s*=\s*(\b\w+\b)\s*\[\s*high\s*:\s*low\s*\]\s*;': r'\1 = \2[low +: SYMBOL_W];',
        r'(\b\w+\b)\s*\[\s*high\s*:\s*low\s*\]\s*=\s*(.+?);': r'\1[low +: SYMBOL_W] = \2;',
    }

    sanitized = verilog_code
    for pattern, replacement in replacements.items():
        sanitized = re.sub(pattern, replacement, sanitized)

    # Icarus does not accept slices of parenthesized expressions like
    # `(expr)[3:0]` or `(expr)[7:0]`. Replace the common low-slice cases with
    # explicit masking so repaired benches remain compilable.
    sanitized = re.sub(r'\(\s*([^()\n]+?)\s*\)\s*\[\s*3\s*:\s*0\s*\]', r'((\1) & 4\'hF)', sanitized)
    sanitized = re.sub(r'\(\s*([^()\n]+?)\s*\)\s*\[\s*7\s*:\s*0\s*\]', r'((\1) & 8\'hFF)', sanitized)
    return sanitized


def _sanitize_reserved_helper_names(verilog_code: str) -> str:
    """
    Rewrite helper task names that can collide with SystemVerilog keywords or
    parser-sensitive identifiers in Icarus.
    """
    sanitized = verilog_code
    sanitized = re.sub(r'\btask\s+expect\b', 'task tb_expect', sanitized)
    sanitized = re.sub(r'\bendtask\s*:\s*expect\b', 'endtask : tb_expect', sanitized)
    sanitized = re.sub(r'\bexpect\s*\(', 'tb_expect(', sanitized)
    return sanitized


def _strip_duplicate_code_fences(verilog_code: str) -> str:
    stripped = verilog_code.strip()
    if stripped.startswith("```"):
        return extract_verilog(stripped)
    return verilog_code


def find_protocol_testbench_issues(verilog_code: str, parsed_spec: dict, test_plan: dict) -> list[str]:
    """
    Detect unsafe generated structures for protocol-heavy modules.
    These are guardrails only; they do not provide replacement testbench code.
    """
    if not _is_protocol_heavy_module(parsed_spec, test_plan):
        return []

    issues = []
    lower = verilog_code.lower()
    module_name = str(parsed_spec.get("module_name", "")).lower()

    pattern_checks = [
        ("timeout waiting", "contains explicit timeout-wait failure logic"),
        ("wait_for_", "contains wait_for-style helper tasks that usually encode bounded convergence assumptions"),
        ("max_cycles", "contains max_cycles-bounded protocol wait logic"),
        ("wait_cycles", "contains bounded wait-cycle helper logic for protocol convergence"),
        ("while (1'b1)", "contains open-ended polling loop structure"),
        ("observed_credit_pulses", "tracks exact credit pulse counts"),
        ("expected_credit_pulses", "expects exact credit pulse totals"),
    ]

    for needle, message in pattern_checks:
        if needle in lower:
            issues.append(message)

    if "push_slots" in lower and ("check_eq5(push_slots" in lower or "wait_for_push_slots" in lower):
        issues.append("asserts exact push_slots behavior")
    if "pop_items" in lower and ("check_eq5(pop_items" in lower or "wait_for_pop_items" in lower):
        issues.append("asserts exact pop_items behavior")
    if "credit_count_push" in lower and "check_eq5(credit_count_push" in lower:
        issues.append("asserts exact credit_count_push behavior")
    if "credit_available_push" in lower and "check_eq5(credit_available_push" in lower:
        issues.append("asserts exact credit_available_push behavior")
    if "credit_available must be" in lower or "credit_available mismatch" in lower:
        issues.append("asserts exact credit_available truth-table behavior")
    if 'check_bit("credit_available' in lower or "check_bit(\"credit_available" in lower:
        issues.append("uses exact credit_available equality checks")
    if "push_credit must be 1 when one credit is available" in lower:
        issues.append("asserts exact push_credit behavior from reconstructed credit arithmetic")
    if 'check_bit("push_credit' in lower or "check_bit(\"push_credit" in lower:
        if "available" in lower or "withhold" in lower or "empty/unwithheld" in lower or "full/unwithheld" in lower:
            issues.append("uses exact push_credit equality checks derived from reconstructed credit state")
    if "push_credit must equal !reset && !stall && (credit_available != 0)" in lower:
        issues.append("uses global push_credit equivalence derived from credit_available")
    fifo_exact_status_needles = (
        "current items mismatch",
        "current slots mismatch",
        "items_next mismatch",
        "slots_next mismatch",
        "current items+slots must equal 13",
        "next items+slots must equal 13",
        "items !== model_occ",
        "slots !== (13 - model_occ)",
        "items_next !==",
        "slots_next !==",
    )
    if any(needle in lower for needle in fifo_exact_status_needles):
        issues.append("asserts exact per-cycle FIFO status/count equality")
    fifo_empty_edge_needles = (
        "pop_valid must be 0 when empty without bypass",
        "empty non-bypass: pop_valid must be 0",
        "empty without bypass",
        "bypass pop_valid must be 1",
        "bypass pop_data mismatch",
    )
    if any(needle in lower for needle in fifo_empty_edge_needles):
        issues.append("asserts exact same-cycle empty-edge FIFO behavior")
    if "accepted pop returns oldest buffered byte" in lower:
        issues.append("checks buffered pop data after the accepting edge instead of on the handshake cycle")
    if "reset items_next" in lower or "reset slots_next" in lower or "reset empty_next" in lower or "reset full_next" in lower:
        issues.append("asserts *_next predictor values during reset")
    if "synchronous" in " ".join(parsed_spec.get("guaranteed_properties", [])).lower():
        sync_reset_needles = (
            "during reset expected",
            "check_reset_outputs();",
            "if (rst_i) begin\n        check_reset_outputs();",
        )
        if "check_reset_outputs" in lower and "before the active" not in lower:
            if any(needle in lower for needle in sync_reset_needles):
                issues.append("checks synchronous reset outputs before the qualifying clock edge")
    cdc_counter_needles = (
        "credit_available_push inconsistent",
        "credit_count_push",
        "push_slots out of legal range",
        "pop_items out of legal range",
    )
    if sum(1 for needle in cdc_counter_needles if needle in lower) >= 2:
        issues.append("uses exact CDC-side counter/status checking")

    forbidden_assumptions = " ".join(parsed_spec.get("forbidden_assumptions", [])).lower()
    if "exact latency" in forbidden_assumptions and ("max_cycles" in lower or "wait_for_" in lower):
        issues.append("uses bounded wait logic despite forbidden exact-latency assumptions")
    if "exact counter" in forbidden_assumptions:
        if "credit_count_push" in lower or "credit_available_push" in lower or "push_slots" in lower or "pop_items" in lower:
            issues.append("references exact counter/status behavior despite forbidden counter assumptions")

    if module_name == "fifo_flops":
        required_sections = (
            "reset_idle_checks",
            "empty_bypass_checks",
            "one_item_store_and_idle_checks",
            "one_item_pop_next_checks",
            "buffered_ordering_checks",
            "twelve_to_thirteen_next_checks",
            "full_idle_checks",
        )
        for section in required_sections:
            if section not in lower:
                issues.append(f"fifo_flops bench missing required section: {section}")

        fifo_forbidden_needles = (
            "empty non-bypass: pop_valid must be 0",
            "accepted pop returns oldest buffered byte",
            "reset items_next",
            "reset slots_next",
            "reset empty_next",
            "reset full_next",
            "check_pre_general",
            "check_stable_state",
            "check_status_count",
            "global scoreboard",
        )
        for needle in fifo_forbidden_needles:
            if needle in lower:
                issues.append(f"fifo_flops bench contains forbidden check: {needle}")

    if module_name == "cdc_fifo_flops_push_credit":
        def _section_body(start_label: str, end_label: str | None) -> str:
            start = lower.find(start_label)
            if start == -1:
                return ""
            start += len(start_label)
            end = lower.find(end_label, start) if end_label else -1
            return lower[start:] if end == -1 else lower[start:end]

        required_sections = (
            "PUSH_RESET_IDLE_CHECKS".lower(),
            "POP_RESET_IDLE_CHECKS".lower(),
            "PUSH_SENDER_RESET_HANDSHAKE_CHECKS".lower(),
            "SINGLE_TRANSFER_CHECKS".lower(),
            "BACKPRESSURE_HOLD_CHECKS".lower(),
            "FIFO_ORDERING_CHECKS".lower(),
            "FILL_AND_DRAIN_CHECKS".lower(),
            "STALL_BLOCKING_CHECKS".lower(),
        )
        for section in required_sections:
            if section not in lower:
                issues.append(f"cdc bench missing required section: {section}")

        cdc_forbidden_needles = (
            "one-cycle delayed effective push reset",
            "prev_push_reset_req",
            "expected_push_reset",
            "push_receiver_in_reset did not match delayed push-side reset state",
            "push_receiver_in_reset violated one-cycle delayed push reset behavior",
            "push_receiver_in_reset === expected_push_reset",
            "push_receiver_in_reset !== expected_push_reset",
            "push_receiver_in_reset did not follow one-cycle delayed push reset condition",
            "push_receiver_in_reset did not assert after sustained write-side reset",
            "push_receiver_in_reset did not deassert",
            "push_receiver_in_reset did not assert",
            "follow one-cycle delayed push reset",
            "delayed push-side reset",
            "delayed push reset",
            "pending_credits",
            "credit pulse had no matching completed pop",
            "credit pulses exceeded completed pops",
            "completed pops exceeded credit pulses",
            "observed more push_credit pulses than completed pops",
            "push_credit pulse wider than one push_clk cycle",
            "credit_edges",
            "observed_credit_pulses",
            "pending_credits",
            "last_push_credit",
            "prev_push_credit",
            "pop_valid not cleared by registered pop_rst",
            "wrong readable data before asserting pop_rst",
            "pop_valid should be low after reset settling",
            "pop_valid must be 0 while effective pop reset is active",
            "expected item did not become visible on pop side",
            "pre-edge pop_data did not match expected value",
            "expected pop_valid before directed pop",
            "expected pop_valid before scoreboard pop",
            "one-for-one",
            "credit_count_push",
            "credit_available_push",
            "push_slots",
            "pop_items",
            "wait_for_",
            "max_cycles",
            "timeout waiting",
        )
        for needle in cdc_forbidden_needles:
            if needle in lower:
                issues.append(f"cdc bench contains forbidden check: {needle}")

        if "push_receiver_in_reset" in lower and "expect" in lower:
            issues.append("cdc bench uses push_receiver_in_reset as a direct expected-value oracle")
        if "push_receiver_in_reset" in lower and ("==" in lower or "!=" in lower) and "reset" in lower:
            issues.append("cdc bench compares push_receiver_in_reset to reset conditions too directly")
        if "expect_eventual_visible_data(" in lower:
            issues.append("cdc bench requires pop-side visibility before actual pop handshakes")
        if "credit_pulse_count" in lower and "pop_handshake_count" in lower and (">" in lower or "<" in lower or "!=" in lower):
            issues.append("cdc bench compares aggregate credit pulses against aggregate pop handshakes")
        if "prev_push_credit" in lower and "push_credit" in lower:
            issues.append("cdc bench monitors push_credit as if it must be a one-cycle pulse")
        if any(name in lower for name in ("credit_edges", "observed_credit_pulses", "pending_credits")):
            issues.append("cdc bench uses aggregate credit-accounting state instead of legality/eventuality checks")

        push_reset_body = _section_body("// push_reset_idle_checks", "// pop_reset_idle_checks")
        if (
            "push_expect_accept" in push_reset_body
            and "push_rst = 1'b1" in push_reset_body
            and "pop_expect_head" in push_reset_body
        ):
            issues.append("cdc bench assumes data accepted before push_rst must survive and pop after push-side reset")

        sender_reset_body = _section_body("// push_sender_reset_handshake_checks", "// single_transfer_checks")
        if (
            "push_expect_accept" in sender_reset_body
            and "push_sender_in_reset = 1'b1" in sender_reset_body
            and "pop_expect_head" in sender_reset_body
        ):
            issues.append("cdc bench assumes data accepted before push_sender_in_reset must survive and pop after sender-reset phase")

    return issues


def enforce_spec_guards(verilog_code: str, parsed_spec: dict) -> str:
    """Add deterministic monitors for behaviors that the LLM often misses."""
    verilog_code = _strip_duplicate_code_fences(verilog_code)
    verilog_code = _sanitize_variable_part_selects(verilog_code)
    verilog_code = _sanitize_reserved_helper_names(verilog_code)
    
    # Global scrub for invalid 'and' in sensitivity lists
    # e.g., 'always @(posedge push_clk and pop_clk)' -> 'always @(posedge push_clk or posedge pop_clk)'
    verilog_code = re.sub(
        r'always\s*@\s*\(\s*posedge\s+([a-zA-Z0-9_]+)\s+and\s+([a-zA-Z0-9_]+)\s*\)',
        r'always @(posedge \1 or posedge \2)',
        verilog_code
    )
    
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
    system_prompt = load_prompt_template(get_testbench_prompt_name(parsed_spec, test_plan))
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
        "oracle_style": parsed_spec.get("oracle_style"),
        "executable_reference": parsed_spec.get("executable_reference", []),
        "guaranteed_properties": parsed_spec.get("guaranteed_properties", []),
        "ambiguous_properties": parsed_spec.get("ambiguous_properties", []),
        "forbidden_assumptions": parsed_spec.get("forbidden_assumptions", []),
        "edge_cases": parsed_spec.get("edge_cases", []),
        "priorities": parsed_spec.get("priorities", []),
        "mutation_risks": parsed_spec.get("mutation_risks", []),
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


def repair_testbench(
    llm_backend,
    spec_text: str,
    parsed_spec: dict,
    test_plan: dict,
    module_header: str,
    testbench_code: str,
    compile_error: str,
) -> str:
    """Ask the LLM to repair a previously generated testbench after compile failure."""
    system_prompt = load_prompt_template("repair_testbench")
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
        "oracle_style": parsed_spec.get("oracle_style"),
        "executable_reference": parsed_spec.get("executable_reference", []),
        "guaranteed_properties": parsed_spec.get("guaranteed_properties", []),
        "ambiguous_properties": parsed_spec.get("ambiguous_properties", []),
        "forbidden_assumptions": parsed_spec.get("forbidden_assumptions", []),
        "edge_cases": parsed_spec.get("edge_cases", []),
        "priorities": parsed_spec.get("priorities", []),
        "mutation_risks": parsed_spec.get("mutation_risks", []),
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

## Module Header
```verilog
{module_header}
```

## Current Testbench
```verilog
{testbench_code[:5000]}
```

## Icarus Compile Error
{compile_error[:2000]}
"""

    raw = llm_backend.complete(
        system_prompt,
        user_content,
        temperature=0.1,
        want_json=False,
    )
    return enforce_spec_guards(extract_verilog(raw), parsed_spec)


def build_failure_feedback(sim_results: list, iteration: int, focus_on_dominant_failure: bool = False) -> str:
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

    if len(passing) == 0 and len(failing) > 0:
        feedback += (
            "### All Mutants Failed\n"
            "The generated testbench is likely over-constraining behavior or using an incorrect "
            "timing/reference model. Re-check sequential timing, mid-cycle assertions, and whether "
            "manual precondition checks accidentally consume an extra clock edge.\n\n"
        )
        if focus_on_dominant_failure:
            first_lines = [
                r.sim_output.splitlines()[0].strip()
                for r in failing
                if r.sim_output and r.sim_output.splitlines()
            ]
            if first_lines:
                counts = collections.Counter(first_lines)
                dominant_message, dominant_count = counts.most_common(1)[0]
                feedback += (
                    "### Dominant failing symptom\n"
                    f"- `{dominant_message}`\n"
                    f"- observed in `{dominant_count}` compiled mutants\n\n"
                    "Revise the testbench by removing or weakening the single assumption most directly "
                    "responsible for this dominant failure. Preserve all other safer checks if possible.\n\n"
                )
        else:
            feedback += "### Sample failing output\n"
            feedback += f"```\n{failing[0].sim_output[:1000]}\n```\n"

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
