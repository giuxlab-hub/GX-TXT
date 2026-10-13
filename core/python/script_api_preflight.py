#!/usr/bin/env python3
"""Check registered script dependencies with the normal Script Bridge catalog."""
from __future__ import annotations

import configparser
from pathlib import Path
import re
import sys

from gxtxt_script_bridge_server import Host

REQUIREMENT = re.compile(r"^([A-Za-z0-9_]+)(?:@([0-9]+))?(?::([A-Za-z0-9._-]+))?(?:\+([A-Za-z0-9_|.-]+))?$")


def requirements(raw: str) -> list[dict]:
    result = []
    for token in raw.replace(",", ";").split(";"):
        token = token.strip()
        if not token:
            continue
        match = REQUIREMENT.fullmatch(token)
        if match is None:
            raise ValueError(f"Invalid required GX-TXT API: {token}")
        api_id, version, provider, capabilities = match.groups()
        item = {"api_id": api_id}
        if version is not None:
            item["api_version"] = int(version)
        if provider is not None:
            item["provider_id"] = provider
        if capabilities is not None:
            item["capabilities"] = capabilities.split("|")
        result.append(item)
    return result


def preflight(runtime_path: Path) -> None:
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(runtime_path, encoding="utf-8")
    Host(runtime_path).require(requirements(config.get("config", "required_apis", fallback="")))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: script_api_preflight.py RUNTIME_INI")
    try:
        preflight(Path(sys.argv[1]))
    except Exception as exc:
        raise SystemExit(f"GX-TXT API preflight failed: {exc}") from exc
