% Synthetic accumulation for native Into, Over and Out practice.
% SPDX-License-Identifier: GPL-3.0-or-later
1; % Keep this file an executable Octave script with local functions.
function increment = adjust(value)
  increment = value + 1;
endfunction
function total = accumulate(count)
  total = 0;
  for sample = 0:(count - 1)
    adjusted = adjust(sample);
    total = total + adjusted;
  endfor
endfunction
result = accumulate(5);
fprintf('NESTED_RESULT %d\n', result);
assert(result == 15);
