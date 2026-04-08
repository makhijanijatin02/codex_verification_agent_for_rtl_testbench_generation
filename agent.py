#!/usr/bin/env python3
"""
agent.py - Main verification agent loop.

Reads a natural-language RTL specification and candidate Verilog implementations,
generates a discriminating testbench using an LLM, and iteratively refines it
based on simulation feedback.

Usage:
    python agent.py --problem-dir path/to/problem [--max-iters 5] [--model gpt-5-codex]
    python agent.py --batch path/to/problems_root  # Run on all problems

Environment (set in .env file):
    CODEX_MODEL    - Codex model for the CLI provider (optional)
    CODEX_CLI_COMMAND - Launcher for Codex CLI (default: "codex exec")
"""

import argparse
import json
import os
import sys
import time
import tempfile
from pathlib import Path

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent))

# Stream progress logs immediately even when stdout/stderr are redirected.
for stream_name in ("stdout", "stderr"):
    stream = getattr(sys, stream_name, None)
    reconfigure = getattr(stream, "reconfigure", None)
    if callable(reconfigure):
        reconfigure(line_buffering=True)

# Load .env file automatically
def load_dotenv():
    """Load environment variables from .env file in the project root."""
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    key = key.strip()
                    value = value.strip()
                    # Don't override existing env vars
                    if key not in os.environ:
                        os.environ[key] = value

load_dotenv()

from llm_backend import create_backend, get_default_model
from spec_parser import parse_specification, build_test_plan
from tb_generator import generate_testbench, extract_module_header, build_failure_feedback
from simulator import Simulator, compute_score


def write_json(path: Path, data: dict | list) -> None:
    """Write JSON output, creating parent directories as needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2))


def prepare_output_paths(problem_name: str, output_dir: str | None) -> tuple[Path, Path]:
    """
    Return concrete output locations that match the template-style agent workspace.

    - Testbenches live under ./tb by default
    - Parsed artifacts/results live under ./artifacts/<problem_name>
    """
    root = Path(output_dir) if output_dir else Path(__file__).parent
    tb_root = root / "tb"
    artifacts_root = root / "artifacts" / problem_name
    tb_root.mkdir(parents=True, exist_ok=True)
    artifacts_root.mkdir(parents=True, exist_ok=True)
    return tb_root / f"{problem_name}_tb.v", artifacts_root


def load_problem(problem_dir: str) -> dict:
    """
    Load a problem from the ICLAD benchmark directory structure.

    Expected structure:
        problem_dir/
        ├── specification.md (or spec.md, spec.txt, *.yaml)
        └── mutant_0.v ... mutant_30.v

    Returns:
        Dictionary with spec_text, mutant_files, problem_name
    """
    pdir = Path(problem_dir)
    if not pdir.exists():
        raise FileNotFoundError(f"Problem directory not found: {problem_dir}")

    # Find specification file
    spec_candidates = list(pdir.glob("specification*")) + \
                      list(pdir.glob("spec*")) + \
                      list(pdir.glob("*.yaml")) + \
                      list(pdir.glob("*.yml"))
    spec_text = ""
    for candidate in spec_candidates:
        if candidate.is_file():
            spec_text = candidate.read_text()
            print(f"  Loaded spec from: {candidate.name}")
            break

    if not spec_text:
        raise FileNotFoundError(f"No specification file found in {problem_dir}")

    # Find mutant files
    mutant_files = sorted(
        pdir.glob("mutant_*.v"),
        key=lambda p: int(p.stem.split("_")[1])
    )

    if not mutant_files:
        # Check subdirectories (some repos put RTL in a subfolder)
        for subdir in pdir.iterdir():
            if subdir.is_dir():
                mutant_files = sorted(
                    subdir.glob("mutant_*.v"),
                    key=lambda p: int(p.stem.split("_")[1])
                )
                if mutant_files:
                    break

    if not mutant_files:
        raise FileNotFoundError(f"No mutant_*.v files found in {problem_dir}")

    # Read a sample mutant for module header extraction
    sample_rtl = mutant_files[0].read_text()

    return {
        "problem_name": pdir.name,
        "spec_text": spec_text,
        "mutant_files": [str(f) for f in mutant_files],
        "mutants_dir": str(mutant_files[0].parent),
        "sample_rtl": sample_rtl,
        "num_mutants": len(mutant_files),
    }


def run_agent(problem_dir: str, provider: str = "codex-cli", model: str = None,
              max_iterations: int = 5, output_dir: str = None) -> dict:
    """
    Run the full verification agent on a single problem.

    Args:
        problem_dir: Path to the problem directory
        provider: LLM backend provider name
        model: LLM model to use
        max_iterations: Maximum refinement iterations
        output_dir: Where to save generated testbench (default: problem_dir)

    Returns:
        Dictionary with final score and details
    """
    start_time = time.time()

    print(f"\n{'='*60}")
    print(f"VERIFICATION AGENT - Starting")
    print(f"{'='*60}")

    # Step 1: Load problem
    print(f"\n[1/5] Loading problem from {problem_dir}...")
    problem = load_problem(problem_dir)
    print(f"  Problem: {problem['problem_name']}")
    print(f"  Mutants: {problem['num_mutants']}")
    tb_path, artifacts_dir = prepare_output_paths(problem["problem_name"], output_dir)

    # Step 2: Initialize LLM backend
    if model is None:
        model = get_default_model(provider)
    model_label = model or "provider default"
    print(f"\n[2/5] Initializing LLM backend ({provider}, model={model_label})...")
    llm_backend = create_backend(provider, model=model, cwd=str(Path(__file__).parent))

    # Step 3: Parse specification
    print(f"\n[3/5] Parsing specification...")
    module_header = extract_module_header(problem["sample_rtl"])

    parsed_spec = parse_specification(
        llm_backend,
        problem["spec_text"],
        rtl_samples=[(Path(problem["mutant_files"][0]).name, problem["sample_rtl"])]
    )
    print(f"  Module: {parsed_spec.get('module_name', 'unknown')}")
    print(f"  Sequential: {parsed_spec.get('is_sequential', 'unknown')}")
    print(f"  Edge cases found: {len(parsed_spec.get('edge_cases', []))}")
    write_json(artifacts_dir / "parsed_spec.json", parsed_spec)

    # Step 4: Build test plan
    print(f"\n[4/5] Building test plan...")
    test_plan = build_test_plan(llm_backend, parsed_spec)
    print(f"  Reset tests: {len(test_plan.get('reset_tests', []))}")
    print(f"  Normal tests: {len(test_plan.get('normal_tests', []))}")
    print(f"  Corner cases: {len(test_plan.get('corner_case_tests', []))}")
    write_json(artifacts_dir / "test_plan.json", test_plan)

    # Step 5: Iterative generate-simulate-refine loop
    print(f"\n[5/5] Starting generate-simulate-refine loop (max {max_iterations} iterations)...")

    simulator = Simulator(timeout_seconds=30)

    best_score = 0.0
    best_tb = None
    previous_tb = None
    failure_feedback = None
    latest_score_info = None

    for iteration in range(1, max_iterations + 1):
        elapsed = time.time() - start_time
        print(f"\n--- Iteration {iteration}/{max_iterations} (elapsed: {elapsed:.1f}s) ---")

        # Check 5-minute timeout
        if elapsed > 270:  # 4.5 min safety margin
            print("  WARNING: Approaching 5-minute timeout. Stopping.")
            break

        # Generate testbench
        print(f"  Generating testbench...")
        tb_code = generate_testbench(
            llm_backend,
            problem["spec_text"],
            parsed_spec,
            test_plan,
            module_header=module_header,
            previous_tb=previous_tb,
            failure_feedback=failure_feedback
        )

        # Save testbench
        tb_path.write_text(tb_code)
        print(f"  Saved testbench to {tb_path} ({len(tb_code)} chars)")

        # Run simulation against all mutants
        print(f"  Running simulations against {problem['num_mutants']} mutants...")
        work_dir = tempfile.mkdtemp(prefix=f"iter{iteration}_")

        try:
            results = simulator.run_all_mutants(tb_path, problem["mutants_dir"], work_dir)
        except Exception as e:
            print(f"  ERROR in simulation: {e}")
            failure_feedback = f"Simulation error: {e}. The testbench likely has syntax errors."
            previous_tb = tb_code
            continue

        # Compute score
        score_info = compute_score(results)
        latest_score_info = score_info
        score = score_info["score"]
        print(f"\n  Score: {score:.4f}")
        print(f"  Passing: {score_info['num_passing']}/{score_info['num_total']}")
        print(f"  Compile errors: {score_info['num_compile_errors']}")
        write_json(artifacts_dir / f"iteration_{iteration}_results.json", {
            "iteration": iteration,
            "score_info": score_info,
            "simulation_results": [
                {
                    "mutant_name": r.mutant_name,
                    "compiled": r.compiled,
                    "passed": r.passed,
                    "compile_error": r.compile_error,
                    "sim_output": r.sim_output,
                }
                for r in results
            ],
        })

        # Track best
        if score > best_score:
            best_score = score
            best_tb = tb_code
            print(f"  NEW BEST SCORE: {best_score:.4f}")

        # Perfect score - stop early
        if score == 1.0:
            print(f"  PERFECT SCORE! Only 1 mutant passes. Stopping.")
            break

        # Prepare feedback for next iteration
        previous_tb = tb_code
        failure_feedback = build_failure_feedback(results, iteration)

    # Save best testbench
    if best_tb and best_tb != tb_code:
        tb_path.write_text(best_tb)
        print(f"\nRestored best testbench (score={best_score:.4f})")

    total_time = time.time() - start_time

    result = {
        "problem_name": problem["problem_name"],
        "best_score": best_score,
        "iterations_used": iteration,
        "total_time_seconds": total_time,
        "num_mutants": problem["num_mutants"],
        "testbench_path": str(tb_path),
        "artifacts_dir": str(artifacts_dir),
        "score_info": latest_score_info,
    }
    write_json(artifacts_dir / "final_result.json", result)

    print(f"\n{'='*60}")
    print(f"FINAL RESULT: {problem['problem_name']}")
    print(f"  Best Score: {best_score:.4f}")
    print(f"  Iterations: {iteration}")
    print(f"  Time: {total_time:.1f}s")
    print(f"  Testbench: {tb_path}")
    print(f"{'='*60}")

    return result


def run_batch(problems_root: str, model: str = None,
              provider: str = "codex-cli", max_iterations: int = 5) -> list:
    """
    Run the agent on all problems in a directory.

    Expected structure:
        problems_root/
        ├── problem_1/
        │   ├── specification.md
        │   └── mutant_*.v
        ├── problem_2/
        │   └── ...
        └── ...
    """
    root = Path(problems_root)
    problem_dirs = sorted([
        d for d in root.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    ])

    print(f"Found {len(problem_dirs)} problems in {problems_root}")

    all_results = []
    for pdir in problem_dirs:
        try:
            result = run_agent(
                str(pdir), provider=provider, model=model, max_iterations=max_iterations
            )
            all_results.append(result)
        except Exception as e:
            print(f"\nERROR on {pdir.name}: {e}")
            all_results.append({
                "problem_name": pdir.name,
                "best_score": 0.0,
                "error": str(e),
            })

    # Summary
    print(f"\n{'='*60}")
    print("BATCH SUMMARY")
    print(f"{'='*60}")
    total_score = 0
    for r in all_results:
        score = r.get("best_score", 0)
        total_score += score
        status = "ERROR" if "error" in r else f"{score:.4f}"
        print(f"  {r['problem_name']:30s} {status}")

    avg_score = total_score / len(all_results) if all_results else 0
    print(f"\n  Average Score: {avg_score:.4f}")
    print(f"  Total Problems: {len(all_results)}")

    # Save results
    results_path = root / "results.json"
    with open(results_path, 'w') as f:
        json.dump(all_results, f, indent=2)
    print(f"\n  Results saved to: {results_path}")

    return all_results


def main():
    parser = argparse.ArgumentParser(
        description="AI Verification Agent - Generates discriminating Verilog testbenches"
    )
    parser.add_argument(
        "--problem-dir", type=str,
        help="Path to a single problem directory"
    )
    parser.add_argument(
        "--batch", type=str,
        help="Path to directory containing multiple problems"
    )
    parser.add_argument(
        "--model", type=str, default=None,
        help="Codex model name (default: CODEX_MODEL from .env)"
    )
    parser.add_argument(
        "--max-iters", type=int, default=5,
        help="Maximum refinement iterations (default: 5)"
    )
    parser.add_argument(
        "--output-dir", type=str, default=None,
        help="Directory to save generated testbench"
    )

    args = parser.parse_args()

    if not args.problem_dir and not args.batch:
        parser.print_help()
        print("\nERROR: Provide either --problem-dir or --batch")
        sys.exit(1)

    if args.batch:
        run_batch(
            args.batch,
            provider="codex-cli",
            model=args.model,
            max_iterations=args.max_iters,
        )
    else:
        run_agent(
            args.problem_dir,
            provider="codex-cli",
            model=args.model,
            max_iterations=args.max_iters,
            output_dir=args.output_dir
        )


if __name__ == "__main__":
    main()
