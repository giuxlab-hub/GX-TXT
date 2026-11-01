'use strict';
// SPDX-License-Identifier: GPL-3.0-or-later
// Local reading aids only. No framework, storage, network or scientific action.
const readingMarks = document.querySelectorAll('input[data-reading-step]');
const readingProgress = document.getElementById('reading-progress');
function updateReadingProgress() {
  let count = 0;
  readingMarks.forEach((mark) => { if (mark.checked) count += 1; });
  readingProgress.textContent = `Reading marks: ${count} of ${readingMarks.length}. Reading only — not GUI execution or acceptance.`;
}
readingMarks.forEach((mark) => mark.addEventListener('change', updateReadingProgress));
const notes = document.querySelectorAll('main details');
document.getElementById('expand-notes').addEventListener('click', () => {
  notes.forEach((note) => { note.open = true; });
});
document.getElementById('collapse-notes').addEventListener('click', () => {
  notes.forEach((note) => { note.open = false; });
});
updateReadingProgress();
document.getElementById('disclosure-controls').hidden = false;
document.getElementById('js-status').textContent = 'Optional local reading aids initialized. Checklist marks and source-note disclosures do not perform GX-TXT actions or create evidence.';
