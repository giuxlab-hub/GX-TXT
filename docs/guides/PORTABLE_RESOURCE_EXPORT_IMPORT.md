# Export and import individual Datasets and graphs

Portable scientific resources transfer individual Datasets and graphs between Sessions.

In **Dataset**, choose an imported/published Dataset and open **Dataset ZIP... → Export Dataset ZIP...**. To receive one, choose **Import Dataset ZIP...**, review source identity, contract/provider, integrity and size, then select a free Dataset ID. Existing IDs are protected. Payload format/bytes, Variable IDs, enabled and disabled schema, reversible CSV source snapshots, custom unit relations, structured metadata and notes survive transfer.

In **Plots**, select a base graph, Variant or Detached Clone and use **Export Graph ZIP...**. Use the toolbar's horizontal scrollbar when needed. Native Plot Dataset graphs retain their renderer identity, complete canonical Dataset packages and editable native scientific presentation. Native scientific Clones remain independent after their original Dataset or Variant is removed. **Import Graph ZIP...** reviews the graph and embedded Dataset IDs before commit. Import always creates an independent Detached Clone. Choose scientific import when the frozen Plot Dataset snapshot and its verified reconstruction provider are available. Native snapshots embed complete canonical Dataset packages without registering their source identities in the receiving Session; historical static snapshots retain their established dependency collision rules. Choose rendered-only import when you need the recorded visual and descriptive resources; its scientific values cannot be rerendered. Notes and metadata are independent copies, and existing graphs are preserved.

**Notes...** opens the standard Markdown editor; Graph Info displays notes/metadata presence and descriptive keys. Variant create/duplicate and Clone creation copy existing notes/metadata; deleting a copy removes only that copy's resources. Save Config and reopen the Session to resume the graph state.

Use a Portable Session ZIP for a whole Session backup. Resource ZIPs transfer individual scientific resources. Plugin ZIPs install code, while HTML export is a read-only publication. See [Portable Resource API](../api/PORTABLE_RESOURCE_API_v1.md) for format, collision and security details.

# Dataset Groups

The Dataset Browser shows an acquired Group under its Namespace, with each
independent Dataset and its role beneath an expandable row. Selecting the Group
does not activate its members for analysis. Use its context menu to inspect,
move the whole Group, export one Group ZIP, or ungroup while keeping all data.
A member's Move action moves the whole Group; explicitly Detach first to move
just that Dataset. Ordinary member Preview and individual Dataset ZIP remain.

Choose **Import Dataset Group ZIP…** from a Namespace context menu. Review the
Group ID, destination Namespace and original/destination member IDs, then import
the complete Group. Collisions refuse; edit the destination IDs explicitly.
Import validates all member bytes/schema/SHA and commits them together. An
individual member ZIP instead imports as a detached Dataset, retaining original
Group provenance without claiming the missing members exist.
