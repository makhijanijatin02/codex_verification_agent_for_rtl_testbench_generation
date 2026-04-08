Agent: RTLVerificationAgent

Goal:
Read a natural-language RTL specification, generate a discriminating Verilog testbench, run simulation against candidate RTL implementations, and refine until only the correct implementation passes.

Workspace Conventions:
- Input specifications live inside a problem directory such as `sample_problem/`.
- Candidate RTL implementations live alongside the specification as `mutant_*.v`.
- Generated testbenches are written under `tb/`.
- Structured agent outputs and simulation summaries are written under `artifacts/`.

Primary Workflow:
1. Read the specification file from the selected problem directory.
2. Inspect the candidate RTL to recover the module header and signal interface.
3. Convert the specification into a structured behavior model.
4. Generate a Verilog testbench and save it under `tb/`.
5. Run simulation across all candidate RTL implementations using `run_sim.py`.
6. If more than one implementation passes, analyze the passing mutants and strengthen the testbench.
7. Repeat until the score improves or the iteration budget is exhausted.

Files:
- `agent.py`: main orchestration loop
- `run_sim.py`: direct simulation/evaluation entry point
- `spec_parser.py`: structured behavior extraction
- `tb_generator.py`: Verilog testbench generation
- `simulator.py`: iverilog/vvp execution wrapper

Expected Demonstration:
1. Run `python3 agent.py --problem-dir sample_problem --max-iters 1`
2. Inspect `tb/sample_problem_tb.v`
3. Inspect `artifacts/sample_problem/final_result.json`
4. Re-run `python3 run_sim.py --problem-dir sample_problem --tb tb/sample_problem_tb.v`
