#!/usr/bin/env python3
"""Static GX-TXT script Analysis Source declarations (public contract v1)."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


MARKER = "GX-TXT-ANALYSIS-SOURCES-V1:"
SOURCE_ID = re.compile(r"[A-Za-z][A-Za-z0-9_]*\Z")
CONTRACT = re.compile(r"[A-Za-z][A-Za-z0-9_.-]*\Z")
DATASET_ID = re.compile(r"[A-Za-z][A-Za-z0-9_.-]*\Z")


def _single(value: object, field: str, *, required: bool = False) -> str:
    if not isinstance(value, str) or any(ch in value for ch in "\r\n\t\x00"):
        raise ValueError(f"{field} must be a single-line string")
    if required and not value.strip():
        raise ValueError(f"{field} is required")
    return value.strip()


def normalize(payload: object) -> dict:
    """Validate one language-neutral declaration without executing script code."""
    if not isinstance(payload, dict) or set(payload) != {"api_version", "sources"}:
        raise ValueError("declaration needs only api_version and sources")
    if type(payload["api_version"]) is not int or payload["api_version"] != 1:
        raise ValueError("unsupported Analysis Sources declaration version")
    raw = payload["sources"]
    if not isinstance(raw, list) or not raw or len(raw) > 32:
        raise ValueError("sources must contain 1 to 32 entries")
    seen: set[str] = set()
    sources: list[dict] = []
    allowed = {"id", "label", "required", "contracts", "purpose", "preferred_dataset"}
    for item in raw:
        if not isinstance(item, dict) or set(item) - allowed:
            raise ValueError("source entry has unsupported fields")
        sid = _single(item.get("id"), "source id", required=True)
        if not SOURCE_ID.fullmatch(sid) or sid in seen:
            raise ValueError(f"invalid or duplicate source id: {sid}")
        seen.add(sid)
        label = _single(item.get("label"), f"{sid} label", required=True)
        required = item.get("required")
        if type(required) is not bool:
            raise ValueError(f"{sid} required must be a JSON boolean")
        contracts = item.get("contracts")
        if not isinstance(contracts, list) or not contracts:
            raise ValueError(f"{sid} contracts must be a nonempty list")
        if len(contracts) > 16:
            raise ValueError(f"{sid} has too many contracts")
        contracts = [_single(value, f"{sid} contract", required=True) for value in contracts]
        if any(not CONTRACT.fullmatch(value) for value in contracts) or len(set(contracts)) != len(contracts):
            raise ValueError(f"{sid} has invalid or duplicate contracts")
        purpose = _single(item.get("purpose", ""), f"{sid} purpose")
        preferred = _single(item.get("preferred_dataset", ""), f"{sid} preferred_dataset")
        if preferred and not DATASET_ID.fullmatch(preferred):
            raise ValueError(f"{sid} preferred_dataset is not a canonical Dataset ID")
        sources.append({"id": sid, "label": label, "required": required,
                        "contracts": contracts, "purpose": purpose, "preferred_dataset": preferred})
    if "primary" not in seen or not next(s for s in sources if s["id"] == "primary")["required"]:
        raise ValueError("primary is required by the Analysis Source Map")
    return {"api_version": 1, "sources": sources}


def discover(source: Path) -> dict | None:
    """Read one comment metadata line from Python or Octave source, never run it."""
    source = Path(source)
    if source.suffix.lower() not in {".py", ".m"}:
        raise ValueError("declarations require a .py or .m script")
    if source.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("script exceeds the 16 MiB static discovery limit")
    prefix = "#" if source.suffix.lower() == ".py" else "%"
    matches = []
    with source.open("r", encoding="utf-8-sig") as stream:
        for lineno, line in enumerate(stream, 1):
            stripped = line.lstrip()
            if MARKER not in stripped:
                continue
            if not stripped.startswith(prefix):
                raise ValueError(f"declaration at line {lineno} must be a {prefix} comment")
            body = stripped[1:].strip()
            if not body.startswith(MARKER):
                raise ValueError(f"invalid declaration marker at line {lineno}")
            encoded = body[len(MARKER):].strip()
            if len(encoded.encode("utf-8")) > 16384:
                raise ValueError("declaration exceeds 16 KiB")
            matches.append((lineno, encoded))
    if not matches:
        return None
    if len(matches) != 1:
        raise ValueError("script must have exactly one Analysis Sources declaration")
    lineno, encoded = matches[0]
    try:
        return normalize(json.loads(encoded))
    except (json.JSONDecodeError, ValueError) as exc:
        raise ValueError(f"invalid Analysis Sources declaration at line {lineno}: {exc}") from exc


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--tsv", action="store_true", help="emit validated tab-separated records for Tcl")
    args = parser.parse_args()
    result = discover(args.source)
    if args.tsv:
        if result:
            for item in result["sources"]:
                print("\t".join((item["id"], item["label"], str(int(item["required"])),
                                 ";".join(item["contracts"]), item["purpose"], item["preferred_dataset"])))
    else:
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
