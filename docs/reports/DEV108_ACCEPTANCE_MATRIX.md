# Dev108 acceptance matrix — preinstall review

Independent current review: **102 PASS, 2 PENDING_ACTIVATED** (DOC-03 and DBG-18), no blockers before sealing. All original104 requirement fields and historical audit statuses remain verbatim in JSON. Actual activated checks remain NOT_TESTED until the external final receipt.

| Check | Exact requirement | Historical scoped status | Current preinstall | Final release |
| --- | --- | --- | --- | --- |
| ICON-01 | real searchable icons and visible thumbnails | PASS | PASS | NOT_TESTED |
| ICON-02 | positive and negative PNG/SVG import tests | PASS | PASS | NOT_TESTED |
| ICON-03 | icon selection with visual state and fallback | PASS | PASS | NOT_TESTED |
| ICON-04 | icon+text/icon-only/text-only | PASS | PASS | NOT_TESTED |
| ICON-05 | proper disabled/hover/selected states | PARTIAL | PASS | NOT_TESTED |
| ICON-06 | scaling/HiDPI/theme and narrow window screenshot review | PARTIAL | PASS | NOT_TESTED |
| ICON-07 | accessible keyboard/tooltip behavior | PASS | PASS | NOT_TESTED |
| ICON-08 | Save/Open exact IDs/assets/SHA | PASS | PASS | NOT_TESTED |
| ICON-09 | Undo/Redo/duplicate/reparent retains icon bindings | PASS | PASS | NOT_TESTED |
| ICON-10 | generated ZIP asset inclusion and no broken absolute paths | PASS | PASS | NOT_TESTED |
| ICON-11 | actual installed Viewer visually matches Builder | PASS | PASS | NOT_TESTED |
| ICON-12 | no commands/handlers changed by icon editing | PASS | PASS | NOT_TESTED |
| ICON-13 | negative oversize/symlink/unsafe SVG/resource rejection | PASS | PASS | NOT_TESTED |
| ICON-14 | intact pre-dev108 designs and Builder Gallery/Native3D regression | PARTIAL | PASS | NOT_TESTED |
| DBG-01 | fresh GUI full editor | PASS | PASS | NOT_TESTED |
| DBG-02 | precise aligned line numbers/folding/red-dot breakpoint | PASS | PASS | NOT_TESTED |
| DBG-03 | set/remove/toggle breakpoint mouse + keyboard | PASS | PASS | NOT_TESTED |
| DBG-04 | actual stop on source line | PASS | PASS | NOT_TESTED |
| DBG-05 | visible distinct active-line arrow | PASS | PASS | NOT_TESTED |
| DBG-06 | real Step Into | PASS | PASS | NOT_TESTED |
| DBG-07 | real Step Over | PASS | PASS | NOT_TESTED |
| DBG-08 | real Step Out | PASS | PASS | NOT_TESTED |
| DBG-09 | Continue to next breakpoint | PARTIAL | PASS | NOT_TESTED |
| DBG-10 | genuine Pause if claimed supported, otherwise exact visible limitation and applicable CORE gap | PASS | PASS | NOT_TESTED |
| DBG-11 | Stop/cancel with owned worker reaped | PASS | PASS | NOT_TESTED |
| DBG-12 | stack/frame/locals grounded in real backend | PASS | PASS | NOT_TESTED |
| DBG-13 | rejected/stale source cannot be debugged using old binary | PASS | PASS | NOT_TESTED |
| DBG-14 | show/hide/reopen debugger via View menu without GUI damage | PASS | PASS | NOT_TESTED |
| DBG-15 | build/run/debug cycles in narrow, wide, DPI/theme configurations with actual screenshots | PARTIAL | PASS | NOT_TESTED |
| DBG-16 | no side effect on real scientific user Sessions | PARTIAL | PASS | NOT_TESTED |
| DBG-17 | unchanged Python/Octave GUI/debugger regressions | PASS | PASS | NOT_TESTED |
| DBG-18 | installed release full GUI cycle, documentation and helpful errors | PARTIAL | PENDING_ACTIVATED | NOT_TESTED |
| SPICE-01 | genuinely different subagent identity and restricted project/write boundary receipt | PASS | PASS | NOT_TESTED |
| SPICE-02 | all source/design authored via development workspace and Builder, no private Tcl | PASS | PASS | NOT_TESTED |
| SPICE-03 | source AST/SDK validates, and known forbidden operations fail | PARTIAL | PASS | NOT_TESTED |
| SPICE-04 | genuine generated/installed standard Viewer | PASS | PASS | NOT_TESTED |
| SPICE-05 | visually usable schema and icon controls | PARTIAL | PASS | NOT_TESTED |
| SPICE-06 | create/place/move/rotate/delete circuit components | PASS | PASS | NOT_TESTED |
| SPICE-07 | accurate wire drag/connect/junction/crossing and stable IDs | PARTIAL | PASS | NOT_TESTED |
| SPICE-08 | edit values/units/labels with rejection for invalid values | PARTIAL | PASS | NOT_TESTED |
| SPICE-09 | exact Undo/Redo across edits and no document corruption | PARTIAL | PASS | NOT_TESTED |
| SPICE-10 | save/reopen same schematic/viewport/element identities | PARTIAL | PASS | NOT_TESTED |
| SPICE-11 | deterministic annotated SPICE netlist and topology checks | PARTIAL | PASS | NOT_TESTED |
| SPICE-12 | real local ngspice `.op` Job | PASS | PASS | NOT_TESTED |
| SPICE-13 | real local `.tran` Job and RC analytic error check | PASS | PASS | NOT_TESTED |
| SPICE-14 | real local `.ac` or `.dc` Job and RLC/other numerical check | PASS | PASS | NOT_TESTED |
| SPICE-15 | true remote node discovery and destination choice, provider identity demonstrated | PASS | PASS | NOT_TESTED |
| SPICE-16 | actual authenticated remote Job completion/reconnect/log/result retrieval | PASS | PASS | NOT_TESTED |
| SPICE-17 | remote cancel/error/offline tested without invented local fallback | PARTIAL | PASS | NOT_TESTED |
| SPICE-18 | local-vs-remote numerical parity on same circuit (tolerances declared), or explicit NOT TESTED with cause if no real node | PASS | PASS | NOT_TESTED |
| SPICE-19 | canonical Dataset publication with units/source/job provenance through public APIs | PASS | PASS | NOT_TESTED |
| SPICE-20 | real Plot waveform/probe/cursor and meaningful graphical screenshots | PARTIAL | PASS | NOT_TESTED |
| SPICE-21 | installed GUI full end-to-end cycle at two viewport sizes with visually inspected outcomes | PARTIAL | PASS | NOT_TESTED |
| SPICE-22 | documentation, source project, gap receipts, circuit examples and all retained CORE preservation checks | PARTIAL | PASS | NOT_TESTED |
| GAP-01 | subagent requests a real missing capability | PASS | PASS | NOT_TESTED |
| GAP-02 | request includes reproducible denied call | PASS | PASS | NOT_TESTED |
| GAP-03 | primary owner audits current API families | PASS | PASS | NOT_TESTED |
| GAP-04 | existing family extended where possible | PASS | PASS | NOT_TESTED |
| GAP-05 | new family (if any) independently justified or none created | PASS | PASS | NOT_TESTED |
| GAP-06 | version compatibility and legacy clients retained | PARTIAL | PASS | NOT_TESTED |
| GAP-07 | public descriptors and manuals current | PARTIAL | PASS | NOT_TESTED |
| GAP-08 | approved restricted SDK/AST modified only by primary agent | PARTIAL | PASS | NOT_TESTED |
| GAP-09 | same denied subagent scenario passes after authorized change | PARTIAL | PASS | NOT_TESTED |
| GAP-10 | remote/local, Job, Plot, Dataset/Document owners unchanged | PASS | PASS | NOT_TESTED |
| GAP-11 | reports enumerate every gap and each code/API delta | PARTIAL | PASS | NOT_TESTED |
| GAP-12 | bad input, stale Session, cancellation and denied unauthorized operations remain rejected | PARTIAL | PASS | NOT_TESTED |
| GUI-01 | screenshot after each icon-UI change and correct alignment | PARTIAL | PASS | NOT_TESTED |
| GUI-02 | narrow/high-DPI icon states | PARTIAL | PASS | NOT_TESTED |
| GUI-03 | real pointer/keyboard icon selection and action dispatch | PASS | PASS | NOT_TESTED |
| GUI-04 | breakpoint red dot + folding + line numbers no collision | PASS | PASS | NOT_TESTED |
| GUI-05 | C++ debug toolbar/variables/stack/menu View, full close/reopen | PASS | PASS | NOT_TESTED |
| GUI-06 | actual simulated schematic screenshot with labels/wires/components and no overlap | PARTIAL | PASS | NOT_TESTED |
| GUI-07 | dragging, wiring and node probe via GUI, not script-only | PARTIAL | PASS | NOT_TESTED |
| GUI-08 | local and remote Job panels with state/results | PARTIAL | PASS | NOT_TESTED |
| GUI-09 | actual waveform Plot display, range/units and saved reopen | PASS | PASS | NOT_TESTED |
| GUI-10 | visual/functional regression of previously delivered Python/Octave editors, Builder Gallery and Native3D | PARTIAL | PASS | NOT_TESTED |
| DOC-01 | standalone WordPress ZIP delivered outside framework with exact dev107 SHA | PASS | PASS | NOT_TESTED |
| DOC-02 | extracted IT/EN articles, examples, image links and manifest verified | PASS | PASS | NOT_TESTED |
| DOC-03 | ZIP absent from new dev108 framework archive and activated installation, historical dev107 archive untouched | PARTIAL | PENDING_ACTIVATED | NOT_TESTED |
| DOC-04 | no runtime Help references to extracted-only asset | PASS | PASS | NOT_TESTED |
| DOC-05 | Python Help → About works with correct installed metadata | PASS | PASS | NOT_TESTED |
| DOC-06 | Octave Help → About works | PASS | PASS | NOT_TESTED |
| DOC-07 | Dev Workspace Help → About works | PASS | PASS | NOT_TESTED |
| DOC-08 | three Help/Manual actions survive close/reopen and narrow GUI layouts | PASS | PASS | NOT_TESTED |
| DOC-09 | Python complete per-control inline manual with genuine illustrations and worked examples | PARTIAL | PASS | NOT_TESTED |
| DOC-10 | Octave complete per-control inline manual | PARTIAL | PASS | NOT_TESTED |
| DOC-11 | Dev Workspace full C++ debugger/manual screenshots | PARTIAL | PASS | NOT_TESTED |
| DOC-12 | independent mounted GUI walkthrough validates documented shortcuts, panels and commands match installed behavior | PARTIAL | PASS | NOT_TESTED |
| NUM-01 | enumerate existing installed PUBLIC GX-TXT Numeric/Mathematical/Statistical operations applicable to circuit computations | PASS | PASS | NOT_TESTED |
| NUM-02 | independently check real local and remote approved CORE API and ngspice/provider capabilities without any NumPy dependency/probe | PASS | PASS | NOT_TESTED |
| NUM-03 | launch multiple parameter-sweep jobs through existing CORE admission/worker policy | PASS | PASS | NOT_TESTED |
| NUM-04 | user-visible queue/progress/cancel/reconnect with no private thread pool | PARTIAL | PASS | NOT_TESTED |
| NUM-05 | compute and verify actual ngspice waveform values, units, interpolation/array operations and analytical checks EXCLUSIVELY via public GX-TXT Numeric/Mathematical APIs | PASS | PASS | NOT_TESTED |
| NUM-06 | canonical Dataset publication and public Plot use correct arrays, units and provenance | PASS | PASS | NOT_TESTED |
| NUM-07 | negative overload/partial failure/stale snapshot preserves previous scientific state | PARTIAL | PASS | NOT_TESTED |
| NUM-08 | real local/remote sweep comparisons with true CORE Job references (else explicitly NOT TESTED) | PASS | PASS | NOT_TESTED |
| NUM-09 | static and runtime checks show **zero new NumPy imports, direct calls, sidecars or dependencies** in all dev108 SPICE/subagent/trusted-worker/test deliverables, while the restricted Development Workspace exposes only specifically admitted GX-TXT public Numeric operations. Any NumPy use in new code is FAIL, not N/A | PARTIAL | PASS | NOT_TESTED |
| GROW-01 | subagent's first unsupported schematic action yields a genuine CORE_API_GAP via the allowed development tools | PASS | PASS | NOT_TESTED |
| GROW-02 | documented failed public Builder component/event evidence exists before CORE change | PASS | PASS | NOT_TESTED |
| GROW-03 | primary agent extends a CURRENT reusable public owner instead of independent SPICE GUI helper | PASS | PASS | NOT_TESTED |
| GROW-04 | same component/event becomes available in Builder Gallery/Designer with correct property/event API and native runtime | PARTIAL | PASS | NOT_TESTED |
| GROW-05 | same approved facility becomes available in restricted Dev Workspace SDK/parser and is exercised by unchanged policy-compliant C++ author code | PARTIAL | PASS | NOT_TESTED |
| GROW-06 | primary independently verifies subagent built standard installed Viewer and full GUI edit/simulate/probe cycle, including screenshots and numeric results | PARTIAL | PASS | NOT_TESTED |
| GROW-07 | capability delta matrix shows which non-SPICE Viewer can reuse each new operation, tests no parallel API/renderer/Job path, and records all other gaps as unfinished rather than quietly removing them | PARTIAL | PASS | NOT_TESTED |
