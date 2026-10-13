% SPDX-License-Identifier: GPL-3.0-or-later
% Historical destructive filter primitive.  v0.8.3 delegates comparison to
% the row-preserving mask helper, preserving the original filter semantics.
function mask = gxtxt_analysis_op_filter(value, op, target)
  mask = gxtxt_analysis_op_mask(value, op, target);
endfunction
