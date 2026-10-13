# Reusable Scientific Notes Editor

GX-TXT provides a reusable GX-Markup/Markdown View/Edit component for scientific documentation. In 0.9.7.69 this component remains in active use for Instrument notes and Instrument Library documentation.

## View first

Reusable-note windows normally open in **View mode**. The rendered document is derived from the authoritative UTF-8 markup source. Choose **Edit** only when the source must be changed.

## Edit mode

The reusable component provides:

- multiline source editing;
- UTF-8 preservation;
- undo and redo;
- vertical and horizontal scrolling;
- selectable wrapped or unwrapped source display;
- preserved indentation and line structure;
- H1/H2/H3 helpers;
- italic and bold helpers;
- inline code and fenced code blocks;
- GX-Markup color annotations;
- live/reloadable rendered preview;
- explicit Save and Cancel transitions.

The editor stores source without lossy conversion. Rendering never replaces the source.

## Experiment interface in 0.9.7.69

The Experiment page intentionally uses the established 0.9.7.67 inline notebook again. Its four distinct fields remain:

```text
Notes
Objective
Procedure / setup
Observations
```

Each field retains the existing inline GX-Markup source/preview behavior and existing Experiment persistence semantics. The separate View/Edit notes window introduced for Experiment in 0.9.7.68 is not used by the Experiment page in 0.9.7.69.

The broader roadmap requirement for one reusable scientific text-editor component across Instrument notes and all four Experiment fields is therefore **not complete** in 0.9.7.69 and remains in the live Remaining Work TODO.

## Instrument notes and Instrument Library documentation

Instrument Module fields named `notes` use the reusable View/Edit notes window. Existing Instrument Module schema and Experiment manifest persistence remain authoritative.

Instrument Library documentation uses the shared GX-Markup editor/renderer. Editing the global Library entry never silently rewrites an Experiment-specific historical instrument snapshot; synchronization remains explicit.
