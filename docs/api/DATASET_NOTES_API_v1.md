# GX-TXT Dataset Notes / GX-Markup v1

**Introduced:** GX-TXT Pipeline v0.9.2  
**License:** GPL-3.0-or-later

## Purpose

Every canonical Dataset ID may have a user-authored laboratory note. The note is distinct from producer-owned dataset metadata and does not alter data, hashes, provenance or units.

## Physical storage

Notes are real UTF-8 Markdown files inside the session:

```text
<session>/
└── notes/
    ├── datasets/
    │   ├── reactor.current.complete.md
    │   └── ...
    └── experiment/
        ├── notes.md
        ├── objective.md
        ├── procedure.md
        └── observations.md
```

Dataset association is indexed in `metadata/datasets.ini`:

```ini
user_notes_file=notes/datasets/reactor.current.complete.md
user_notes_format=gx-markup-v1
user_notes_updated_at=...
```

`user_notes_markup` is retained as a compatibility mirror for early v0.9.2 readers. When a `.md` file exists it is authoritative.

Because `notes/` is inside the session tree, normal session copies/exports include the notes together with the scientific data and metadata.

## Session files integration

The existing **Session files** tab lists `.md` files, therefore dataset and Experiment notes are directly browsable there. Selecting a note shows its source text. **Edit note...** opens the same GX-Markup editor used elsewhere in the framework.

Only Markdown documents under the session `notes/` tree are editable through this action; Session files remains a read-only browser for other files.

## Experiment notebook integration

The Experiment pages **Notes**, **Objective**, **Procedure / setup** and **Observations** use the same GX-Markup source/preview engine. Their text is persisted as the four `.md` files under `notes/experiment/` and mirrored in Manifest Format 2 for backward compatibility.

## GX-Markup v1

GX-Markup v1 is a small deterministic Markdown-like subset stored in `.md` files:

```text
# Heading 1
## Heading 2
### Heading 3
*italic*
**bold**
`inline code`
```

Fenced code blocks:

````text
```
code
```
````

Text color extension:

```text
[color=#C00000]important note[/color]
```

The common editor provides source + preview panes and toolbar actions for headings, italic, bold, inline code, fenced code blocks and color.

## Migration

If a session was saved by the first v0.9.2 implementation with `user_notes_markup` only, opening the session creates the corresponding `notes/datasets/*.md` file without changing the Dataset ID. Older Experiment notebook text stored only in `manifest.ini` is similarly materialized into `notes/experiment/*.md`.
