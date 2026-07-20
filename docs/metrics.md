# Evaluation metrics

The five metrics are computed from pipeline scan output + Wazuh alerts, per environment,
and compared A vs B. Definitions below match Chapter 3 exactly.

## ASR — Attack Success Rate
`ASR = (# techniques that succeeded) / (# techniques attempted)`
- Source: Nuclei findings (confirmed), Stratus Red Team detonation results, Prowler fails
  that map to an exploitable condition.
- Lower ASR in Env B => Zero Trust reduced exploitable surface.

## LMCS — Lateral Movement Capability Score  (all-pairs blast-radius form)
`LMCS = (Σ (V_i × W_i)) / K_max`
- `i` — ordered **source→target** node pair (source ≠ target).
- `V_i` — binary reachability of the pair (1 if the source can reach the target, else 0).
- `W_i` — criticality weight of the pair's **destination** node.
- `K_max` — `Σ W_i` over all pairs = the full-mesh maximum (every node reaches every node).
- Every network tier is treated as a potential origin, so LMCS measures the whole segmentation
  surface, i.e. how much of the weighted environment is traversable — not one assumed foothold.
- **Single-foothold Eq 3.2 is the special case** where `i` is restricted to pairs whose source is
  the one foothold (`--foothold app`). The equation shape is identical; only the domain of `i`,
  the meaning of `W_i` (destination criticality), and `K_max` (full-mesh sum) change.
- Source: network reachability (SG ingress ∧ egress, transitive) parsed OFFLINE from Terraform
  state; Stratus lateral-movement techniques validate a few edges empirically.
- **Higher LMCS = greater lateral-movement capability = weaker containment.** Expect Env B
  (micro-segmentation + restricted egress) to score lower than Env A (flat internal trust).

## MTTD — Mean Time To Detect
`MTTD = mean(t_detected - t_action)` across attack actions Wazuh detected.
- Source: attack action timestamps (pipeline logs) vs Wazuh alert timestamps.
- **Undetected actions handled explicitly:** an action Wazuh never alerts on is *not* averaged
  in as a zero or small delay (which would flatter MTTD). It is excluded from the MTTD mean
  and reported separately as a detection-coverage figure (`# detected / # attempted`), so MTTD
  measures speed only over detected actions and coverage is not silently hidden.

## CBCS — CIS Benchmark Compliance Score
`CBCS = (C_passed / (C_total − C_ignored)) × 100`
- `C_passed` — CIS checks that passed.
- `C_total` — total CIS checks assessed.
- `C_ignored` — checks explicitly excluded (not applicable / muted).
- Computed by **Prowler** against the **CIS AWS Foundations Benchmark**.
- Higher CBCS = stronger baseline compliance. Expect Env B > Env A.

## CDI — Configuration Drift Index
`CDI = 1 − (CBCS_current / CBCS_baseline)`
- `CBCS_baseline` — CBCS measured immediately after the first Terraform deploy (clean IaC state).
- `CBCS_current` — CBCS measured on a later run, after drift-injection scenarios (Table 3.3).
- Measures configuration drift over time: `CDI = 0` means no drift from baseline; `CDI > 0`
  means drift has degraded compliance; `CDI < 0` means compliance improved above baseline.
- Source: two Prowler CBCS runs (baseline vs current) driven by the Table 3.3 drift scenarios.

---

## Computing the metrics (`metrics/compute_metrics.py`)

All five are subcommands; each writes a result JSON to `metrics/data/`.

```
python metrics/compute_metrics.py cbcs  --input <prowler_csv> --output ...
python metrics/compute_metrics.py cdi   --baseline <cbcs.json> --current <cbcs.json> --output ...
python metrics/compute_metrics.py asr   --nuclei <nuclei.jsonl> --nuclei-templates-run <N> \
                                        --stratus <stratus_results.jsonl> --output ...
python metrics/compute_metrics.py lmcs  --state <terraform.tfstate> --weights metrics/lmcs_weights.yaml --output ...
python metrics/compute_metrics.py mttd  --actions <attack_actions.jsonl> --alerts <alerts.json> \
                                        --signatures metrics/mttd_signatures.yaml --output ...
```

### Input artefact schemas

**ASR** — offensive tools only (Prowler deliberately excluded; CBCS covers posture).
- `nuclei-results.jsonl`: native Nuclei `-jsonl`. Each line is a confirmed match; success =
  `info.severity` ≥ `--severity-threshold` (default `medium`). The true denominator (templates
  *executed*) is not in the JSONL, so pass `--nuclei-templates-run N` from the Nuclei run summary.
- `stratus_results.jsonl` (one record per attempted technique):
  ```json
  {"technique":"aws.defense-evasion.cloudtrail-stop","status":"success","exit_code":0,"timestamp":"2026-07-14T12:00:00Z"}
  ```
  Success = `status` in {success, succeeded, detonated} or `exit_code == 0`.

**LMCS** — offline, reproducible from Terraform state; no live AWS access. **All-pairs form.**
- `--state`: the environment's `terraform.tfstate`. The SG ingress/egress graph is parsed from it.
- `--weights`: `metrics/lmcs_weights.yaml` — node set + criticality weights `W_i` (identical A/B).
- `--foothold NODE` (optional): restrict to a single source, recovering the single-foothold Eq 3.2.
- Sources = network nodes with an SG (each tier is a potential origin); derived nodes
  (`service`/`colocated`) are targets only. Reachability is transitive (BFS over the SG graph).
- Output includes `mode`, `lmcs`, `weighted_reachable`, `k_max`, a `reachability_matrix`
  (source → {target: bool}), and `reachable_pairs`.

**MTTD** — depends on Wazuh (`deploy_wazuh = true`).
- `attack_actions.jsonl` (appended by the Nuclei + Stratus stages), one line per action:
  ```json
  {"action_id":"stratus-aws.defense-evasion.cloudtrail-stop","tool":"stratus","technique":"aws.defense-evasion.cloudtrail-stop","t_execute":"2026-07-14T12:00:00Z"}
  ```
- `alerts.json`: Wazuh alerts (JSON-lines), fields used: `timestamp`, `rule.id`, `rule.mitre.id`.
- `mttd_signatures.yaml`: maps each `technique` → Wazuh `rule_ids` / `mitre_ids`. Correlation is by
  signature (no shared trace ID) — a small mis-attribution risk noted as a methodology limitation.
- On a `deploy_wazuh = false` run there is no `alerts.json`: MTTD reports `mttd_seconds = null`,
  `n_detected = 0`, `detection_coverage = 0` (it does not crash).

### Follow-up wiring (not yet in `.github/workflows/pipeline.yml`)

The parsers above are complete; the pipeline still needs to *produce* three artefacts:
1. **Stratus** stage: write `stratus_results.jsonl` (technique + exit status) instead of stdout only,
   and append each detonation to `attack_actions.jsonl`.
2. **Nuclei** stage: append each probe to `attack_actions.jsonl` and export the executed-template count.
3. A **Wazuh alert-export** stage (after the attack stages) pulling `alerts.json` from the manager.
Plus author the Wazuh rules/decoders and fill in real `rule_ids` in `mttd_signatures.yaml`.

### Environment B control notes (Table 3.1)

Two Table 3.1 rows differ from a naive reading; kept consistent with Chapter 3:

- **GuardDuty — excluded.** AWS Free-Plan accounts restrict the service. GuardDuty is not in the
  CloudTrail → Wazuh detection path that MTTD measures, so its absence does not affect the A/B
  comparison; it also reflects a realistic constraint for resource-limited SMEs, for whom paid-tier
  managed detection may be inaccessible. VPC Flow Logs (CloudWatch) remain enabled in Env B only.
- **MFA — structurally inapplicable, not omitted.** The architecture uses machine identities
  (instance roles + SSM Session Manager) with no long-lived human credentials, so MFA has no
  principal to apply to. The Table 3.1 row is framed as *"no long-lived credentials; SSM Session
  Manager access only"* — the stronger, accurate claim for a machine-identity design.

> **LMCS modelling note.** LMCS uses the **all-pairs blast-radius** form (chosen so the metric
> discriminates A from B for the right reason — segmentation and least privilege). Under the earlier
> *single*-foothold reading, the app's legitimate dependencies (RDS, Secrets Manager, local Redis)
> are reachable in **both** environments by design, so single-foothold LMCS came out identical for A
> and B — that reading measures a fixed foothold's reach, not the environment's containment. The
> all-pairs form treats every tier as a potential origin: baseline flat trust (DB open to the whole
> VPC, all-egress) yields a near-full mesh, whereas Zero Trust (DB only from the app SG, restricted
> egress) blocks return/cross-tier pairs — so Env B < Env A. `--foothold` still recovers the
> single-foothold special case for comparison in the results chapter.
