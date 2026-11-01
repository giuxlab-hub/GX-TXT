# Test and integration acceptance plan

## Tests actually performed, isolated ChatGPT artifact environment

- `tests/test_isolated.tcl`: Tcl source completeness, descriptor activation stub,
  controlled expression parser (including malicious characters), precedence,
  bounded sampling, public Numeric adapter structure with mocked operations,
  and integration/derivative dispatch against fake results.
- `tests/test_gui_smoke.tcl`: Xvfb/Tk window/control wiring, simulated graph PNG
  display, mocked integral output, and window close cleanup.
- `tests/test_publication_mock.tcl`: verifies public transactional publication
  command sequence, saved-document identity check, refusal of stale documents
  and error-path abort using fake CORE publication services.

**All three are mock tests, not tests of the real framework.** There has been no
Octave numerical accuracy run, real Plot Dataset renderer test, GX-TXT runtime
launch, genuine Session persistence test or genuine Dataset publication test.

## Required tests after an accepted GX-TXT release exists

1. Validate descriptor import and lazy viewer activation; confirm no ID
   collision and no Tk dependency during headless discovery.
2. Activate using a disposable Session. Check no open Session fails clearly;
   switch Session during an open viewer and verify save/publish are rejected.
3. Evaluate sine, polynomial and exponential with known reference points
   (e.g. `sin(0)=0`, `x^2` at ±2, `exp(0)=1`); inspect domain error handling.
4. Compare `NUMERIC_API_v1::integrate` on `x^2` from 0 to 1 against 1/3
   under 101, 301 and 901 samples. Report observed convergence and actual
   tolerance/error; do **not** declare exact integration.
5. Compare derivative for `sin(x)` to `cos(x)` at interior and endpoints;
   report maximum errors separately at fixed sampling steps.
6. Verify edits drive `renderTransientCurves2D` and that the full graph PNG
   is scrollable, messages are legible and the UI stays stable after errors.
7. Save two documents, close/restart GX-TXT, reload each by stable ID; test
   malformed/wrong-owner/state schema and Session isolation.
8. Publish an `x` + `f1` Dataset; inspect canonical row count and Variable IDs
   via Schema v3 and Canonical Dataset v2; render it through normal `plot.dataset`.
9. Attempt to publish an existing Dataset ID and verify **no replacement**.
   Inject a writer failure and verify CORE abort/registry consistency.
10. Check memory/CPU/latency for 32/301/1201 samples and repeated parameter
    changes; measure the effect of AST node count and synchronous Octave calls.
11. Run startup/discovery on Linux and record a reproducible GUI PASS with real
    GX-TXT version, module versions, source digests, Session and stack traces.
12. Separately obtain permission before any Windows compatibility checks.

**No actual integration PASS is claimed by this ZIP.**

## Language acceptance (English-first)

- Run `python3 tests/test_language_policy.py` as a limited lexical guardrail.
- Inspect the English-language user guide, all Tk UI labels and every reachable
  status/error dialog; verify consistent English scientific terminology.
- Treat missing English strings, accidental Italian, and inconsistent terminology
  as blocking defects. The current prototype has English hardcoded Tcl strings;
  a full catalog-based localization system is not yet implemented.
- If other languages are introduced, require complete English-key coverage and
  checked placeholders; preserve English as the authoritative fallback.
