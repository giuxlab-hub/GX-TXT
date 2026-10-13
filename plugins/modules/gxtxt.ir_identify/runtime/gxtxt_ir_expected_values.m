function vals=gxtxt_ir_expected_values(P)
% Distinct protocol timing references for public PlotSpec annotations.
% SPDX-License-Identifier: GPL-3.0-or-later
  vals=[P.headerMark P.headerSpace P.bitMark P.zeroSpace P.oneSpace P.zeroMark P.oneMark P.bitSpace P.unit];
  vals=unique(vals(isfinite(vals)&vals>0));
endfunction
