// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
(() => {
 const x = document.getElementById('pixel-x');
 const y = document.getElementById('pixel-y');
 const format = value => Number(value.toFixed(5)).toString().replace('-', '−');
 function update() {
  const px = Number(x.value), py = Number(y.value);
  document.getElementById('read-x').value = String(px);
  document.getElementById('read-y').value = String(py);
  document.getElementById('chosen-pixel').setAttribute('cx', String(px));
  document.getElementById('chosen-pixel').setAttribute('cy', String(py));
  document.getElementById('mapped').textContent = `Illustrative coordinate: ${format((px - 10) / 10)} s, ${format((50 - py) / 20)} V.`;
  const inside = px >= 10 && px <= 90 && py >= 10 && py <= 90;
  document.getElementById('domain').textContent = inside
   ? 'The selected location is inside the calibration rectangle.'
   : 'The selected location is outside the calibration rectangle. The displayed formula is extrapolated; scientific use requires the actual accepted domain policy.';
 }
 x.addEventListener('input', update);
 y.addEventListener('input', update);
 document.getElementById('reset-reference').addEventListener('click', () => {x.value = '30'; y.value = '70'; update();});
 update();
})();
