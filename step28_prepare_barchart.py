#!/usr/bin/env python3
"""Prepare and certify the Barchart input panel for Step 28.

This stage is deliberately outcome-free.  It maps the frozen logical Eurex
contracts to Barchart symbols, audits every raw contract file, selects the
contract using only the pre-PR grid, and writes the canonical five-minute
Schatz--Bobl--Bund panel.  It does not estimate factors, Markov tests or SBB
costs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable
from zoneinfo import ZoneInfo


SCHEMA = "step28_barchart_data_v1"
BAR_MINUTES = 5
RAW_TIME_ZONE = "America/Chicago"
RAW_BAR_LABEL = "interval_start"
CANONICAL_TIME_ZONE = "UTC"
CANONICAL_BAR_LABEL = "interval_end"
RAW_PRICE_FIELD = "Latest"
CANONICAL_PRICE_FIELD = "Close"
MIN_COVERAGE = 0.80
MIN_RETURNS = 5
ASSET_ROOTS = {"schatz": "hf", "bobl": "hr", "bund": "gg"}
MONTH_CODES = {3: "h", 6: "m", 9: "u", 12: "z"}
EXPECTED_HEADER = [
    "Time", "Open", "High", "Low", "Latest", "Change", "%Change", "Volume"
]
FILE_PATTERN = re.compile(
    r"^([a-z]+)([hmuz])(\d{2})_intraday-(\d+)min_"
    r"historical-data-(\d{2})-(\d{2})-(\d{4})\.csv$"
)


@dataclass(frozen=True)
class Bar:
    time_utc: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("data_root", type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, rows: Iterable[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def parse_utc(text: str) -> datetime:
    return datetime.strptime(text.strip(), "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=timezone.utc
    )


def fmt_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def logical_to_symbol(asset: str, year: int, month: int) -> str:
    return f"{ASSET_ROOTS[asset]}{MONTH_CODES[month]}{year % 100:02d}"


def manifest_row(path: Path) -> dict[str, str]:
    rows = read_csv(path)
    if len(rows) != 1:
        raise ValueError(f"expected one manifest row: {path}")
    return rows[0]


def audit_time_manifests(data_root: Path) -> tuple[bool, list[dict]]:
    manifest_dir = data_root / "Output" / "manifests"
    time_path = manifest_dir / "time_alignment_manifest.csv"
    semantics_path = manifest_dir / "window_semantics_manifest.csv"
    audit = []

    time_ok = False
    if time_path.is_file():
        row = manifest_row(time_path)
        time_ok = (
            row.get("status") == "complete"
            and row.get("raw_provider") == "Barchart"
            and row.get("raw_time_zone") == RAW_TIME_ZONE
            and row.get("analysis_time_zone") == CANONICAL_TIME_ZONE
        )
    audit.append(check_row("time_alignment_manifest", True, time_ok,
                           "certified Barchart America/Chicago to UTC", time_path))

    semantics_ok = False
    if semantics_path.is_file():
        row = manifest_row(semantics_path)
        semantics_ok = (
            row.get("status") == "certified"
            and row.get("raw_time_zone") == RAW_TIME_ZONE
            and row.get("analysis_time_zone") == CANONICAL_TIME_ZONE
            and row.get("bar_label_semantics") == RAW_BAR_LABEL
            and row.get("canonical_bar_time") == "interval_end_utc"
        )
    audit.append(check_row("window_semantics_manifest", True, semantics_ok,
                           "certified interval_start to interval_end_utc", semantics_path))
    return time_ok and semantics_ok, audit


def check_row(check_id: str, binding: bool, passed: bool, required: str,
              source: Path | str, observed: str | None = None) -> dict:
    source_path = Path(source) if source else None
    return {
        "check_id": check_id,
        "binding": int(binding),
        "pass": int(passed),
        "observed": observed if observed is not None else ("pass" if passed else "fail"),
        "required": required,
        "source_file": str(source_path) if source_path else "",
        "source_sha256": sha256(source_path) if source_path and source_path.is_file() else "missing",
    }


def expected_times(start: datetime, end: datetime) -> list[datetime]:
    count = int((end - start).total_seconds() // (BAR_MINUTES * 60)) + 1
    return [start + timedelta(minutes=BAR_MINUTES * i) for i in range(count)]


def read_and_audit_contract(
    path: Path, requested_ranges: list[tuple[datetime, datetime]]
) -> tuple[dict, dict[datetime, Bar]]:
    header_ok = False
    footer_present = False
    data_rows = 0
    bad_shape = 0
    bad_datetime = 0
    missing_core = 0
    nonpositive_price = 0
    negative_volume = 0
    ohlc_inconsistency = 0
    duplicate_timestamps = 0
    first_provider = None
    last_provider = None
    previous_provider = None
    sort_sign = 0
    unsorted = False
    seen = set()
    retained: dict[datetime, Bar] = {}
    chicago = ZoneInfo(RAW_TIME_ZONE)

    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        header = next(csv.reader([stream.readline().rstrip("\r\n")]), [])
        header_ok = header == EXPECTED_HEADER
        for raw_line in stream:
            raw_line = raw_line.rstrip("\r\n")
            if not raw_line.strip():
                continue
            if raw_line.lstrip('"').startswith("Downloaded from Barchart.com"):
                footer_present = True
                continue
            row = next(csv.reader([raw_line]), [])
            if len(row) != 8:
                bad_shape += 1
                continue
            data_rows += 1
            try:
                provider_time = datetime.strptime(row[0], "%Y-%m-%d %H:%M")
            except ValueError:
                bad_datetime += 1
                continue
            try:
                values = [float(row[i].replace(",", "")) for i in (1, 2, 3, 4, 7)]
            except ValueError:
                missing_core += 1
                continue
            open_, high, low, close, volume = values
            if min(open_, high, low, close) <= 0:
                nonpositive_price += 1
            if volume < 0:
                negative_volume += 1
            if not (high >= max(open_, low, close) and low <= min(open_, high, close)):
                ohlc_inconsistency += 1
            if provider_time in seen:
                duplicate_timestamps += 1
            seen.add(provider_time)
            if previous_provider is not None and provider_time != previous_provider:
                sign = 1 if provider_time > previous_provider else -1
                if sort_sign == 0:
                    sort_sign = sign
                elif sign != sort_sign:
                    unsorted = True
            previous_provider = provider_time
            first_provider = provider_time if first_provider is None else min(first_provider, provider_time)
            last_provider = provider_time if last_provider is None else max(last_provider, provider_time)

            canonical_time = (
                provider_time.replace(tzinfo=chicago).astimezone(timezone.utc)
                + timedelta(minutes=BAR_MINUTES)
            )
            if any(start <= canonical_time <= end for start, end in requested_ranges):
                retained[canonical_time] = Bar(
                    canonical_time, open_, high, low, close, volume
                )

    structural = all([
        header_ok, footer_present, data_rows > 0, bad_shape == 0,
        bad_datetime == 0, missing_core == 0, nonpositive_price == 0,
        negative_volume == 0, ohlc_inconsistency == 0,
        duplicate_timestamps == 0, not unsorted,
    ])
    audit = {
        "file_name": path.name,
        "source_sha256": sha256(path),
        "data_rows": data_rows,
        "first_provider_time": first_provider.strftime("%Y-%m-%d %H:%M:%S") if first_provider else "",
        "last_provider_time": last_provider.strftime("%Y-%m-%d %H:%M:%S") if last_provider else "",
        "header_ok": int(header_ok),
        "footer_present": int(footer_present),
        "bad_row_shape": bad_shape,
        "bad_datetime": bad_datetime,
        "missing_core": missing_core,
        "nonpositive_price": nonpositive_price,
        "negative_volume": negative_volume,
        "ohlc_inconsistency": ohlc_inconsistency,
        "duplicate_timestamps": duplicate_timestamps,
        "timestamp_unsorted": int(unsorted),
        "structurally_valid": int(structural),
        "status": "certified" if structural else "failed_structure",
    }
    return audit, retained


def return_measure(
    bars: dict[datetime, Bar], anchor: datetime,
    first_endpoint: int, last_endpoint: int
) -> dict:
    endpoints = [
        anchor + timedelta(minutes=offset)
        for offset in range(first_endpoint, last_endpoint + 1, BAR_MINUTES)
    ]
    present = [
        endpoint in bars and endpoint - timedelta(minutes=BAR_MINUTES) in bars
        for endpoint in endpoints
    ]
    n_present = sum(present)
    adjacent = sum(present[i - 1] and present[i] for i in range(1, len(present)))
    coverage = n_present / len(present) if present else math.nan
    eligible = (
        coverage >= MIN_COVERAGE
        and n_present >= MIN_RETURNS
        and adjacent >= max(MIN_RETURNS - 1, 1)
    )
    volume = sum(bars[t].volume for t in endpoints if t in bars)
    return {
        "expected_returns": len(endpoints),
        "observed_returns": n_present,
        "coverage": coverage,
        "adjacent_pairs": adjacent,
        "volume": volume,
        "eligible": eligible,
    }


def add_measure(row: dict, prefix: str, measure: dict) -> None:
    for key, value in measure.items():
        row[f"{prefix}_{key}"] = int(value) if isinstance(value, bool) else value


def main() -> int:
    args = parse_args()
    data_root = args.data_root.expanduser().resolve()
    raw_dir = data_root / "Raw" / "Barchart_futures"
    acquisition_dir = data_root / "Output" / "step28_history_acquisition"
    output_dir = data_root / "Output" / "step28_sbbts"
    output_dir.mkdir(parents=True, exist_ok=True)

    inputs = {
        "links": acquisition_dir / "step28_event_control_links.csv",
        "targets": acquisition_dir / "step28_target_dates.csv",
        "contracts": acquisition_dir / "step28_lseg_contract_map.csv",
        "requests": acquisition_dir / "step28_lseg_request_windows.csv",
    }
    missing_inputs = [str(path) for path in inputs.values() if not path.is_file()]
    if missing_inputs:
        raise FileNotFoundError("missing frozen acquisition inputs: " + " | ".join(missing_inputs))
    if not raw_dir.is_dir():
        raise FileNotFoundError(f"missing raw Barchart directory: {raw_dir}")

    links = read_csv(inputs["links"])
    targets = read_csv(inputs["targets"])
    contracts = read_csv(inputs["contracts"])
    requests = read_csv(inputs["requests"])
    target_by_date = {row["trade_date"]: row for row in targets}

    contract_rows = []
    required_symbols = set()
    symbol_meta = {}
    for row in contracts:
        asset = row["asset_id"].strip().lower()
        symbol = logical_to_symbol(asset, int(row["expiry_year"]), int(row["expiry_month"]))
        out = {
            key: value for key, value in row.items()
            if key not in {"vendor_ric", "mapping_status", "mapping_evidence"}
        }
        out["data_provider"] = "Barchart"
        out["vendor_symbol"] = symbol.upper()
        out["mapping_status"] = "verified_by_symbol_rule"
        out["mapping_evidence"] = "Barchart root plus quarterly month code plus two-digit year"
        contract_rows.append(out)
        required_symbols.add(symbol)
        symbol_meta[symbol] = out

    request_rows = []
    requests_by_symbol: dict[str, list[dict]] = defaultdict(list)
    for row in requests:
        asset = row["asset_id"].strip().lower()
        symbol = logical_to_symbol(asset, int(row["expiry_year"]), int(row["expiry_month"]))
        out = {key: value for key, value in row.items() if key != "vendor_ric"}
        out["data_provider"] = "Barchart"
        out["vendor_symbol"] = symbol.upper()
        out["request_start_utc_dt"] = parse_utc(row["request_start_utc"])
        out["request_end_utc_dt"] = parse_utc(row["request_end_utc"])
        request_rows.append(out)
        requests_by_symbol[symbol].append(out)

    files_by_symbol: dict[str, list[Path]] = defaultdict(list)
    ignored_files = []
    for path in sorted(raw_dir.glob("*.csv")):
        match = FILE_PATTERN.match(path.name.lower())
        if not match:
            ignored_files.append({"file_name": path.name, "parsed_symbol": "", "reason": "filename_not_recognised"})
            continue
        symbol = "".join(match.group(i) for i in (1, 2, 3))
        frequency = int(match.group(4))
        if symbol in required_symbols and frequency == BAR_MINUTES:
            files_by_symbol[symbol].append(path)
        else:
            ignored_files.append({
                "file_name": path.name,
                "parsed_symbol": symbol.upper(),
                "reason": "outside_frozen_step28_universe",
            })

    file_audit = []
    bars_by_symbol: dict[str, dict[datetime, Bar]] = {}
    file_identity = {}
    for symbol in sorted(required_symbols):
        meta = symbol_meta[symbol]
        matches = files_by_symbol.get(symbol, [])
        base = {
            "asset_id": meta["asset_id"],
            "logical_contract_id": meta["logical_contract_id"],
            "vendor_symbol": symbol.upper(),
            "matching_files": len(matches),
        }
        if len(matches) != 1:
            base.update({
                "file_name": "|".join(path.name for path in matches),
                "source_sha256": "",
                "data_rows": 0,
                "first_provider_time": "",
                "last_provider_time": "",
                "header_ok": 0,
                "footer_present": 0,
                "bad_row_shape": 0,
                "bad_datetime": 0,
                "missing_core": 0,
                "nonpositive_price": 0,
                "negative_volume": 0,
                "ohlc_inconsistency": 0,
                "duplicate_timestamps": 0,
                "timestamp_unsorted": 0,
                "structurally_valid": 0,
                "status": "missing" if not matches else "duplicate_symbol",
            })
            file_audit.append(base)
            bars_by_symbol[symbol] = {}
            continue
        ranges = [
            (row["request_start_utc_dt"], row["request_end_utc_dt"])
            for row in requests_by_symbol[symbol]
        ]
        audit, retained = read_and_audit_contract(matches[0], ranges)
        base.update(audit)
        file_audit.append(base)
        bars_by_symbol[symbol] = retained
        file_identity[symbol] = (matches[0].name, audit["source_sha256"])

    candidate_rows = []
    candidates_by_group: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for request in request_rows:
        symbol = request["vendor_symbol"].lower()
        bars = bars_by_symbol.get(symbol, {})
        target = target_by_date[request["trade_date"]]
        pr_anchor = parse_utc(target["pseudo_pr_datetime_utc"])
        selection = return_measure(bars, pr_anchor, -55, -5)
        grid = expected_times(request["request_start_utc_dt"], request["request_end_utc_dt"])
        row = {key: value for key, value in request.items() if not key.endswith("_dt")}
        row["source_file"] = file_identity.get(symbol, ("", ""))[0]
        row["source_sha256"] = file_identity.get(symbol, ("", ""))[1]
        row["request_grid_expected_bars"] = len(grid)
        row["request_grid_observed_bars"] = sum(t in bars for t in grid)
        row["request_grid_complete"] = int(all(t in bars for t in grid))
        add_measure(row, "selection_pre", selection)
        candidate_rows.append(row)
        candidates_by_group[(request["trade_date"], request["asset_id"])].append(row)

    selected_rows = []
    selected_by_group = {}
    canonical_rows = []
    coverage_rows = []
    for key in sorted(candidates_by_group):
        candidates = candidates_by_group[key]
        candidates.sort(key=lambda row: (
            -int(row["selection_pre_eligible"]),
            -float(row["selection_pre_coverage"]),
            -float(row["selection_pre_volume"]),
            int(row["candidate_rank"]),
        ))
        chosen = candidates[0]
        selected_by_group[key] = chosen
        selected = {
            "trade_date": chosen["trade_date"],
            "sample_role": chosen["sample_role"],
            "asset_id": chosen["asset_id"],
            "candidate_rank": chosen["candidate_rank"],
            "logical_contract_id": chosen["logical_contract_id"],
            "data_provider": "Barchart",
            "vendor_symbol": chosen["vendor_symbol"],
            "source_file": chosen["source_file"],
            "source_sha256": chosen["source_sha256"],
            "selection_pre_coverage": chosen["selection_pre_coverage"],
            "selection_pre_volume": chosen["selection_pre_volume"],
            "selection_pre_eligible": chosen["selection_pre_eligible"],
        }
        selected_rows.append(selected)

        symbol = chosen["vendor_symbol"].lower()
        bars = bars_by_symbol.get(symbol, {})
        target = target_by_date[chosen["trade_date"]]
        pr_anchor = parse_utc(target["pseudo_pr_datetime_utc"])
        pc_anchor = parse_utc(target["pseudo_pc_datetime_utc"])
        phase_specs = {
            "PR": (pr_anchor, (-55, -5), (5, 25)),
            "PC": (pc_anchor, (-25, -5), (5, 45)),
        }
        for phase, (anchor, pre_range, post_range) in phase_specs.items():
            pre = return_measure(bars, anchor, pre_range[0], pre_range[1])
            post = return_measure(bars, anchor, post_range[0], post_range[1])
            coverage = dict(selected)
            coverage["phase"] = phase
            coverage["anchor_utc"] = fmt_utc(anchor)
            add_measure(coverage, "pre", pre)
            add_measure(coverage, "post", post)
            coverage["phase_eligible"] = int(
                bool(selected["selection_pre_eligible"])
                and pre["eligible"] and post["eligible"]
            )
            coverage_rows.append(coverage)

        request = next(
            row for row in requests_by_symbol[symbol]
            if row["trade_date"] == chosen["trade_date"]
        )
        for time_utc in expected_times(request["request_start_utc_dt"], request["request_end_utc_dt"]):
            bar = bars.get(time_utc)
            if bar is None:
                continue
            canonical_rows.append({
                "trade_date": chosen["trade_date"],
                "sample_role": chosen["sample_role"],
                "asset_id": chosen["asset_id"],
                "candidate_rank": chosen["candidate_rank"],
                "logical_contract_id": chosen["logical_contract_id"],
                "data_provider": "Barchart",
                "vendor_symbol": chosen["vendor_symbol"],
                "bar_end_utc": fmt_utc(time_utc),
                "Open": bar.open,
                "High": bar.high,
                "Low": bar.low,
                "Close": bar.close,
                "Volume": bar.volume,
                "source_file": chosen["source_file"],
                "source_sha256": chosen["source_sha256"],
            })

    phase_lookup = {
        (row["trade_date"], row["asset_id"], row["phase"]): bool(int(row["phase_eligible"]))
        for row in coverage_rows
    }
    date_phase_rows = []
    usable_lookup = {}
    for trade_date in sorted(target_by_date):
        target = target_by_date[trade_date]
        for phase in ("PR", "PC"):
            asset_flags = {
                asset: phase_lookup.get((trade_date, asset, phase), False)
                for asset in ASSET_ROOTS
            }
            usable = all(asset_flags.values())
            usable_lookup[(trade_date, phase)] = usable
            date_phase_rows.append({
                "trade_date": trade_date,
                "sample_role": target["sample_role"],
                "phase": phase,
                "schatz_eligible": int(asset_flags["schatz"]),
                "bobl_eligible": int(asset_flags["bobl"]),
                "bund_eligible": int(asset_flags["bund"]),
                "three_asset_eligible": int(usable),
            })

    controls_by_event: dict[str, list[str]] = defaultdict(list)
    for row in links:
        controls_by_event[row["event_date"]].append(row["control_date"])
    support_rows = []
    for event_date in sorted(controls_by_event):
        for phase in ("PR", "PC"):
            controls = controls_by_event[event_date]
            usable_controls = [date for date in controls if usable_lookup.get((date, phase), False)]
            dropped_controls = [date for date in controls if date not in usable_controls]
            support_rows.append({
                "event_date": event_date,
                "phase": phase,
                "event_usable": int(usable_lookup.get((event_date, phase), False)),
                "n_original_controls": len(controls),
                "n_usable_controls": len(usable_controls),
                "usable_control_dates": "|".join(usable_controls),
                "dropped_control_dates": "|".join(dropped_controls),
                "control_rule": "exclude_incomplete_without_replacement_equal_reweight",
            })

    contract_map_path = output_dir / "step28_barchart_contract_map.csv"
    requests_path = output_dir / "step28_barchart_request_windows.csv"
    file_audit_path = output_dir / "step28_barchart_file_audit.csv"
    ignored_path = output_dir / "step28_barchart_ignored_files.csv"
    candidate_path = output_dir / "step28_candidate_coverage.csv"
    selected_path = output_dir / "step28_selected_contracts.csv"
    bars_path = output_dir / "step28_canonical_bars.csv"
    coverage_path = output_dir / "step28_phase_coverage.csv"
    date_phase_path = output_dir / "step28_date_phase_intersection.csv"
    support_path = output_dir / "step28_event_control_support.csv"

    write_csv(contract_map_path, contract_rows, list(contract_rows[0]))
    request_output_rows = [
        {key: value for key, value in row.items() if not key.endswith("_dt")}
        for row in request_rows
    ]
    write_csv(requests_path, request_output_rows, list(request_output_rows[0]))
    write_csv(file_audit_path, file_audit, list(file_audit[0]))
    write_csv(ignored_path, ignored_files, ["file_name", "parsed_symbol", "reason"])
    write_csv(candidate_path, candidate_rows, list(candidate_rows[0]))
    write_csv(selected_path, selected_rows, list(selected_rows[0]))
    write_csv(bars_path, canonical_rows, list(canonical_rows[0]))
    write_csv(coverage_path, coverage_rows, list(coverage_rows[0]))
    write_csv(date_phase_path, date_phase_rows, list(date_phase_rows[0]))
    write_csv(support_path, support_rows, list(support_rows[0]))

    time_ok, gate_audit = audit_time_manifests(data_root)
    n_present = sum(int(row["matching_files"]) == 1 for row in file_audit)
    n_valid = sum(bool(row["structurally_valid"]) for row in file_audit)
    counts_ok = (
        len(contracts) == 165 and len(requests) == 6672 and len(targets) == 556
        and len(links) == 1020
    )
    files_ok = n_present == len(contracts) and n_valid == len(contracts)
    gate_audit.extend([
        check_row("frozen_inventory_counts", True, counts_ok,
                  "165 contracts; 6672 requests; 556 dates; 1020 links",
                  inputs["contracts"],
                  f"{len(contracts)} contracts; {len(requests)} requests; "
                  f"{len(targets)} dates; {len(links)} links"),
        check_row("required_contract_files", True, files_ok,
                  "exactly one structurally valid 5-minute file for each of 165 contracts",
                  file_audit_path, f"{n_present}/165 present; {n_valid}/165 valid"),
        check_row("canonical_price_field", True, True,
                  "Barchart Latest mapped to canonical Close", bars_path,
                  "Latest -> Close"),
        check_row("canonical_bar_clock", True, True,
                  "America/Chicago interval-start labels converted to UTC interval-end",
                  bars_path, "America/Chicago + 5 minutes -> UTC"),
        check_row("irregular_intervals_as_unit", True, True,
                  "only exact five-minute endpoint pairs are transitions",
                  coverage_path, "not used"),
        check_row("incomplete_control_rule", True, True,
                  "exclude without replacement and equal-reweight survivors",
                  support_path,
                  "exclude_incomplete_without_replacement_equal_reweight"),
    ])
    ready = time_ok and counts_ok and files_ok

    for row in gate_audit:
        source = Path(row["source_file"])
        if source.is_absolute():
            try:
                row["source_file"] = str(source.relative_to(data_root))
            except ValueError:
                pass

    audit_path = output_dir / "step28_data_gate_audit.csv"
    write_csv(audit_path, gate_audit, list(gate_audit[0]))

    def count_dates(role: str, phase: str) -> int:
        return sum(
            int(row["three_asset_eligible"])
            for row in date_phase_rows
            if row["sample_role"] == role and row["phase"] == phase
        )

    manifest = {
        "schema_version": SCHEMA,
        "status": "certified" if ready else "blocked",
        "data_provider": "Barchart",
        "raw_time_zone": RAW_TIME_ZONE,
        "raw_bar_label_semantics": RAW_BAR_LABEL,
        "canonical_time_zone": CANONICAL_TIME_ZONE,
        "canonical_bar_label_semantics": CANONICAL_BAR_LABEL,
        "frequency_minutes": BAR_MINUTES,
        "raw_price_field": RAW_PRICE_FIELD,
        "canonical_price_field": CANONICAL_PRICE_FIELD,
        "n_required_contracts": len(contracts),
        "n_present_contracts": n_present,
        "n_valid_contracts": n_valid,
        "n_ignored_raw_files": len(ignored_files),
        "n_target_dates": len(targets),
        "n_event_dates": sum(row["sample_role"] == "event" for row in targets),
        "n_control_dates": sum(row["sample_role"] == "matched_control" for row in targets),
        "n_pr_event_dates_usable": count_dates("event", "PR"),
        "n_pc_event_dates_usable": count_dates("event", "PC"),
        "n_pr_control_dates_usable": count_dates("matched_control", "PR"),
        "n_pc_control_dates_usable": count_dates("matched_control", "PC"),
        "control_rule": "exclude_incomplete_without_replacement_equal_reweight",
        "contract_selection_rule": "pre_pr_coverage_then_volume_then_nearest_expiry",
        "contracts_input_sha256": sha256(inputs["contracts"]),
        "requests_input_sha256": sha256(inputs["requests"]),
        "targets_input_sha256": sha256(inputs["targets"]),
        "links_input_sha256": sha256(inputs["links"]),
        "file_audit_sha256": sha256(file_audit_path),
        "canonical_bars_sha256": sha256(bars_path),
        "phase_coverage_sha256": sha256(coverage_path),
        "code_sha256": sha256(Path(__file__).resolve()),
        "primary_panel_ready": int(ready),
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "python_version": sys.version.split()[0],
    }
    manifest_path = output_dir / "step28_barchart_data_manifest.csv"
    write_csv(manifest_path, [manifest], list(manifest))

    failed = [row["check_id"] for row in gate_audit if row["binding"] and not row["pass"]]
    decision = {
        "schema_version": "step28_data_gate_v2",
        "status": "pass_data_gate" if ready else "blocked_data_gate",
        "ready_for_sample_size_gate": int(ready),
        "failed_checks": "|".join(failed),
        "next_action": (
            "freeze and run outcome-free spectral sample-size calibration"
            if ready else "repair the failed data checks and rerun Step 28"
        ),
        "data_provider": "Barchart",
        "data_manifest_sha256": sha256(manifest_path),
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    decision_path = output_dir / "step28_data_gate_decision.csv"
    write_csv(decision_path, [decision], list(decision))

    print("\n================ STEP 28 BARCHART DATA GATE ================")
    print(f"Required contracts       : {n_present}/{len(contracts)} present")
    print(f"Structurally valid       : {n_valid}/{len(contracts)}")
    print(f"Ignored raw files        : {len(ignored_files)}")
    print(f"PR usable event dates    : {manifest['n_pr_event_dates_usable']}/102")
    print(f"PC usable event dates    : {manifest['n_pc_event_dates_usable']}/102")
    print(f"PR usable control dates  : {manifest['n_pr_control_dates_usable']}/454")
    print(f"PC usable control dates  : {manifest['n_pc_control_dates_usable']}/454")
    print(f"Data-gate status         : {decision['status']}")
    print(f"Output directory         : {output_dir}")
    print("============================================================")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
