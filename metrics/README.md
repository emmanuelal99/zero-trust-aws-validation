# Metrics collection & analysis

Computes the five evaluation metrics (ASR, LMCS, MTTD, CBCS, CDI) per environment from
pipeline scan output and Wazuh alerts, and produces the A vs B comparison.
See `../docs/metrics.md` for the Chapter 3 definitions and formulae.

## `compute_metrics.py`

Implements the two Prowler-driven metrics:

```bash
# CBCS from a Prowler CIS AWS Foundations compliance CSV
python compute_metrics.py cbcs \
  --input 'prowler-output/compliance/*cis_3.0_aws_foundations*.csv' \
  --output data/cbcs_baseline_environment-b.json

# CDI from baseline vs current CBCS (drift injected between the two Prowler runs)
python compute_metrics.py cdi \
  --baseline data/cbcs_baseline_environment-b.json \
  --current  data/cbcs_current_environment-b.json \
  --output   data/cdi_environment-b.json
```

- `--input` accepts a path or a glob (Prowler embeds the account ID in filenames).
- CBCS = `(C_passed / (C_total − C_ignored)) × 100`; `MANUAL`/`MUTED` count as ignored.
- CDI = `1 − (CBCS_current / CBCS_baseline)`; `> 0` means drift degraded compliance.

The baseline-vs-current CBCS comparison is driven by the drift-injection scenarios in
`../drift/` (dissertation Table 3.3). ASR/LMCS/MTTD consume Nuclei/Stratus/Wazuh artefacts.

- `data/` — raw scan/alert inputs and metric JSON (git-ignored).
- `requirements.txt` — Python deps (PyYAML for the drift harness).
