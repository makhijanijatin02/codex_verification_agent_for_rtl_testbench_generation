"""
simulator.py - Compile and run Verilog testbenches against mutant implementations using iverilog.
"""

import subprocess
import os
import tempfile
import re
from pathlib import Path


class SimulationResult:
    """Holds the result of a single mutant simulation."""
    def __init__(self, mutant_name: str, compiled: bool, passed: bool,
                 compile_error: str = "", sim_output: str = ""):
        self.mutant_name = mutant_name
        self.compiled = compiled
        self.passed = passed
        self.compile_error = compile_error
        self.sim_output = sim_output

    def __repr__(self):
        status = "PASS" if self.passed else ("COMPILE_ERROR" if not self.compiled else "FAIL")
        return f"SimResult({self.mutant_name}: {status})"


class Simulator:
    """Runs iverilog + vvp to simulate a testbench against mutant implementations."""

    def __init__(self, timeout_seconds: int = 30):
        self.timeout = timeout_seconds
        self._check_iverilog()

    def _check_iverilog(self):
        """Verify iverilog is installed."""
        try:
            result = subprocess.run(["iverilog", "-V"], capture_output=True, timeout=5)
            if result.returncode != 0:
                raise RuntimeError("iverilog found but returned error")
        except FileNotFoundError:
            raise RuntimeError(
                "iverilog not found. Install with: sudo apt-get install iverilog\n"
                "Or on macOS: brew install icarus-verilog"
            )

    def compile_and_run(self, testbench_path: str, mutant_path: str,
                        work_dir: str = None) -> SimulationResult:
        """
        Compile a testbench with a mutant implementation and run the simulation.

        Args:
            testbench_path: Path to the testbench file (tb.v)
            mutant_path: Path to the mutant Verilog file (mutant_X.v)
            work_dir: Working directory for compilation outputs

        Returns:
            SimulationResult with compile/pass status and output
        """
        mutant_name = Path(mutant_path).stem

        if work_dir is None:
            work_dir = tempfile.mkdtemp(prefix="ivsim_")

        sim_out = os.path.join(work_dir, f"{mutant_name}.vvp")

        # Step 1: Compile with iverilog
        compile_cmd = ["iverilog", "-g2012", "-o", sim_out, testbench_path, mutant_path]
        try:
            compile_result = subprocess.run(
                compile_cmd,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
        except subprocess.TimeoutExpired:
            return SimulationResult(mutant_name, False, False,
                                   compile_error="Compilation timed out")

        if compile_result.returncode != 0:
            return SimulationResult(
                mutant_name, False, False,
                compile_error=compile_result.stderr[:2000]
            )

        # Step 2: Run simulation with vvp
        try:
            sim_result = subprocess.run(
                ["vvp", sim_out],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
        except subprocess.TimeoutExpired:
            return SimulationResult(mutant_name, True, False,
                                   sim_output="Simulation timed out")

        output = sim_result.stdout + sim_result.stderr

        # Determine pass/fail from output
        passed = self._check_passed(output)

        return SimulationResult(mutant_name, True, passed, sim_output=output[:3000])

    def compile_only(self, testbench_path: str, mutant_path: str,
                     work_dir: str = None) -> tuple[bool, str]:
        """
        Compile a testbench with one mutant and return (compiled_ok, error_text).
        Useful for early syntax/compatibility screening before full-batch simulation.
        """
        result = self.compile_and_run(testbench_path, mutant_path, work_dir)
        if result.compiled:
            return True, ""
        return False, result.compile_error

    def _check_passed(self, output: str) -> bool:
        """
        Determine if simulation passed based on output text.

        Looks for common pass indicators and absence of fail indicators.
        The ICLAD harness uses 'PASS' / 'FAIL' markers.
        """
        output_upper = output.upper()

        # Check for explicit PASS/FAIL markers
        has_pass = bool(re.search(r'\bPASS\b', output_upper))
        has_fail = bool(re.search(r'\bFAIL\b', output_upper))

        # Also check for "TESTS PASSED" or "ALL TESTS PASSED"
        has_tests_passed = bool(re.search(r'TESTS?\s+PASSED', output_upper))

        # If explicit fail, it always fails
        if has_fail:
            return False

        # Otherwise, if any pass marker exists
        if has_pass or has_tests_passed:
            return True

        # Default: no clear marker means fail
        return False

    def run_all_mutants(self, testbench_path: str, mutants_dir: str,
                        work_dir: str = None) -> list:
        """
        Run the testbench against all mutant implementations in a directory.

        Args:
            testbench_path: Path to generated testbench
            mutants_dir: Directory containing mutant_0.v ... mutant_30.v
            work_dir: Working directory for compilation outputs

        Returns:
            List of SimulationResult objects
        """
        if work_dir is None:
            work_dir = tempfile.mkdtemp(prefix="ivsim_batch_")

        # Find all mutant files
        mutant_files = sorted(
            Path(mutants_dir).glob("mutant_*.v"),
            key=lambda p: int(re.search(r'(\d+)', p.stem).group(1))
        )

        if not mutant_files:
            raise FileNotFoundError(f"No mutant_*.v files found in {mutants_dir}")

        results = []
        for mutant_path in mutant_files:
            result = self.compile_and_run(testbench_path, str(mutant_path), work_dir)
            results.append(result)
            print(f"  {result}")

        return results


def compute_score(results: list, correct_mutant_index: int = None) -> dict:
    """
    Compute the precision-style score for a set of simulation results.

    Score = 1 / (number of passing implementations)
    If the correct implementation does not pass, score = 0.

    Args:
        results: List of SimulationResult
        correct_mutant_index: Index of the correct mutant (if known)

    Returns:
        Dictionary with score, num_passing, details
    """
    passing = [r for r in results if r.passed]
    failing = [r for r in results if not r.passed]
    compile_errors = [r for r in results if not r.compiled]

    num_passing = len(passing)
    num_total = len(results)

    # Check if correct mutant passed (if we know which one it is)
    correct_passed = True
    if correct_mutant_index is not None:
        correct_name = f"mutant_{correct_mutant_index}"
        correct_results = [r for r in results if r.mutant_name == correct_name]
        if correct_results:
            correct_passed = correct_results[0].passed
        else:
            correct_passed = False

    if not correct_passed:
        score = 0.0
    elif num_passing == 0:
        score = 0.0
    else:
        score = 1.0 / num_passing

    return {
        "score": score,
        "num_passing": num_passing,
        "num_failing": len(failing),
        "num_compile_errors": len(compile_errors),
        "num_total": num_total,
        "correct_passed": correct_passed,
        "passing_mutants": [r.mutant_name for r in passing],
        "failing_mutants": [r.mutant_name for r in failing],
    }
