# Drift-injection harness (CDI)

Drives the **Configuration Drift Index** metric:

```
CDI = 1 - (CBCS_current / CBCS_baseline)
```

## Flow

1. **Baseline** — right after `terraform apply`, the Prowler pipeline stage runs the CIS
   AWS Foundations Benchmark and `compute_metrics.py cbcs` records `CBCS_baseline`.
2. **Inject** — `run_drift.py --apply --env <A|B>` applies the Table 3.3 scenarios in
   `drift_scenarios.yaml`, mutating the *deployed* environment away from its Terraform state.
3. **Current** — Prowler re-runs the same CIS benchmark; `compute_metrics.py cbcs` records
   `CBCS_current`.
4. **CDI** — `compute_metrics.py cdi --baseline ... --current ...` computes the index.
5. **Revert** — `run_drift.py --revert --env <A|B>` restores the baseline (reverse order),
   so a subsequent `terraform plan` shows no diff.

## Scenarios (Table 3.3)

`drift_scenarios.yaml` holds the eight scenarios D1–D8. Each declares `apply`/`revert` bash
snippets that reference environment variables resolved by the pipeline (`APP_SG_ID`,
`ALB_SG_ID`, `INSTANCE_ROLE_NAME`, `VPC_ID`, `ACCOUNT_ID`, `CLOUDTRAIL_NAME`, `NAME_PREFIX`).

Scenarios are split by **detection channel** so the CBCS/CDI measurement stays clean:

| Channel | Scenarios | Detected by | Feeds CDI? |
|---|---|---|---|
| `prowler_cbcs` | D1–D6 | Prowler CIS AWS Foundations | **Yes** |
| `nuclei` | D7 | Nuclei (app-layer) | No |
| `terraform_plan` | D8 | `terraform plan -detailed-exitcode` | No |

```bash
python run_drift.py --apply  --env B --channel prowler_cbcs   # D1–D6 (CDI)
python run_drift.py --apply  --env B --channel nuclei         # D7
python run_drift.py --revert --env B --channel prowler_cbcs   # undo D1–D6
python run_drift.py --apply  --env B --only D5                # a single scenario
```

### CBCS-movement summary (Table 3.3 analysis)

Whether each scenario actually shifts the Prowler CIS result (and therefore CDI).
✅ = moves CBCS reliably; ⚠️ = conditional (delta only under the stated precondition);
➖ = by design does not touch CBCS (routed to another detection channel).

| ID | Name | CIS / tool | Channel | Moves CBCS? | Condition / reason |
|----|------|-----------|---------|-------------|--------------------|
| D1 | Network Exposure | CIS 5.2 | prowler_cbcs | ✅ Reliably | Opening tcp/22 to `0.0.0.0/0` always fails Prowler's SG admin-port check. |
| D2 | IAM Privilege Escalation | CIS 1.16 | prowler_cbcs | ✅ Reliably | Uses a **customer-managed** `*:*` policy. (AWS-managed `AdministratorAccess` would **not** trip 1.16 — Prowler evaluates customer-managed policies.) |
| D3 | Public Data Exposure | CIS 2.1.5 | prowler_cbcs | ✅ Reliably | Bucket-level Block-Public-Access removed → bucket check fails. (Account-level BPA can mask real exposure but the bucket-level control still fails.) |
| D4 | Logging Configuration | CIS 3.1 | prowler_cbcs | ⚠️ Conditional | Delta **only** if a CloudTrail trail exists and was logging at baseline. With no trail, CIS 3.1 already fails at baseline → CDI sees no change. |
| D5 | Encryption Drift | CIS 2.2.1 | prowler_cbcs | ✅ Reliably | Disabling region EBS default encryption always fails the CIS 2.2.1 check. |
| D6 | Identity Configuration | CIS 1.8 | prowler_cbcs | ⚠️ Conditional | Delta **only** if the password policy passes at baseline. If the account has no/weak policy already, CIS 1.8 fails at baseline → no delta. Snapshot/restore (below) keeps the baseline identical across runs. |
| D7 | Application Configuration | Nuclei (missing headers) | nuclei | ➖ No (by design) | App-layer misconfiguration; invisible to Prowler/CIS. Detected by Nuclei; excluded from CDI. |
| D8 | Infrastructure Drift | `terraform plan` | terraform_plan | ➖ No (by design) | State/IaC consistency drift; not a CIS control. Detected by `terraform plan -detailed-exitcode` (exit 2); excluded from CDI. |

**Reliable CBCS movers for CDI:** D1, D2, D3, D5.
**Conditional (flagged):** D4, D6 — verify their preconditions hold at baseline or the CDI delta they contribute is zero.

### D6 resolution
D6 was "MFA removal" (CIS 1.10), but this environment uses instance **roles** — there are no
console users/MFA to mutate. CIS 1.14 (key rotation) and 1.12 (root key) aren't cleanly
mutable in a pipeline (can't backdate a key, can't create a root key). D6 is therefore
substituted with **CIS 1.8 — weaken the account IAM password policy**: account-level, always
revertible, low standing risk, and Prowler-checked.

**Snapshot/restore (for repeatable runs).** Rather than hard-coding an assumed "strong" policy
on revert, D6 now captures the *exact* current policy on `apply`:
`aws iam get-account-password-policy` → `/tmp/${NAME_PREFIX}-pwpolicy-snapshot.json` (or a
`NONE` marker if no policy exists). On `revert` it rebuilds that exact snapshot
(`--require-*`/`--no-require-*` + numeric fields reconstructed from the JSON), or runs
`aws iam delete-account-password-policy` if the marker was `NONE`. This guarantees each of the
30+ repeated runs starts from an **identical** baseline, so CDI measurements stay comparable.

Requires `pyyaml` and an authenticated AWS CLI (the pipeline assumes the role via OIDC).
Every injection has a matching revert; the pipeline runs reverts under `if: always()`.
