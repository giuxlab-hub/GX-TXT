# Export and import individual Datasets and graphs

GX-TXT 0.9.8.10-dev-051 adds portable scientific resources to the current Session workflow.

In **Dataset**, choose an imported/published Dataset and open **Dataset ZIP... → Export Dataset ZIP...**. To receive one, choose **Import Dataset ZIP...**, review source identity, contract/provider, integrity and size, then select a free Dataset ID. Existing IDs are protected. Payload format/bytes, Variable IDs, enabled and disabled schema, reversible CSV source snapshots, custom unit relations, structured metadata and notes survive transfer.

In **Plots**, select a base graph, Variant or Detached Clone and use **Export Graph ZIP...**. Use the toolbar's horizontal scrollbar when needed. **Import Graph ZIP...** reviews the graph and embedded Dataset IDs before commit. Import always creates an independent Detached Clone. Choose scientific import when the frozen Plot Dataset snapshot and noncolliding dependencies are available. Choose rendered-only import when you need the recorded visual and descriptive resources; its scientific values cannot be rerendered. Notes and metadata are independent copies, and existing graphs are preserved.

**Notes...** opens the standard Markdown editor; Graph Info displays notes/metadata presence and descriptive keys. Variant create/duplicate and Clone creation copy existing notes/metadata; deleting a copy removes only that copy's resources. Save Config and reopen the Session to resume the graph state.

Use a Portable Session ZIP for a whole Session backup. Resource ZIPs transfer individual scientific resources. Plugin ZIPs install code, while HTML export is a read-only publication. See [Portable Resource API](../api/PORTABLE_RESOURCE_API_v1.md) for format, collision and security details.
