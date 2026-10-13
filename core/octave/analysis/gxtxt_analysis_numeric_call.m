% Resolve the protected public numerical binding for shared analysis code.
% SPDX-License-Identifier: GPL-3.0-or-later
function result=gxtxt_analysis_numeric_call(varargin)
  if(exist('gxtxt_numeric_v1','file')!=2)
    root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    entry=fullfile(root,'plugins','modules','math.numeric','api','octave','gxtxt_numeric_v1.m');
    if(exist(entry,'file')!=2),error('GXTXT:AnalysisExpression','NUMERIC_API_v1 Octave binding is unavailable');endif
    addpath(fileparts(entry));
  endif
  result=gxtxt_numeric_v1(varargin{:});
endfunction
