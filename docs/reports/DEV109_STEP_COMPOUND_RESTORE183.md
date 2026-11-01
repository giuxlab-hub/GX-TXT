# Saved multi-solid STEP restoration

Independent installed successor QA reproduced `CAD176-MULTISOLID-REDO-01`:
accepting an extruded outer contour, hole and disconnected island produces a
valid two-solid object, but the first Redo rejects its saved STEP as multiple
occurrences. The canonical failed History state and actual screenshot are
preserved in `/srv/gxtxt/checkpoints/dev109/cad_successor_profiles176/`.

The former native `load_step` operation serves ordinary single-occurrence
intake. The shared Geometry API now also exposes explicit `restore_step` for
one previously saved canonical object. It uses the additive existing-engine
`gx3de_step_compound_create` C function to collect exact part geometry and world
placements without Boolean fusion. Workbench restoration selects this shared
operation. Ordinary external STEP intake and its occurrence-identity checks
remain unchanged. Existing document/resource ownership, physical-unit
normalization, placement, roles and staged rollback are retained.

The actual GUI-authored immutable input is 46,052 bytes, SHA-256
`45cc2ffc2fe117346a7300bba91604a84cc83d365d057928218c9e7f5e2c8f42`.
The new native engine/transport pass 59 focused checks: two closed solids,
area 848 mm², volume 848 mm³, exact bounds, centimetre normalization, saved
placement, complete STEP round trip, existing single-solid intake, malformed
resource/unit/owner rejection and normal scope closure. The original transport
correctly refuses the added operation; this component before-check is distinct
from the preserved original real-GUI Redo failure.

Build and actual test receipts:

- `/srv/gxtxt/agents/builds/dev109/native_step181/`
- `/srv/gxtxt/checkpoints/dev109/step_compound182/`
- `/srv/gxtxt/agents/tests/step_compound182_before/`
- `/srv/gxtxt/agents/tests/step_compound182_after/`

One development build of the changed shared engine and transport completed.
Its first wrapper returned 1 because it compared incidental weak libstdc++
template symbols emitted differently by O2 and CMake Release. All 46 missing
symbols are weak standard-library instantiations; every public engine export
and the Tcl initialization entrypoint is retained. The failed receipt remains
unchanged, and a separate continuation verifies linking and exact source pins;
no second compilation was performed for this qualification.

These are real native component checks, not installed GUI History acceptance.
The cold original Redo and normal saved-document reopening must still pass on
the matching integrated owner/binary batch. Full CAD parity and release
acceptance remain open.
