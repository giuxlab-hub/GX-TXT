# Rotated Native2D title extent

MAIN2's registered descriptive-statistics Generator exposed a common Native2D
presentation defect in REG-0227/REG-0229. At actual Xft DPI144, its genuine five
voltage-variable Y title measured 849px high on a 447px Canvas, with bounds
`-2 -230 30 619`. Dataset IDs, source pairs, units and gaps were correct. The
original failure and the already passing322 baseline checks are preserved in
`/srv/gxtxt/checkpoints/dev109/main2_preview109/AR_NATIVE_Y_OWNER_REQUEST.json`.
Tk physical DPI remained75; this is not evidence of physical DPI144.

`core/tcl/native2d_presentation_v1.tcl` already wrapped horizontal titles but
assigned every rotated Y title the same x=14 position and no wrapping. It now
uses actual font metrics to reserve the rotated multiline title band beside
the existing tick-label margin. The horizontal and vertical requested margins
grow together, while the existing native view remains responsible for bounds
and calibrated aspect. Snapshot generation measures its final actual span,
retains the exact canonical text and supplies the same wrapping contract to
the existing opaque and alpha-text adapters. There is no new renderer, Viewer
workaround, scientific-data mutation, font reduction or native compilation.

The focused actual-Tk/precompiled component check is catalogued under
`validation/axis_long_y375/`. Its baseline reproduces clipped Y titles with
font14 and28. The first baseline's two photo-disposal checks also incorrectly
expected removal of an empty dictionary parent; that observer assertion was
corrected without changing product photo ownership. All original failures
remain preserved. Corrected checks cover full original captions, combined X/Y,
rotated opaque/alpha bounds, separation from ticks, repeatable layout and
readonly scene/snapshot state. Component checks do not establish installed
scientific GUI acceptance. At this initial report cutoff, MAIN2 still had to
repeat the original failed Generator-created Xft144 case on the integrated source.

The subsequent independent AS afterproof passed 115/115 checks using the same
registered descriptive-statistics Generator and canonical source. Actual
898 × 447 Canvas bounds now contain the full three-line Y caption at
`5 30 101 359`, separate from its ticks, with all 47 finite pairs and gap runs
unchanged. The earlier 322 passing baseline checks were retained without replay.
Compiler, linker, Native3D and Preview Job invocations were zero. Desktop-service
exit qualifications remain in the process receipt; this is not an all-zero
desktop-exit claim or physical144DPI proof. MAIN independently reviewed the
native frame and accepted this shared correction in
`/srv/gxtxt/checkpoints/dev109/axis_long_y375/ACCEPTANCE.json` (commit081e11ad).
