# HTML Dataset Viewer

Read registered HTML Datasets through GX-TXT's safe native document presenter. The source remains read-only.

## Open a document

Open **HTML** from Viewers. In an open Session, choose a source from **HTML Dataset**. The selector offers compatible HTML identities from that Session; choosing one renders its content. **Open HTML Dataset** explicitly opens the selected source again. A compatible source opened through **Open Dataset** uses the same Viewer.

With no open Session, the document area explains that a Session is required. If the Session has no compatible HTML Dataset, it explains that none is available. Open or import an appropriate source through the ordinary Session/Dataset workflow, then reopen the Viewer. A missing or incompatible context reports a source diagnostic rather than becoming an editable file.

## Read and adjust text size

The document uses the main window width. Reading hints and supported-format limits sit below it. Resize the window to reflow text; the scrollbar remains available for long documents.

Use **Smaller**, **Larger** and **Reset** above the document to change text size. The range is **50–300%**, in **25%** steps; Reset returns to **100%**. Ctrl+plus or Ctrl+equal enlarges text, Ctrl+minus reduces it, and Ctrl+0 resets it. Reopening starts a new reading view at 100%. Text-size changes preserve the document content and canonical source identity.

Use the mouse wheel, scrollbar or Page Up/Page Down to scroll. Ctrl+Home and Ctrl+End move to the start and end. Focus the document, then use Ctrl+A to select its rendered text and Ctrl+C to copy it. Copy returns the readable presentation, not the original HTML markup. Selection and Copy remain available while editing is disabled.

## Supported presentation

The safe native presenter supports headings, paragraphs, lists, simple tables, preformatted code and styled inert link text. It is a scientific document reader rather than a general browser.

JavaScript, forms, CSS and external/network resources are inactive. Links do not navigate or launch a browser. Images are omitted and may appear as an image-omitted notice. Complex browser layouts and rich media are not supported.

## Session and source integrity

The canonical Dataset ID, source revision and SHA remain with CORE. The selector follows the current Session; a source from another Session is not an eligible substitute. When a window reports that its Session has changed, reopen HTML for the current Session. Reading, resizing, text zoom and Copy do not publish or edit scientific data.

## Acceptance status of this staged guide

Installed 1.2 native tests verified the full-width normal/narrow layout, actual zoom buttons and keyboard shortcuts, 50–300% bounds, scrolling/reflow, disabled editing, unchanged source SHA and identical copied text before/after zoom. Earlier native Dataset/Session A→B→A and Copy failures and same-author repairs remain preserved separately. MAIN verified the explicit no-Session and no-compatible-source prompts. New-view zoom reset was observed after normal close/reopen.

MAIN also verified that global UI fonts remained unchanged and document zoom/timer resources were released after normal closing. Subsequent installed native checks also verified resize-to-Session expiry, compatible and incompatible Dataset contexts, and normal catalog discovery. Their original failures and corrected evidence remain preserved. Independent integrated acceptance and final release deposition remain MAIN-owned release checks. This guide describes the observed reading workflows; it is not a whole-release acceptance claim.
