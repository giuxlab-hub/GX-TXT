# Shared Runner control inventory

Author scope: MAIN1. Independent outcomes are recorded by the Low validation owner;
this inventory is not an acceptance assertion. All routes share
scriptWorkspaceRunDialog, scriptRunReviewOptions and scriptJobSubmit.

| ID | Visible operation | Owner/result | Required negative/lifecycle coverage |
|---|---|---|---|
| R01 | Script name/language/reference/version/revision/SHA, saved inert arguments | Read exact Registry metadata; no invocation | Dirty saved-source choice; changed source/schema/revision; Session replaced |
| R02 | Typed per-Job parameter entries, booleans, choice selectors, existing Reset/browse controls | uiFieldCreate/Normalize then scriptExecutionParameters | Required blank, wrong integer/range/choice, Unicode/quoted/empty strings; zero/many fields; reset default |
| R03 | Preset Dataset ID | Canonical ID in reviewed Session | Unknown/wrong contract/foreign Session/changed revision/integrity |
| R04 | Save label | Presentation metadata only | Empty/Unicode/long value; no Script default mutation |
| R05 | Save parameters as Dataset | Explicit create-only Publication; typed Schema3 Variables | Invalid value/name/collision/publication failure; cancel before Save; no automatic Job |
| R06 | Load parameters | Full schema/source/types/revision/hash validation then atomic form update | Missing/extra/wrong type/choice/stale Script; unchanged form on refusal |
| R07 | Inputs and output toggle | Presentation only | Hide/show retains all rows/values; scroll/focus |
| R08 | Add input Dataset | New per-row namespace/ID/alias/label/status/remove controls | Zero/many rows, empty namespace, no compatible ID |
| R09 | Semantic alias | Identifier scientific input identity | Empty/invalid/duplicate alias refuses; labels independent |
| R10 | Display label | Presentation only | Empty/long label; identity unchanged |
| R11 | Each Namespace selector | Filters that row only, clears old Dataset/revision | Other rows/Current unchanged; empty/long/deleted/moved namespace |
| R12 | Each Dataset selector/status | Captures exact revision | Changed/missing/moved/cross-Session/spoofed input; explicit reselection |
| R13 | Remove input | Drops request row only | Other rows retained, remove/re-add, post-collapse |
| R14 | Output ID/label | Optional request to original Publication | Existing ID/default create-only; invalid ID; original producer ownership |
| R15 | Owned replacement check | Deliberate existing authorized producer request | Foreign ownership/moved namespace denied; no input-derived rights |
| R16 | Validate review | Same typed/controller checks; no Job | Every invalid field actionable; no execution/publication |
| R17 | Rerun explicit review checkbox | Required only for previous-Job review | Historical immutable receipt preserved; changed bindings must reselect |
| R18 | Run Job and Ctrl+Return | Fresh async source/preset/input admission; immutable receipt | Duplicate submit, stale callback/closed/reopened review, errors; submitted distinct completed |
| R19 | Close, Escape, WM close | Dismiss review | No Job before Run, no cancellation claim after submit; reopen clean lifetime |
| R20 | Help | Actual native contextual explanation | Keyboard/dismiss/focus recovery |
| R21 | Scrollbar, wheel, Tab/Shift+Tab | Existing shared UI_FIELD scroll owner; fixed action/status | 480x360 and large window, 0/many fields/rows, large font; no unreachable controls |
| E01 | Editor View Parameters | Existing layout state, independent params packing | Both languages unsaved declarations/source/debug state retained; reopen preference |
| E02 | Editor View Script properties | Other metadata group only | Parameters stays independent; combined old saved layout migration |

Launcher matrix: Python Workspace, Octave Workspace, Script Library, main Run tab,
host Workspace Run control, Session Script Explorer, previous Job rerun. Real
Python and Octave Jobs each require three canonical inputs in base/lab/a/lab/b,
scientific readback, committed output, immutable source/bindings/typed preset
provenance and a cold reopen. Unchanged Publication shared CREATE-only grants
remain under their original public owner; output namespace does not come from inputs.
