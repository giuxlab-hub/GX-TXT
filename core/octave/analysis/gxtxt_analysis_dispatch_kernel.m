% SPDX-License-Identifier: GPL-3.0-or-later
% Internal numerical-kernel dispatcher. Scientific context/status integration
% stays in gxtxt_analysis_run(); operation implementation lookup is centralized.
function varargout = gxtxt_analysis_dispatch_kernel(type,varargin)
  h=gxtxt_analysis_operation_registry('handler',type);
  if(isempty(h)),error('GXTXT:AnalysisRegistry','operation %s has no registered numerical handler',type);endif
  [varargout{1:nargout}]=feval(h,varargin{:});
endfunction
