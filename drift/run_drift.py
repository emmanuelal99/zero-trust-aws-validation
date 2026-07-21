#!/usr/bin/env python3
"""Configuration-drift harness for the CDI metric.

Applies (or reverts) the drift-injection scenarios declared in `drift_scenarios.yaml`.
Each scenario is a controlled, out-of-band mutation of a *deployed* environment that moves
it away from its Terraform (IaC) baseline — e.g. loosening a security group, disabling
encryption, attaching an over-broad policy. Prowler is then re-run and CBCS_current is
compared with CBCS_baseline to produce the Configuration Drift Index.

Scenario shell snippets are executed via `bash` and may reference environment variables
(typically Terraform outputs exported by the pipeline, e.g. $APP_SG_ID, $DB_INSTANCE_ID).

Usage:
    python run_drift.py --apply  --env B                 # inject all Env-B scenarios
    python run_drift.py --apply  --env B --only D1,D3    # inject a subset
    python run_drift.py --revert --env B                 # undo (reverse order)
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML is required: pip install pyyaml")

HERE = Path(__file__).resolve().parent
SCENARIOS_FILE = HERE / "drift_scenarios.yaml"

def missing_resources(scenario: dict) -> list[str]:
    """Return the required resource env vars that resolve to None/empty.

    Scenarios that mutate a *deployed* resource declare the env vars carrying that
    resource's ID/name via `requires:` in drift_scenarios.yaml. On plan-only runs those
    lookups yield "" or the literal string "None" (AWS CLI `--output text` on a null
    scalar), which would make the AWS call fail with e.g. "The ID 'None' is not valid".
    When any required var is absent we skip the scenario so plan-only runs stay clean.
    """
    missing = []
    for var in scenario.get("requires", []):
        val = os.environ.get(var, "").strip()
        if val == "" or val.lower() == "none":
            missing.append(var)
    return missing


def load_scenarios() -> list[dict]:
    data = yaml.safe_load(SCENARIOS_FILE.read_text()) or {}
    return data.get("scenarios", [])


def select(scenarios: list[dict], env: str, only: set[str] | None,
           channel: str | None) -> list[dict]:
    out = []
    for s in scenarios:
        envs = [e.upper() for e in s.get("environment", ["A", "B"])]
        if env.upper() not in envs:
            continue
        if only and s["id"] not in only:
            continue
        if channel and s.get("detection") != channel:
            continue
        out.append(s)
    return out


def run_snippet(scenario_id: str, phase: str, snippet: str) -> bool:
    if not snippet or not snippet.strip():
        print(f"[{scenario_id}] no {phase} snippet — skipping")
        return True
    print(f"[{scenario_id}] {phase} ...")
    proc = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", snippet],
        text=True,
    )
    ok = proc.returncode == 0
    print(f"[{scenario_id}] {phase} {'ok' if ok else 'FAILED (%d)' % proc.returncode}")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description="Apply/revert drift-injection scenarios (Table 3.3).")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="Inject drift.")
    mode.add_argument("--revert", action="store_true", help="Revert drift (reverse order).")
    ap.add_argument("--env", required=True, choices=["A", "B", "a", "b"], help="Target environment.")
    ap.add_argument("--only", help="Comma-separated scenario IDs to run (default: all applicable).")
    ap.add_argument("--channel", choices=["prowler_cbcs", "nuclei", "terraform_plan"],
                    help="Only run scenarios with this detection channel "
                         "(CDI uses prowler_cbcs so D7/D8 never touch CBCS).")
    ap.add_argument("--continue-on-error", action="store_true",
                    help="Keep going if a scenario fails (default: stop).")
    args = ap.parse_args()

    only = {x.strip() for x in args.only.split(",")} if args.only else None
    scenarios = select(load_scenarios(), args.env, only, args.channel)
    if not scenarios:
        sys.exit(f"No scenarios matched env={args.env} only={only} channel={args.channel}")

    phase = "apply" if args.apply else "revert"
    ordered = scenarios if args.apply else list(reversed(scenarios))

    failures = 0
    for s in ordered:
        missing = missing_resources(s)
        if missing:
            print(f"[{s['id']}] no infrastructure ({', '.join(missing)} resolved to "
                  f"None/empty) — skipping {s['id']} on plan-only run.")
            continue
        ok = run_snippet(s["id"], phase, s.get(phase, ""))
        if not ok:
            failures += 1
            if not args.continue_on_error:
                sys.exit(f"Stopping: {s['id']} {phase} failed.")

    print(f"\n{phase}: {len(ordered) - failures}/{len(ordered)} scenarios succeeded.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
