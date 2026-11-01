'use strict';
// SPDX-License-Identifier: GPL-3.0-or-later
// Local reading aids only: no storage, network, framework or scientific action.
const marks = document.querySelectorAll('input[data-reading-step]');
const progress = document.getElementById('reading-progress');
function updateReading() {
  let count = 0;
  marks.forEach((mark) => { if (mark.checked) count += 1; });
  if (progress) progress.textContent = `Reading marks: ${count} of ${marks.length}. Reading only; all Manchester GUI outcomes remain NOT_TESTED.`;
}
marks.forEach((mark) => mark.addEventListener('change', updateReading));
const notes = document.querySelectorAll('main details');
const expand = document.getElementById('expand-notes');
const collapse = document.getElementById('collapse-notes');
if (expand) expand.addEventListener('click', () => { notes.forEach((note) => { note.open = true; }); });
if (collapse) collapse.addEventListener('click', () => { notes.forEach((note) => { note.open = false; }); });
updateReading();
const controls = document.getElementById('disclosure-controls');
if (controls) controls.hidden = false;
const status = document.getElementById('js-status');
if (status) status.textContent = 'Optional reading aids initialized. Marks and disclosures do not run GX-TXT, calculate science or create evidence.';
