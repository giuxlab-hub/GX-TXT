function value=gxtxt_ir_numeric(numeric_fn,operation,varargin)
% Route reusable IR numerical primitives through the discovered public API.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(isempty(numeric_fn)),error('gxtxt.ir_waveform: public NUMERIC_API_v1 binding is required');endif
  switch(operation)
    case 'median'
      s=feval(numeric_fn,'statistics',double(varargin{1}(:)),struct());value=s.median;
    case 'mean'
      s=feval(numeric_fn,'reduce_summary',double(varargin{1}(:)),struct());value=s.mean;
    case 'rms'
      s=feval(numeric_fn,'statistics',double(varargin{1}(:)),struct());value=s.rms;
    case 'interpolate'
      r=feval(numeric_fn,'interpolate',double(varargin{1}(:)),double(varargin{2}(:)),double(varargin{3}(:)), ...
        struct('method','linear','extrapolation','nan','nonfinite','error'));
      value=reshape(r.yq,size(varargin{3}));
    otherwise
      error('gxtxt.ir_waveform: unsupported numerical operation %s',operation);
  endswitch
endfunction
