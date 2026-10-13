# Graph Notes API v1

Available in GX-TXT 0.9.8.10-dev-051. CORE service; no plugin activation is required.

A graph reference is a dictionary with `kind=provider`, `module_id`, `graph_id`, and `variant_id` (empty for a base graph), or `kind=clone` and `clone_id`. The provider graph must be declared, the Variant must exist, and a Clone must belong to the current Session. PNG filenames and list positions are not identity.

```tcl
set ref [dict create kind provider module_id plot.dataset graph_id plot.dataset.xy variant_id p0004]
::GX::graphNotesInfo $ref
::GX::graphNotesExists $ref
::GX::graphNotesRead $ref
::GX::graphNotesWrite $ref "# Experiment
Reviewed measurement."
::GX::graphNotesClear $ref
```

`info` returns `reference`, `exists`, `updated_at`, and `format=gx-markup-v1`. `read` returns UTF-8 Markdown; an absent note reads as empty text. `write` atomically replaces the Session-owned file and updates the normal Manifest association. `clear` removes the resource and association. No scientific Dataset or graph PNG is changed.

Base storage is `notes/graphs/<module>/<graph>/base/notes.md`; Variants use `.../variants/<variant>/notes.md`; Clones use `notes/graphs/clones/<clone>/notes.md`. CORE chooses and validates these paths. Callers supply references, never storage paths. Manifest sections `[graph_notes]` and `[graph_notes.N]` record the identity and Session-relative association. Notes appear in Session Files, Graph Info, and the standard GX-Markup editor opened by **Plots → Notes...** or the full-size viewer's **Notes...**.

Creating a Variant copies an existing base note; duplicating a Variant copies that Variant's note. The new note is independent. An absent source note creates no empty resource. Provider/API-created Variants use the same lifecycle. Clone creation copies the current graph note. Deletion cleans only the selected graph's resource. Graph Metadata follows the same copy/delete rules; annotations remain a separate resource.

Both Octave and Python Script Bridge expose `info`, `exists`, `read`, `write`, and `clear`, with the same graph-reference struct. Require `GRAPH_NOTES_API_v1@1:graph_notes` and call through `gxtxt_api_call`. File paths and copy internals are not exposed. For example:

```python
gxtxt_api_require('GRAPH_NOTES_API_v1@1:graph_notes')
gxtxt_api_call('GRAPH_NOTES_API_v1', 'write', [ref, '# Reviewed graph'])
```

HTML export creates a first-class graph-note page and graph backlink; Portable Session and Portable Graph ZIPs preserve the Markdown file. See [Graph Metadata](GRAPH_METADATA_API_v1.md) and [Portable Resources](PORTABLE_RESOURCE_API_v1.md).
