#!/usr/bin/env python3
"""
Single entry point for the Phase 2 verification-agent pipeline.

This script runs the full workflow:
1. Generate a testbench with agent.py
2. Re-run standalone simulation with run_sim.py for reproducible reporting
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def run_command(cmd: list[str]) -> None:
    result = subprocess.run(cmd)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the full verification-agent pipeline.")
    parser.add_argument("--problem-dir", required=True, help="Problem directory containing specification and mutant_*.v files")
    parser.add_argument("--max-iters", type=int, default=1, help="Maximum agent refinement iterations")
    parser.add_argument("--model", default=None, help="Optional Codex model override")
    args = parser.parse_args()

    problem_name = Path(args.problem_dir).name
    tb_path = Path("tb") / f"{problem_name}_tb.v"

    agent_cmd = ["python3", "agent.py", "--problem-dir", args.problem_dir, "--max-iters", str(args.max_iters)]
    if args.model:
        agent_cmd.extend(["--model", args.model])
    run_command(agent_cmd)

    run_command([
        "python3",
        "run_sim.py",
        "--problem-dir",
        args.problem_dir,
        "--tb",
        str(tb_path),
    ])


if __name__ == "__main__":
    main()
