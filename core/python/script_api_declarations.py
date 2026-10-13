#!/usr/bin/env python3
"""Discover literal GX-TXT API requirements without executing script source."""
from __future__ import annotations

import ast
from pathlib import Path
import re
import sys

REQUIREMENT = re.compile(r"[A-Za-z0-9_]+(?:@[0-9]+)?(?::[A-Za-z0-9._-]+)?(?:\+[A-Za-z0-9_|.-]+)?\Z")
OCTAVE_CALL = re.compile(
    r"gxtxt_api_require\s*\(\s*(\{(?:\s|[,;]|'[^']*'|\"[^\"]*\")*\}|'[^']*'|\"[^\"]*\")\s*\)",
    re.DOTALL,
)
OCTAVE_STRING = re.compile(r"'([^']*)'|\"([^\"]*)\"")


def octave_literal_calls(source: str):
    """Find literal calls outside Octave comments and quoted source text."""
    i = 0
    block = None
    while i < len(source):
        if block is not None:
            end = source.find(block, i)
            if end < 0:
                return
            i = end + len(block)
            block = None
            continue
        if source.startswith(("%{", "#{"), i) and not source[source.rfind("\n", 0, i) + 1:i].strip():
            block = source[i] + "}"
            i += 2
            continue
        char = source[i]
        if char in "%#":
            end = source.find("\n", i)
            i = len(source) if end < 0 else end + 1
            continue
        if char in "'\"":
            quote = char
            i += 1
            while i < len(source):
                if source[i] == quote:
                    if i + 1 < len(source) and source[i + 1] == quote:
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        if source.startswith("gxtxt_api_require", i) and (i == 0 or not (source[i - 1].isalnum() or source[i - 1] == "_")):
            call = OCTAVE_CALL.match(source, i)
            if call:
                yield call.group(1)
                i = call.end()
                continue
        i += 1


def literals(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple)) and all(isinstance(item, str) for item in value):
        return list(value)
    return []


def discover(source: str, language: str) -> list[str]:
    found = []
    if language == "Python":
        tree = ast.parse(source)
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name) or node.func.id != "gxtxt_api_require" or not node.args:
                continue
            try:
                found.extend(literals(ast.literal_eval(node.args[0])))
            except (ValueError, TypeError, SyntaxError, MemoryError, RecursionError):
                continue
    elif language == "Octave":
        for argument in octave_literal_calls(source):
            found.extend(a or b for a, b in OCTAVE_STRING.findall(argument))
    else:
        raise ValueError(f"Unsupported script language: {language}")
    for item in found:
        if not REQUIREMENT.fullmatch(item):
            raise ValueError(f"Invalid literal GX-TXT API requirement: {item}")
    return sorted(set(found))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: script_api_declarations.py LANGUAGE SOURCE_PATH")
    code = Path(sys.argv[2]).read_text(encoding="utf-8-sig")
    print(";".join(discover(code, sys.argv[1])))
