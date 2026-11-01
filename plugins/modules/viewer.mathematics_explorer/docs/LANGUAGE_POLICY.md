# GX-TXT Mathematics Explorer — language policy and audit

**Authoritative source language: English (en).**

This policy applies to every user-visible label, menu, dialog, tooltip, message,
help page, module description, test instruction, and scientific term.

- Write user-facing text in English **at initial development time**. Never treat
  a translation from Italian as the authoritative English source.
- Future translations must use stable localization keys, consistent terminology,
  checked placeholders, and reviewed catalogs. English must be the fallback.
- Mixed-language controls, untranslated strings, missing keys, and inconsistent
  scientific terminology are release-blocking defects.
- Scientific identifiers, variable names, Dataset IDs, and mathematical syntax
  are data/contracts, not translatable interface text.
- Each release must run a source-language audit and manually inspect dynamic
  Tcl strings, dialogs, status messages, previews, and documentation. A simple
  vocabulary scan is only a *guardrail*, not proof of complete localization.

## Prototype 0.1.0 correction

Audit of the isolated source bundle revealed that `docs/USER_GUIDE.md` had been
written in Italian. It has been rewritten in English without changing the
scientific scope, source code, or existing module identity.

At the time of this correction, Tcl/Tk UI labels, numerical error messages,
module metadata, and the other development documents were inspected and found
written in English. **The prototype still contains English strings embedded in
Tcl source rather than a centralized localization catalog.** Therefore it is
English-first but **does not yet meet the stricter future catalog requirement**.
This is recorded explicitly rather than reported as a completed i18n migration.

## Pre-integration localization acceptance

1. Run `python3 tests/test_language_policy.py` from the module directory.
2. Manually inspect every visible Tk control and error path in the running viewer.
3. Before adding a second language, extract all strings to an English source
   catalog, assign stable keys, validate placeholders, and add catalog coverage
   tests. Do not introduce translation-only changes to numerical algorithms.
4. Record separately the language-audit result and the real GX-TXT scientific
   integration result. Do not report either as PASS without testing it.
