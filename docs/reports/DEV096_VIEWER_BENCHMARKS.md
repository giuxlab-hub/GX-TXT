# dev096 extracted-package Viewer measurements

SPDX-License-Identifier: GPL-3.0-or-later

Nine serial real-GUI runs compare accepted095 and the second fresh096 extraction
on the same hardware, each in a fresh process and independent private copies of
the existing 413797-row complex-path fixture. No other acceptance/audit workload
ran during this benchmark sequence. Canonical source SHA-256:
`c60641fd101937603af37ac8b9fb36fc8bdbb480bcca761c114d2e333a76ebce`.

| Curves | Cache | dev095 all-ready (s) | dev096 all-ready (s) | Open (ms) | First prepared (ms) | First native draw (ms) | RSS / HWM (KiB) | Session disk (bytes) | Exact science |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 6 | cold | 4.177 | 5.536 | 118.5 | 682.9 | 711.3 | 57904 / 58964 | 16652289 | PASS |
| 6 | warm | 4.177 | 1.854 | 133.3 | 249.1 | 893.7 | 55892 / 57976 | 16652289 | PASS |
| 25 | cold | 17.316 | 22.789 | 119.5 | 710.2 | 738.8 | 110604 / 120764 | 17741981 | PASS |
| 25 | warm | 17.316 | 6.809 | 182.4 | 297.6 | 3309.4 | 102180 / 114764 | 17741981 | PASS |
| 101 | cold | 80.695 | 103.706 | 127.8 | 699.9 | 728.4 | 325472 / 365192 | 22254360 | PASS |
| 101 | warm | 80.695 | 25.846 | 382.6 | 501.4 | 12655.6 | 291932 / 344564 | 22254360 | PASS |

Warm all-ready improvement is 2.25×, 2.54×, 3.12× for 6/25/101
curves respectively. Cold preparation is slower because it creates validated
managed buffers. First native draw on larger warm Workspaces is also slower than
the initial cold first curve; the measured improvement is in complete Workspace
readiness, not every startup metric. The window returns promptly, and the
separate partial-load cancellation/Session-switch test verifies responsiveness.

Every comparison checks identical logical curve IDs, displayed point counts,
XY values/order, breaks, extrema and source-row identity fields against095, plus
the canonical source SHA. Per-source preparation, Native2D construction, source
validation, nested stage samples and diagnostics are in each `benchmark.tcldict`;
nested timings must not be summed as independent work. RSS and peak HWM are
process readings, and disk bytes cover the complete private Session rather than
an invented per-curve incremental cache cost. Baseline resource readings and all
six complete per-field comparison receipts are also retained.

Evidence: `package-benchmarks1/results.json`, the nine logs and Tcl receipts,
six `*-comparison.json` files and owned-window screenshots. Final release product
parity proves that the delivered Viewer/CORE bytes equal this tested extraction.

`package-cache-lifecycle2` additionally verifies unsupported-version and changed
filter fallback, one legitimate CORE-published Dataset revision with unaffected
entries reused, and native F8 Cancel/window close/public Session switch during
actual partial loading. Saved Workspace payloads remain exact; all source tokens
and jobs are released, and late callbacks do not populate the new Session.
Missing, truncated/corrupt and escaping-resource fallback, portable owner
remapping, History/clear and exact canonical publication are covered by
`package-gui2/viewer-history` and the retained Curve Viewer native regressions.

The earlier development benchmark report is retained in Git history and its
original `viewer-timing2-*` receipts remain available; these figures are the
extracted-package measurements used for this release.
