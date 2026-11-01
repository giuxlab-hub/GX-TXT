# Markdown Document Preview

This optional native C++ Preview Module presents canonical Markdown documents through the standard Dataset Preview host. Select a Dataset whose declared contract is `document.text` and whose document kind is Markdown. The Contract Visualizer preference identifies this provider as `preview.markdown_document/markdown_document`.

## Panes

- **Rendered** displays the shared CORE Markdown rendering with selectable text.
- **Source** displays the exact canonical Markdown source as selectable read-only text.
- **Metadata** displays the canonical Dataset identity, Session and admitted document properties.
- **Associated Source** appears only when the canonical source-note owner validates a source association. It uses that owner's existing SourceSurface. Generic Markdown has three panes.

Rendered and Source use the same document owner as Markdown Documents. Use the ordinary text selection and Copy commands to copy text to another application. The Preview does not publish documents or alter canonical data. To edit a document, use its Open action and the Markdown Documents editor.

## Markdown and resources

The shared renderer supports its documented Markdown subset, including headings, emphasis, links, lists, quotes, code blocks and tables. It does not claim complete CommonMark compatibility. Managed document images use the shared resource owner and renderer. Resource identity and permission checks remain in CORE.

## Native implementation

The Builder design declares four direct read-only document components, one for each pane. The standard Preview host supplies the selected component ID to the genuine compiled C++ worker. Its bounded router issues only `Host.document_command(component, "render")` for that exact declared component. CORE owns the host notebook, conditional association, canonical reads, rendering, clipboard behavior and disposal. No module-local parser, Tk interface, filesystem access or Dataset store is used.

The package contains the Builder design, C++ source, public SDK contract, compiled binary and normal Build/Test/Export receipts. Preview layout in Builder is a simulation; installed behavior is exercised from a real Dataset Preview.
