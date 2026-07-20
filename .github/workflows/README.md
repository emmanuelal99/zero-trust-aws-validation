# Attack pipeline (GitHub Actions)

`pipeline.yml` — one workflow, run against a target environment (A or B) via
`workflow_dispatch` (or on push to `main`, defaulting to Environment B).

## Stages

1. **terraform** — `fmt`/`validate`/`plan` (and gated `apply`); exports `app_url`.
2. **trivy** — IaC scan of `terraform/`, SARIF uploaded to code scanning.
3. **prowler** — CIS AWS Foundations Benchmark assessment; `compute_metrics.py cbcs`
   records **CBCS_baseline**.
4. **nuclei** — web/app scan of the Logi-Track ALB endpoint.
5. **stratus** — Stratus Red Team detonation of the techniques in
   `security/stratus-red-team/techniques.txt` (cleaned up after).
6. **cdi** — injects the Table 3.3 drift scenarios (`drift/`), re-runs Prowler for
   **CBCS_current**, computes **CDI = 1 − (current/baseline)**, then reverts the drift.

## Requirements

- Repo secret `AWS_PIPELINE_ROLE_ARN` — IAM role assumed via GitHub OIDC (`id-token: write`).
- Region: `eu-west-2`.

Metric artefacts (`cbcs-baseline-*`, `cdi-*`, scan outputs) are uploaded per run and consumed
by `metrics/compute_metrics.py`. See `docs/metrics.md` for definitions.
