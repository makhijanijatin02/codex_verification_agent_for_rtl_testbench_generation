# Real Benchmark Results

These results were collected on three real visible problems from the public ICLAD Google Verification benchmark using:

```bash
python3 run_pipeline.py --problem-dir <problem_dir> --max-iters 1
```

| Problem | Type | Mutants | Passing Implementations | Compile Errors | Runtime (s) | Outcome |
|--------|------|--------:|------------------------:|---------------:|------------:|---------|
| `enc_bin2gray` | Combinational | 31 | 1 | 0 | 62.6 | Strong discrimination |
| `enc_bin2onehot` | Combinational | 31 | 1 | 0 | 141.8 | Strong discrimination |
| `shift_right` | Combinational | 31 | 0 | 31 | 234.4 | Testbench compile failure |

Observed limitation on `shift_right`:
- the generated testbench used variable part-selects in a way that `iverilog` rejected
- representative compile error: `Part select expressions must be constant`

Relevant artifacts are included under:
- `artifacts/enc_bin2gray/`
- `artifacts/enc_bin2onehot/`
- `artifacts/shift_right/`
