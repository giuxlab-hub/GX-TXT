% GX-TXT model registry: Koren-style triode model
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% theta = [mu Kp Kvb Kg1 Ex]
% x_v   = plate/anode voltage [V]
% vg_v  = grid-to-cathode voltage [V]
% output = plate/anode current [mA]
function y_mA = triode_koren_v1(theta, x_v, vg_v)
  if (numel(theta) != 5), error('triode.koren_v1 requires 5 parameters'); endif
  mu = theta(1); Kp = theta(2); Kvb = theta(3); Kg1 = theta(4); Ex = theta(5);
  x_v = x_v(:); vg_v = vg_v(:);
  den = sqrt(max(Kvb + x_v.^2, eps));
  z = Kp .* (1 ./ mu + vg_v ./ den);
  % Numerically stable softplus: log(1+exp(z)).
  sp = max(z,0) + log1p(exp(-abs(z)));
  E1 = (x_v ./ Kp) .* sp;
  E1 = max(E1,0);
  % Koren's (1+sign(E1)) factor is 2 for the positive-current region.
  y_mA = 2000 .* (E1 .^ Ex) ./ Kg1;
  y_mA(!isfinite(y_mA)) = 0;
endfunction
