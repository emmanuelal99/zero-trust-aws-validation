# Security tooling configs

Configuration and baseline files for each pipeline stage. Scan **output** is git-ignored.

- `trivy/`    — Trivy config, ignore policy for IaC/container scans (pipeline stage 2)
- `prowler/`  — Prowler config + custom checks for AWS posture (stage 3)
- `nuclei/`   — Nuclei templates + target config for the Logi-Track app (stage 4)
- `stratus-red-team/` — Stratus technique selection + run config (stage 5)

Each tool runs against **both** environments; results are tagged by environment for the
A vs B comparison.
