"""
spec_parser.py - Use an LLM backend to extract structured hardware behavior
from natural-language specs.
"""

import json
import re
from pathlib import Path


def load_prompt_template(template_name: str) -> str:
    """Load a prompt template from the prompts/ directory."""
    prompt_path = Path(__file__).parent / "prompts" / f"{template_name}.txt"
    if not prompt_path.exists():
        raise FileNotFoundError(f"Prompt template not found: {prompt_path}")
    return prompt_path.read_text()


def _parse_json_response(text: str) -> dict:
    """Parse JSON from LLM response, handling code blocks and raw JSON."""
    # Try direct parse first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try to extract from markdown code block
    json_match = re.search(r'```(?:json)?\s*([\s\S]*?)```', text)
    if json_match:
        try:
            return json.loads(json_match.group(1))
        except json.JSONDecodeError:
            pass

    # Try to find JSON object in the text
    brace_match = re.search(r'\{[\s\S]*\}', text)
    if brace_match:
        try:
            return json.loads(brace_match.group(0))
        except json.JSONDecodeError:
            pass

    return {"raw_response": text, "parse_error": True}


def parse_specification(llm_backend, spec_text: str,
                        rtl_samples: list = None) -> dict:
    """
    Use the LLM to extract structured behavior from a natural-language spec.

    Args:
        llm_backend: Backend implementing complete()
        spec_text: The raw specification text
        rtl_samples: Optional list of (filename, content) for module port info

    Returns:
        Dictionary with structured spec information
    """
    system_prompt = load_prompt_template("parse_spec")

    user_content = f"## Specification\n\n{spec_text}\n"

    if rtl_samples:
        user_content += "\n## RTL Reference (for port names and widths)\n\n"
        for fname, content in rtl_samples[:2]:
            user_content += f"### {fname}\n```verilog\n{content[:1500]}\n```\n\n"

    result_text = llm_backend.complete(
        system_prompt,
        user_content,
        temperature=0.2,
        want_json=True,
    )

    return _parse_json_response(result_text)


def build_test_plan(llm_backend, parsed_spec: dict) -> dict:
    """
    Generate a structured test plan from parsed spec information.

    Args:
        llm_backend: Backend implementing complete()
        parsed_spec: Output from parse_specification()

    Returns:
        Dictionary with categorized test vectors
    """
    system_prompt = load_prompt_template("gen_testplan")

    user_content = f"## Parsed Specification\n\n```json\n{json.dumps(parsed_spec, indent=2)}\n```"

    result_text = llm_backend.complete(
        system_prompt,
        user_content,
        temperature=0.3,
        want_json=True,
    )

    return _parse_json_response(result_text)
