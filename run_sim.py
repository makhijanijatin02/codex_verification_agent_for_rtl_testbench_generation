#!/usr/bin/env python3
"""
run_sim.py - Concrete simulation entry point for the verification agent workspace.

Compiles and runs a generated testbench against all mutant RTL implementations in a
problem directory, then writes a JSON summary under artifacts/.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from simulator import Simulator, compute_score


def run_sim(problem_dir: str, tb_path: str, output_json: str | None = None) -> dict:
    problem_path = Path(problem_dir)
    tb_file = Path(tb_path)

    if not problem_path.exists():
        raise FileNotFoundError(f"Problem directory not found: {problem_dir}")
    if not tb_file.exists():
        raise FileNotFoundError(f"Testbench not found: {tb_path}")

    simulator = Simulator(timeout_seconds=30)
    results = simulator.run_all_mutants(str(tb_file), str(problem_path))
    score_info = compute_score(results)

    payload = {
        "problem_dir": str(problem_path),
        "tb_path": str(tb_file),
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
    }

    json_path = Path(output_json) if output_json else Path("artifacts") / problem_path.name / "run_sim_results.json"
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2))

    print(f"Problem: {problem_path.name}")
    print(f"Testbench: {tb_file}")
    print(f"Score: {score_info['score']:.4f}")
    print(f"Passing: {score_info['num_passing']}/{score_info['num_total']}")
    print(f"Results JSON: {json_path}")

    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the generated verification testbench against all mutants.")
    parser.add_argument("--problem-dir", required=True, help="Problem directory containing mutant_*.v")
    parser.add_argument("--tb", required=True, help="Path to generated Verilog testbench")
    parser.add_argument("--output-json", default=None, help="Optional JSON output path")
    args = parser.parse_args()

    run_sim(args.problem_dir, args.tb, args.output_json)


if __name__ == "__main__":
    main()
