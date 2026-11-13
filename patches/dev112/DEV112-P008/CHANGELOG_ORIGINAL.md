# GX-TXT DEV112-P008 changes

Accepted source: f691b0f6e1016cb9af3db30ba3d1c8b5ea91429c. Full per-issue detail and exact file changes
are in ACCEPTANCE_MATRIX.json and MODIFIED_FILES.json.

The original P008 scope corrects 17 reproduced P007 defects and implements both
requested GUI improvements. Three original requirements needed no product fix:
P007-GUI-025 (backup-policy preview invalidation), P007-GUI-037 (empty queue
rebuilding with the current explicit composition ownership), and P007-GUI-038
(effective page settings projected from the authoritative current composition).
Those correct P007 behaviors are preserved.

P007-GUI-039 is a separate, reproduced Page Setup defect corrected by P008.
Recipe refresh now adopts the UIField committed baseline without adding History.
After refreshing an A3 recipe, choosing the prior A4 baseline applies A4 normally;
Undo, Redo and Save retain their existing behavior. This correction is distinct
from the already-correct effective composition projection in P007-GUI-038.

Supplementary changes address demonstrated layout, diagnostic, state-clarity,
search, preview and control-feedback findings through their existing owners.
They clarify persistent versus read-through connectors, saved versus draft roots,
Module state versus Viewer visibility, immediate commits and free-text Date
metadata. They preserve security refusal and scientific semantics. Inapplicable
Python imports and incomplete TeX/resource inventories receive truthful diagnostics.
Unnecessary changes are avoided for qualified environment-only or intentionally
working behavior. The matrix distinguishes code fixes, documentation/clarity
changes, existing shared corrections and no-change results individually.

Cumulative installation and authentic rollback reuse the established receipt,
preimage and integrity infrastructure with the exact P007 route added. There is
no owner installation activation, new dependency manager, scientific algorithm
rewrite, alternative registry/scheduler or excluded-project implementation.
