#!/usr/bin/env python3
"""Compute dissertation evaluation metrics from pipeline artefacts.

Implemented here (Chapter 3 definitions):

  CBCS — CIS Benchmark Compliance Score
         CBCS = (C_passed / (C_total - C_ignored)) * 100
         Parsed from a Prowler CIS AWS Foundations Benchmark compliance report.

  CDI  — Configuration Drift Index
         CDI = 1 - (CBCS_current / CBCS_baseline)
         baseline = CBCS right after the first Terraform deploy (clean IaC state),
         current  = CBCS after the Table 3.3 drift-injection scenarios.

  ASR  — Attack Success Rate
         ASR = N_successful / N_total  (purely offensive: Nuclei + Stratus only)
         successful = confirmed Nuclei finding at/above a severity threshold, or a
         Stratus technique that detonated (exit 0). Denominator = templates executed
         + techniques attempted. Prowler is intentionally excluded (CBCS covers posture).

  LMCS — Lateral Movement Capability Score  (all-pairs blast-radius form)
         LMCS = (Σ V_i·W_i) / K_max,  K_max = Σ W_i
         The index i ranges over ordered (source -> target) node pairs; V_i is the binary
         reachability of that pair; W_i is the DESTINATION node's criticality weight; K_max
         is the full-mesh maximum (every pair reachable). Measures how much of the weighted
         environment is traversable — lower = better containment. Reachability is derived
         OFFLINE from the Terraform state security-group graph (ingress ∧ egress), so it is
         reproducible without live AWS access. Weights/node set come from
         metrics/lmcs_weights.yaml (identical for Env A and Env B — a controlled variable).
         Restricting i to one source (--foothold) recovers the single-foothold Eq 3.2.

  MTTD — Mean Time To Detect
         MTTD = mean(t_detect - t_execute) over DETECTED actions only.
         t_execute from the attack-action log (attack_actions.jsonl), t_detect from Wazuh
         alerts, correlated via a signature map (metrics/mttd_signatures.yaml). Undetected
         actions are excluded from the mean (never counted as ~0) and reported separately
         as detection coverage (n_detected / n_attempted).

Artefact schemas are documented in docs/metrics.md.
"""
from __future__ import annotations

import argparse
import csv
import glob
import ipaddress
import json
import re
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

# Prowler compliance statuses that count as "ignored" for CBCS (not assessed pass/fail).
IGNORED_STATUSES = {"MANUAL", "MUTED", "INFO", "NOT_AVAILABLE"}


def _find_status_field(fieldnames: list[str]) -> str:
    """Locate the STATUS column regardless of Prowler version casing."""
    for name in fieldnames:
        if name and name.strip().upper() in {"STATUS", "REQUIREMENTS_STATUS", "CHECK_STATUS"}:
            return name
    raise SystemExit(f"Could not find a STATUS column in: {fieldnames}")


def _find_muted_field(fieldnames: list[str]) -> str | None:
    for name in fieldnames:
        if name and name.strip().upper() in {"MUTED", "IS_MUTED"}:
            return name
    return None


def _read_compliance_rows(path: Path) -> list[dict]:
    """Read a Prowler compliance CSV, sniffing the delimiter (Prowler uses ';')."""
    text = path.read_text(encoding="utf-8-sig")
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=";,\t")
        delimiter = dialect.delimiter
    except csv.Error:
        delimiter = ";"
    return list(csv.DictReader(text.splitlines(), delimiter=delimiter))


def compute_cbcs(input_path: Path) -> dict:
    """CBCS from a Prowler CIS compliance CSV."""
    rows = _read_compliance_rows(input_path)
    if not rows:
        raise SystemExit(f"No rows in compliance report: {input_path}")

    fieldnames = list(rows[0].keys())
    status_field = _find_status_field(fieldnames)
    muted_field = _find_muted_field(fieldnames)

    c_total = len(rows)
    c_passed = 0
    c_ignored = 0

    for row in rows:
        status = (row.get(status_field) or "").strip().upper()
        muted = False
        if muted_field:
            muted = (row.get(muted_field) or "").strip().lower() in {"true", "1", "yes"}

        if muted or status in IGNORED_STATUSES:
            c_ignored += 1
        elif status in {"PASS", "PASSED"}:
            c_passed += 1
        # FAIL and everything else falls through as assessed-not-passed.

    denominator = c_total - c_ignored
    if denominator <= 0:
        raise SystemExit("CBCS denominator (C_total - C_ignored) is zero; nothing assessed.")

    cbcs = (c_passed / denominator) * 100.0
    return {
        "metric": "CBCS",
        "cbcs": round(cbcs, 2),
        "c_passed": c_passed,
        "c_total": c_total,
        "c_ignored": c_ignored,
        "source": str(input_path),
    }


def compute_cdi(baseline_path: Path, current_path: Path) -> dict:
    """CDI from two CBCS result files."""
    baseline = json.loads(baseline_path.read_text())["cbcs"]
    current = json.loads(current_path.read_text())["cbcs"]
    if baseline == 0:
        raise SystemExit("CBCS_baseline is 0; CDI is undefined.")

    cdi = 1.0 - (current / baseline)
    return {
        "metric": "CDI",
        "cdi": round(cdi, 4),
        "cbcs_baseline": baseline,
        "cbcs_current": current,
        "interpretation": (
            "no drift" if abs(cdi) < 1e-9
            else "compliance degraded (drift)" if cdi > 0
            else "compliance improved above baseline"
        ),
    }


# ===========================================================================
# ASR — Attack Success Rate
# ===========================================================================
_SEVERITY_ORDER = {"info": 0, "low": 1, "medium": 2, "high": 3, "critical": 4}


def _read_jsonl(path: Path) -> list[dict]:
    """Read a JSON-lines file; tolerate blank lines. Missing file -> empty list.

    Malformed lines are skipped with a warning rather than aborting the whole
    computation. The Wazuh alerts export is pulled over an SSM channel with a bounded
    output size; if a payload is ever truncated the final line can be cut mid-string,
    and one bad line must not zero out an otherwise-valid MTTD run.
    """
    if not path.exists():
        return []
    records = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as e:
            print(
                f"WARN: skipping malformed JSON at {path}:{lineno} ({e}); "
                "line likely truncated in transit.",
                file=sys.stderr,
            )
    return records


def compute_asr(
    nuclei_path: Path | None,
    stratus_path: Path | None,
    severity_threshold: str,
    nuclei_templates_run: int | None,
) -> dict:
    """ASR from Nuclei findings + Stratus detonation results (offensive tools only)."""
    threshold = _SEVERITY_ORDER.get(severity_threshold.lower())
    if threshold is None:
        raise SystemExit(f"Unknown severity threshold: {severity_threshold}")

    # --- Nuclei: each JSONL line is a confirmed match (a "successful" probe). ---
    nuclei_findings = _read_jsonl(nuclei_path) if nuclei_path else []
    nuclei_success = 0
    for f in nuclei_findings:
        sev = str(((f.get("info") or {}).get("severity") or f.get("severity") or "")).lower()
        if _SEVERITY_ORDER.get(sev, -1) >= threshold:
            nuclei_success += 1
    # N_total for Nuclei = templates executed. Nuclei only writes matches, so the true
    # denominator must be supplied from the run summary. Fall back to findings count
    # (degenerate: ASR_nuclei -> share of findings meeting the threshold) with a warning.
    if nuclei_templates_run is not None:
        nuclei_total = nuclei_templates_run
    else:
        nuclei_total = len(nuclei_findings)
        if nuclei_findings:
            print(
                "WARN: --nuclei-templates-run not given; using findings count as the "
                "Nuclei denominator (pass the executed-template count for a true ASR).",
                file=sys.stderr,
            )
    if nuclei_success > nuclei_total:  # guard against a mis-supplied denominator
        nuclei_success = nuclei_total

    # --- Stratus: one record per attempted technique; success = detonated (exit 0). ---
    stratus_records = _read_jsonl(stratus_path) if stratus_path else []
    stratus_total = len(stratus_records)
    stratus_success = 0
    for r in stratus_records:
        status = str(r.get("status") or "").lower()
        exit_code = r.get("exit_code")
        if status in {"success", "succeeded", "detonated"} or exit_code == 0:
            stratus_success += 1

    n_success = nuclei_success + stratus_success
    n_total = nuclei_total + stratus_total
    if n_total == 0:
        raise SystemExit("ASR denominator is zero (no Nuclei templates and no Stratus techniques).")

    return {
        "metric": "ASR",
        "asr": round(n_success / n_total, 4),
        "n_successful": n_success,
        "n_total": n_total,
        "by_tool": {
            "nuclei": {
                "successful": nuclei_success,
                "total": nuclei_total,
                # Per-tool ASR so ASR_nuclei is reportable alongside the combined figure;
                # null when that tool ran no attacks (avoids 0/0).
                "asr": round(nuclei_success / nuclei_total, 4) if nuclei_total else None,
                "severity_threshold": severity_threshold.lower(),
            },
            "stratus": {
                "successful": stratus_success,
                "total": stratus_total,
                "asr": round(stratus_success / stratus_total, 4) if stratus_total else None,
            },
        },
        "sources": {
            "nuclei": str(nuclei_path) if nuclei_path else None,
            "stratus": str(stratus_path) if stratus_path else None,
        },
    }


# ===========================================================================
# LMCS — Lateral Movement Capability Score (offline Terraform-state SG graph)
# ===========================================================================
def _iter_state_instances(state: dict):
    """Yield (type, attributes) for every resource instance in a Terraform state file."""
    for res in state.get("resources", []):
        rtype = res.get("type", "")
        for inst in res.get("instances", []):
            yield rtype, (inst.get("attributes") or {})


def _norm_port(attrs: dict) -> tuple[int, int]:
    """Return a (from, to) port range; a null/-1 range means 'all ports'."""
    proto = str(attrs.get("proto") or attrs.get("ip_protocol") or attrs.get("protocol") or "")
    frm = attrs.get("from")
    to = attrs.get("to")
    if proto in {"-1", "all"} or frm in (None, "", -1):
        return (0, 65535)
    return (int(frm), int(to if to not in (None, "") else frm))


def _build_sg_table(state: dict) -> tuple[dict, list[str]]:
    """Build {sg_id: {names, ingress:[rule], egress:[rule]}} and collect VPC CIDRs.

    Handles both the standalone rule resources (aws_vpc_security_group_(in|e)gress_rule)
    and inline ingress/egress blocks on aws_security_group.
    """
    table: dict[str, dict] = {}
    vpc_cidrs: list[str] = []

    def _entry(sg_id: str) -> dict:
        return table.setdefault(sg_id, {"names": set(), "ingress": [], "egress": []})

    def _rule(proto, frm, to, ref, cidr) -> dict:
        return {"proto": proto, "from": frm, "to": to, "ref": ref, "cidr": cidr}

    for rtype, a in _iter_state_instances(state):
        if rtype == "aws_vpc":
            if a.get("cidr_block"):
                vpc_cidrs.append(a["cidr_block"])
        elif rtype == "aws_security_group":
            e = _entry(a.get("id", ""))
            if a.get("name"):
                e["names"].add(a["name"])
            nm = (a.get("tags") or {}).get("Name")
            if nm:
                e["names"].add(nm)
            for block, key in (("ingress", "ingress"), ("egress", "egress")):
                for b in a.get(block) or []:
                    proto = b.get("protocol")
                    frm, to = b.get("from_port"), b.get("to_port")
                    for cidr in (b.get("cidr_blocks") or []):
                        e[key].append(_rule(proto, frm, to, None, cidr))
                    for ref in (b.get("security_groups") or []):
                        e[key].append(_rule(proto, frm, to, ref, None))
        elif rtype in ("aws_vpc_security_group_ingress_rule", "aws_security_group_rule"):
            e = _entry(a.get("security_group_id", ""))
            e["ingress"].append(_rule(
                a.get("ip_protocol") or a.get("protocol"),
                a.get("from_port"), a.get("to_port"),
                a.get("referenced_security_group_id") or a.get("source_security_group_id"),
                a.get("cidr_ipv4") or (a.get("cidr_blocks") or [None])[0],
            ))
        elif rtype == "aws_vpc_security_group_egress_rule":
            e = _entry(a.get("security_group_id", ""))
            e["egress"].append(_rule(
                a.get("ip_protocol"), a.get("from_port"), a.get("to_port"),
                a.get("referenced_security_group_id"), a.get("cidr_ipv4"),
            ))
    return table, vpc_cidrs


def _cidr_covers_vpc(cidr: str | None, vpc_cidrs: list[str]) -> bool:
    """True if an SG-rule CIDR admits an in-VPC host (0.0.0.0/0, or a superset of a VPC CIDR)."""
    if not cidr:
        return False
    if cidr == "0.0.0.0/0":
        return True
    try:
        rule_net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return False
    for vc in vpc_cidrs:
        try:
            if ipaddress.ip_network(vc, strict=False).subnet_of(rule_net):
                return True
        except ValueError:
            continue
    return False


def _match_sg_ids(table: dict, suffix: str) -> set[str]:
    """SG ids whose group-name / Name tag contains the suffix (e.g. 'app-sg', 'db-sg')."""
    return {sid for sid, e in table.items() if any(suffix in n for n in e["names"])}


def _rules_admitting_source(rules: list[dict], source_sgs: set[str], vpc_cidrs: list[str]) -> list[dict]:
    """Ingress rules that admit the source (by SG reference or a VPC-covering CIDR)."""
    return [r for r in rules if (r["ref"] in source_sgs) or _cidr_covers_vpc(r["cidr"], vpc_cidrs)]


def _rules_reaching_target(rules: list[dict], target_sgs: set[str], vpc_cidrs: list[str]) -> list[dict]:
    """Egress rules that reach the target (by SG reference or a VPC-covering CIDR)."""
    return [r for r in rules if (r["ref"] in target_sgs) or _cidr_covers_vpc(r["cidr"], vpc_cidrs)]


def _ports_overlap(a: dict, b: dict) -> bool:
    lo_a, hi_a = _norm_port(a)
    lo_b, hi_b = _norm_port(b)
    return max(lo_a, lo_b) <= min(hi_a, hi_b)


def _network_reachable(source_sgs: set[str], target_sgs: set[str], table: dict, vpc_cidrs: list[str]) -> bool:
    """True if some port is permitted by BOTH source egress -> target AND target ingress <- source."""
    if not source_sgs or not target_sgs:
        return False
    target_ingress = []
    for t in target_sgs:
        target_ingress += table.get(t, {}).get("ingress", [])
    source_egress = []
    for s in source_sgs:
        source_egress += table.get(s, {}).get("egress", [])
    admitting = _rules_admitting_source(target_ingress, source_sgs, vpc_cidrs)
    reaching = _rules_reaching_target(source_egress, target_sgs, vpc_cidrs)
    return any(_ports_overlap(i, e) for i in admitting for e in reaching)


def _egress_permits_service(source_sgs: set[str], port: int, table: dict, vpc_cidrs: list[str], endpoint_sgs: set[str]) -> bool:
    """True if the foothold can egress `port` to the internet (public API) or a VPC endpoint SG.

    Models an AWS control-plane service (e.g. Secrets Manager) reachable either over the
    public endpoint (baseline all-egress) or an interface VPC endpoint (Zero Trust).
    """
    for s in source_sgs:
        for r in table.get(s, {}).get("egress", []):
            lo, hi = _norm_port(r)
            if not (lo <= port <= hi):
                continue
            if r["cidr"] == "0.0.0.0/0":
                return True
            if _cidr_covers_vpc(r["cidr"], vpc_cidrs):
                return True
            if r["ref"] in endpoint_sgs:
                return True
    return False


def _reachable_network_set(source: str, network_nodes: list[str], node_sgs: dict, table: dict, vpc_cidrs: list[str]) -> set[str]:
    """Network nodes transitively reachable from `source` via SG hops (excludes `source`)."""
    seen = {source}
    reached: set[str] = set()
    frontier = [source]
    while frontier:
        cur = frontier.pop()
        for tgt in network_nodes:
            if tgt in seen:
                continue
            if _network_reachable(node_sgs[cur], node_sgs[tgt], table, vpc_cidrs):
                seen.add(tgt)
                reached.add(tgt)
                frontier.append(tgt)
    return reached


def compute_lmcs(state_path: Path, weights_path: Path, single_source: str | None) -> dict:
    """LMCS from an offline Terraform state file + a criticality-weight spec.

    All-pairs blast-radius form (generalised Chapter 3 Eq 3.2): the index i ranges over
    ordered (source -> target) node pairs, V_i is the binary reachability of that pair, and
    W_i is the DESTINATION node's criticality weight. K_max = Σ_i W_i is the full-mesh
    maximum (the score if every node could reach every node). LMCS = (Σ V_i·W_i)/K_max
    ∈ [0, 1]; higher = less contained. Passing `single_source` restricts i to pairs whose
    source is that one node, recovering the original single-foothold Eq 3.2 as a special case.
    """
    spec = yaml.safe_load(weights_path.read_text())
    nodes_spec: dict = spec.get("nodes") or {}
    if not nodes_spec:
        raise SystemExit(f"No 'nodes' defined in {weights_path}")

    state = json.loads(state_path.read_text())
    table, vpc_cidrs = _build_sg_table(state)

    node_sgs: dict[str, set[str]] = {}
    for name, cfg in nodes_spec.items():
        suffix = cfg.get("sg_suffix")
        node_sgs[name] = _match_sg_ids(table, suffix) if suffix else set()

    # A VPC-endpoint SG is an alternative egress destination for 'service' nodes.
    endpoint_sgs = _match_sg_ids(table, spec.get("endpoint_sg_suffix", "vpce-sg"))
    network_nodes = [n for n, c in nodes_spec.items() if c.get("reachability", "network") == "network"]

    # Sources = tiers an attacker can traverse FROM (network nodes with a security group).
    # Derived nodes (colocated / service) have no SG of their own, so they are targets only.
    sources = list(network_nodes)
    if single_source is not None:
        if single_source not in nodes_spec:
            raise SystemExit(f"--foothold '{single_source}' is not a defined node in {weights_path}")
        if single_source not in network_nodes:
            raise SystemExit(f"--foothold '{single_source}' has no security group; it cannot originate traffic")
        sources = [single_source]

    def _pair_reachable(source: str, target: str, reached: set[str]) -> bool:
        cfg = nodes_spec[target]
        kind = cfg.get("reachability", "network")
        if kind == "network":
            return target in reached
        if kind == "colocated":
            host = cfg.get("host")
            return host == source or host in reached
        if kind == "service":
            return _egress_permits_service(node_sgs[source], int(cfg.get("port", 443)), table, vpc_cidrs, endpoint_sgs)
        raise SystemExit(f"Unknown reachability '{kind}' for node '{target}' in {weights_path}")

    matrix: dict[str, dict] = {}
    reachable_pairs: list[list[str]] = []
    weighted_reachable = 0.0
    k_max = 0.0
    for s in sources:
        reached = _reachable_network_set(s, network_nodes, node_sgs, table, vpc_cidrs)
        row: dict[str, bool] = {}
        for t, cfg in nodes_spec.items():
            if t == s:
                continue
            w_t = float(cfg.get("weight", 0))
            reachable = _pair_reachable(s, t, reached)
            k_max += w_t  # every ordered pair contributes W_t to the full-mesh maximum
            row[t] = reachable
            if reachable:
                weighted_reachable += w_t
                reachable_pairs.append([s, t])
        matrix[s] = row

    if k_max <= 0:
        raise SystemExit("K_max (Σ W_i) is zero; check the weights file / node set.")

    return {
        "metric": "LMCS",
        "mode": "single-foothold" if single_source is not None else "all-pairs",
        "lmcs": round(weighted_reachable / k_max, 4),
        "weighted_reachable": weighted_reachable,
        "k_max": k_max,
        "sources": sources,
        "reachability_matrix": matrix,
        "reachable_pairs": reachable_pairs,
        "nodes": {
            name: {
                "weight": float(cfg.get("weight", 0)),
                "reachability": cfg.get("reachability", "network"),
                "is_source": name in sources,
                "resolved_sg_count": len(node_sgs[name]),
            }
            for name, cfg in nodes_spec.items()
        },
        "source_state": str(state_path),
        "weights": str(weights_path),
    }


# ===========================================================================
# MTTD — Mean Time To Detect
# ===========================================================================
def _parse_ts(value) -> datetime:
    """Parse an ISO-8601 timestamp (accepts trailing Z and Wazuh's +0000 offset)."""
    s = str(value).strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    # Wazuh writes offsets without a colon, e.g. 2026-07-14T12:00:05.123+0000
    m = re.search(r"([+-]\d{2})(\d{2})$", s)
    if m and s[-3] != ":":
        s = s[: m.start()] + m.group(1) + ":" + m.group(2)
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        dt = datetime.strptime(s.split(".")[0].split("+")[0], "%Y-%m-%dT%H:%M:%S")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _alert_rule_id(alert: dict) -> str:
    return str(((alert.get("rule") or {}).get("id")) or alert.get("rule_id") or "")


def _alert_mitre_ids(alert: dict) -> set[str]:
    mitre = ((alert.get("rule") or {}).get("mitre") or {})
    ids = mitre.get("id") or []
    if isinstance(ids, str):
        ids = [ids]
    return {str(i) for i in ids}


def compute_mttd(actions_path: Path, alerts_path: Path, signatures_path: Path) -> dict:
    """MTTD from an attack-action log vs Wazuh alerts, correlated by signature map."""
    sig_spec = yaml.safe_load(signatures_path.read_text()) or {}
    sig_by_tech: dict[str, dict] = {}
    for entry in sig_spec.get("signatures", []):
        tech = entry.get("technique")
        if not tech:
            continue
        sig_by_tech[tech] = {
            "rule_ids": {str(r) for r in (entry.get("rule_ids") or [])},
            "mitre_ids": {str(m) for m in (entry.get("mitre_ids") or [])},
        }

    actions = _read_jsonl(actions_path)
    if not actions:
        raise SystemExit(f"No attack actions in {actions_path}")
    alerts = _read_jsonl(alerts_path)  # empty if Wazuh disabled/undeployed

    parsed_alerts = []
    for al in alerts:
        ts = al.get("timestamp") or al.get("@timestamp")
        if not ts:
            continue
        parsed_alerts.append({
            "time": _parse_ts(ts),
            "rule_id": _alert_rule_id(al),
            "mitre_ids": _alert_mitre_ids(al),
        })

    matched = []
    unmatched = []
    for action in actions:
        tech = action.get("technique")
        t_exec = _parse_ts(action["t_execute"])
        sig = sig_by_tech.get(tech, {"rule_ids": set(), "mitre_ids": set()})
        best = None
        for al in parsed_alerts:
            if al["time"] < t_exec:
                continue  # a detection cannot precede the action
            if al["rule_id"] in sig["rule_ids"] or (al["mitre_ids"] & sig["mitre_ids"]):
                if best is None or al["time"] < best["time"]:
                    best = al
        if best is None:
            unmatched.append(action.get("action_id", tech))
        else:
            matched.append({
                "action_id": action.get("action_id", tech),
                "technique": tech,
                "delay_seconds": (best["time"] - t_exec).total_seconds(),
                "rule_id": best["rule_id"],
            })

    n_attempted = len(actions)
    n_detected = len(matched)
    delays = [m["delay_seconds"] for m in matched]

    return {
        "metric": "MTTD",
        # Speed over DETECTED actions only; undetected excluded (not counted as ~0).
        "mttd_seconds": round(statistics.mean(delays), 2) if delays else None,
        "median_seconds": round(statistics.median(delays), 2) if delays else None,
        "min_seconds": round(min(delays), 2) if delays else None,
        "max_seconds": round(max(delays), 2) if delays else None,
        "n_detected": n_detected,
        "n_attempted": n_attempted,
        "detection_coverage": round(n_detected / n_attempted, 4) if n_attempted else 0.0,
        "matched": matched,
        "unmatched_actions": unmatched,
        "sources": {
            "actions": str(actions_path),
            "alerts": str(alerts_path),
            "signatures": str(signatures_path),
        },
    }


def _resolve_input(pattern: str) -> Path:
    """Accept a direct path or a glob (Prowler compliance filenames embed account IDs)."""
    p = Path(pattern)
    if p.is_file():
        return p
    matches = sorted(glob.glob(pattern))
    if not matches:
        raise SystemExit(f"No file matched: {pattern}")
    return Path(matches[-1])


def _emit(result: dict, output: str | None) -> None:
    text = json.dumps(result, indent=2)
    if output:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        Path(output).write_text(text + "\n")
    print(text)


def main() -> int:
    parser = argparse.ArgumentParser(description="Compute dissertation evaluation metrics.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_cbcs = sub.add_parser("cbcs", help="CBCS from a Prowler CIS compliance CSV.")
    p_cbcs.add_argument("--input", required=True, help="Prowler CIS compliance CSV path or glob.")
    p_cbcs.add_argument("--output", help="Write result JSON here (e.g. metrics/data/cbcs_baseline.json).")

    p_cdi = sub.add_parser("cdi", help="CDI from baseline vs current CBCS files.")
    p_cdi.add_argument("--baseline", required=True, help="Baseline CBCS JSON (post first deploy).")
    p_cdi.add_argument("--current", required=True, help="Current CBCS JSON (post drift injection).")
    p_cdi.add_argument("--output", help="Write result JSON here.")

    p_asr = sub.add_parser("asr", help="ASR from Nuclei findings + Stratus results.")
    p_asr.add_argument("--nuclei", help="Nuclei -jsonl output path.")
    p_asr.add_argument("--stratus", help="Stratus results JSONL path (one record per technique).")
    p_asr.add_argument("--nuclei-templates-run", type=int,
                       help="Templates Nuclei executed (true N_total for the Nuclei channel).")
    p_asr.add_argument("--severity-threshold", default="medium",
                       choices=list(_SEVERITY_ORDER), help="Min Nuclei severity counted as success.")
    p_asr.add_argument("--output", help="Write result JSON here.")

    p_lmcs = sub.add_parser("lmcs", help="LMCS from an offline Terraform state SG graph.")
    p_lmcs.add_argument("--state", required=True, help="Terraform state file (terraform.tfstate).")
    p_lmcs.add_argument("--weights", required=True, help="Criticality-weight spec (lmcs_weights.yaml).")
    p_lmcs.add_argument("--foothold", help="Restrict to a single source node (recovers the single-foothold Eq 3.2). Default: all-pairs.")
    p_lmcs.add_argument("--output", help="Write result JSON here.")

    p_mttd = sub.add_parser("mttd", help="MTTD from an attack-action log vs Wazuh alerts.")
    p_mttd.add_argument("--actions", required=True, help="attack_actions.jsonl (action_id, technique, t_execute).")
    p_mttd.add_argument("--alerts", required=True, help="Wazuh alerts.json (JSON-lines).")
    p_mttd.add_argument("--signatures", required=True, help="Signature map (mttd_signatures.yaml).")
    p_mttd.add_argument("--output", help="Write result JSON here.")

    args = parser.parse_args()

    if args.command == "cbcs":
        result = compute_cbcs(_resolve_input(args.input))
    elif args.command == "cdi":
        result = compute_cdi(Path(args.baseline), Path(args.current))
    elif args.command == "asr":
        if not args.nuclei and not args.stratus:
            parser.error("asr needs at least one of --nuclei / --stratus")
        result = compute_asr(
            _resolve_input(args.nuclei) if args.nuclei else None,
            _resolve_input(args.stratus) if args.stratus else None,
            args.severity_threshold,
            args.nuclei_templates_run,
        )
    elif args.command == "lmcs":
        result = compute_lmcs(_resolve_input(args.state), Path(args.weights), args.foothold)
    elif args.command == "mttd":
        # Alerts may be absent when Wazuh is not deployed; tolerate a missing file
        # (compute_mttd then reports 0 detections / null MTTD rather than crashing).
        alerts_matches = sorted(glob.glob(args.alerts))
        alerts_path = Path(alerts_matches[-1]) if alerts_matches else Path(args.alerts)
        result = compute_mttd(_resolve_input(args.actions), alerts_path, Path(args.signatures))
    else:  # pragma: no cover
        parser.error("unknown command")

    _emit(result, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
