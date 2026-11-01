# Markdown Documents

Markdown Documents edits canonical Markdown Datasets through GX-TXT's shared document services. It appears in **Documents** and uses the existing Markdown renderer and Source Surface.

## Open and save

Use **File → Open Dataset** to choose a registered Markdown Dataset in the current Session. **New Markdown** starts an independent blank draft.

**Save to Existing Dataset** keeps the original Dataset ID. CORE checks the current Session, source revision, SHA-256, immutable status and actual producer authorization. A foreign producer must explicitly authorize the current edit. A refused or stale save retains the draft and original source.

**Publish as New Dataset** asks for a new canonical ID, preserves the original Dataset and records source lineage. Publishing a copy of a source note does not silently retarget the originating source file.

Ctrl+S and Ctrl+Shift+S invoke these two distinct choices. Inspect the source and destination IDs and save permissions in the document properties.

Normal Dataset Open for a validated per-file source note first opens its existing source editor and that file’s Markdown tab. If that editor is unavailable, CORE can use this Documents viewer. Generic Markdown opens in Documents. This policy is declared to the CORE resolver.

This optional module can be disabled or removed through the normal Plugin Manager. Existing canonical Datasets remain preserved.

## Author and read

The source pane edits literal UTF-8 Markdown. The rendered pane shows the same draft without publishing or reloading the saved Dataset. Use **Edit** for local text Undo/Redo, Find/Replace and selection commands. Native text selection and standard clipboard keys remain with the shared GX-TXT text owner.

**Format** supplies headings, emphasis, inline and fenced code, lists, tables, links, block quotes, separators, colors and image insertion. GX-Markup is a documented Markdown-like subset, not a claim of complete CommonMark or GFM support. Embedded executable content is not run.

Inserted images are reviewed managed attachments. The images panel handles their current resource identity; arbitrary external downloads and untracked absolute image paths are not used.

## Panels, Workspace and History

**View** shows or hides source, rendered preview, outline, properties and images without discarding the draft. Reset Layout restores the editing arrangement. Larger Text (F8), Smaller Text (F7) and Actual Text Size (Ctrl+0) use the shared document presentation owner.

The existing **Workspace** menu saves and reopens the document draft and presentation state. **History** manages document-state snapshots. Edit Undo/Redo is the local text stack; History navigation and canonical Dataset publication are distinct operations. Restoring a Workspace or History draft does not publish over the current Dataset.

Session changes and changed or missing canonical sources require an explicit current source review. Failed operations preserve the draft and show their actual diagnostic.

## Architecture and limits

The package includes the actual Builder design, editable C++ project and source, admitted native binary and build/export receipts. The C++ client routes only finite declared document actions through the public Host SDK. CORE owns all file access, rendering, clipboard, publication, resources, Workspace and History.

The shared document owner enforces its UTF-8 and size bounds. Missing source associations do not make a saved Markdown note unreadable. Associated code uses the existing Source Surface and remains read-only.
