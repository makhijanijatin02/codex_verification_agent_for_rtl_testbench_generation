#!/usr/bin/env python3
"""
Phase 3 pipeline entry point.

Supports:
1. Single-problem execution
2. Batch visible-benchmark execution with aggregate metrics
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from agent import run_agent
from run_sim import run_sim


def _write_json(path: Path, payload: dict | list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def _write_markdown_summary(path: Path, rows: list[dict], average_score: float) -> None:
    lines = [
        "# Batch Benchmark Summary",
        "",
        "| Problem | Agent Score | Passing | Compile Errors | Runtime (s) |",
        "|---------|------------:|--------:|---------------:|------------:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['problem_name']} | {row['score']:.4f} | "
            f"{row['num_passing']}/{row['num_total']} | "
            f"{row['num_compile_errors']} | {row['runtime_seconds']:.1f} |"
        )
    lines.extend([
        "",
        f"- Average score: `{average_score:.4f}`",
        f"- Problems evaluated: `{len(rows)}`",
    ])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def run_single_problem(problem_dir: str, max_iters: int, model: str | None) -> dict:
    problem_name = Path(problem_dir).name
    tb_path = Path("tb") / f"{problem_name}_tb.v"

    agent_result = run_agent(
        problem_dir,
        provider="codex-cli",
        model=model,
        max_iterations=max_iters,
    )
    sim_result = run_sim(problem_dir, str(tb_path))
    return {
        "agent_result": agent_result,
        "simulation_result": sim_result,
    }


def run_batch(root_dir: str, max_iters: int, model: str | None) -> dict:
    root = Path(root_dir)
    problem_dirs = sorted([p for p in root.iterdir() if p.is_dir() and not p.name.startswith(".")])
    if not problem_dirs:
        raise FileNotFoundError(f"No problem directories found in {root_dir}")

    rows = []
    raw_results = []

    for problem_dir in problem_dirs:
        print(f"\n{'=' * 72}")
        print(f"PIPELINE BATCH RUN: {problem_dir.name}")
        print(f"{'=' * 72}")
        result = run_single_problem(str(problem_dir), max_iters, model)
        agent_result = result["agent_result"]
        score_info = result["simulation_result"]["score_info"]

        row = {
            "problem_name": problem_dir.name,
            "score": score_info["score"],
            "num_passing": score_info["num_passing"],
            "num_total": score_info["num_total"],
            "num_compile_errors": score_info["num_compile_errors"],
            "runtime_seconds": agent_result["total_time_seconds"],
        }
        rows.append(row)
        raw_results.append(result)

    average_score = sum(r["score"] for r in rows) / len(rows)
    summary = {
        "problems_evaluated": len(rows),
        "average_score": average_score,
        "rows": rows,
    }

    artifacts_root = Path("artifacts")
    _write_json(artifacts_root / "batch_summary.json", summary)
    _write_json(artifacts_root / "batch_results.json", raw_results)
    _write_markdown_summary(artifacts_root / "batch_summary.md", rows, average_score)

    print(f"\n{'=' * 72}")
    print("BATCH SUMMARY")
    print(f"{'=' * 72}")
    for row in rows:
        print(
            f"{row['problem_name']:30s} "
            f"score={row['score']:.4f} "
            f"passing={row['num_passing']}/{row['num_total']} "
            f"compile_errors={row['num_compile_errors']}"
        )
    print(f"\nAverage score: {average_score:.4f}")
    print(f"Summary JSON: artifacts/batch_summary.json")
    print(f"Summary MD:   artifacts/batch_summary.md")

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the verification-agent pipeline.")
    parser.add_argument("--problem-dir", help="Problem directory containing specification and mutant_*.v files")
    parser.add_argument("--batch", help="Directory containing multiple benchmark problem subdirectories")
    parser.add_argument("--max-iters", type=int, default=1, help="Maximum agent refinement iterations")
    parser.add_argument("--model", default=None, help="Optional Codex model override")
    args = parser.parse_args()

    if bool(args.problem_dir) == bool(args.batch):
        raise SystemExit("Provide exactly one of --problem-dir or --batch")

    if args.batch:
        run_batch(args.batch, args.max_iters, args.model)
    else:
        run_single_problem(args.problem_dir, args.max_iters, args.model)


if __name__ == "__main__":
    main()
