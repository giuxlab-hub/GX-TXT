#!/usr/bin/env python3
"""Guardrail for accidentally reintroduced Italian in GX-TXT viewer sources.

This is NOT an exhaustive multilingual/l10n audit. Manual GUI review is required.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# Deliberately exclude this guardrail from scanning, since it lists prohibited
# words as test data. LICENSE contains third-party legal text.
SOURCES = [
    path for path in ROOT.rglob("*")
    if path.is_file()
    and path.suffix.lower() in {".tcl", ".ini", ".md"}
    and path.name != "LICENSE"
]
# Avoid common English cognates and programming keywords. This catches known
# unwanted Italian GUI/help vocabulary, but it cannot prove English correctness.
ITALIAN_TERMS = re.compile(
    r"\b(?:guida iniziale|procedura|convenzioni numeriche|limiti intenzionali|"
    r"aprire|abilitare|modificare|inserire|calcola|salvare|ricarica|"
    r"funzioni|grafico|grafici|intervallo|campioni|derivata|integrale|"
    r"sinusoide|polinomio|esponenziale|gaussiana|cursori|unità|"
    r"pubblicazione genera|risultato più robusto|"
    r"questa versione|non include|prima versione|senza scrivere|"
    r"non è|scegliere|nessuna stima)\b",
    re.IGNORECASE,
)
ACCENTED_ITALIAN = re.compile(r"[àèéìòùÀÈÉÌÒÙ]")
errors = []
for path in sorted(SOURCES):
    if path.name == "LANGUAGE_POLICY.md":
        # This document legitimately discusses Italian as a topic in English.
        continue
    data = path.read_text(encoding="utf-8")
    for number, line in enumerate(data.splitlines(), 1):
        if ITALIAN_TERMS.search(line) or ACCENTED_ITALIAN.search(line):
            errors.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")

if errors:
    print("FAIL: possible untranslated Italian source text:\n" + "\n".join(errors))
    raise SystemExit(1)
print(f"PASS: no flagged Italian tokens in {len(SOURCES)} source/doc files; manual localization review remains necessary.")
