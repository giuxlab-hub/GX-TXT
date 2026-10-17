% Shared expression grammar with Unit Registry dimensional validation.
% SPDX-License-Identifier: GPL-3.0-or-later
function [out,out_unit]=gxtxt_analysis_expression_strict_units(expr,series,units,output_unit)
  if(nargin<4),output_unit='';endif
  rpn=gxtxt_analysis_expression_parse(expr);scaled=series;used={};
  for i=1:numel(rpn)
    token=rpn{i};if(!strcmp(token.kind,'id')),continue;endif
    id=token.text;if(any(strcmp(used,id))),continue;endif;used{end+1}=id;
    if(!isfield(series,id)),error('GXTXT:AnalysisUnits','unknown symbol: %s',id);endif
    unit='';if(isfield(units,id)),unit=units.(id);endif
    if(isempty(strtrim(unit))),error('GXTXT:AnalysisUnits','strict unit checking requires unit metadata for %s',id);endif
    parsed=gxtxt_unit_parse(unit);
    if(!strcmp(parsed.kind,'linear')),error('GXTXT:AnalysisUnits','strict unit arithmetic does not support semantic/non-linear unit %s',unit);endif
    if(!isnumeric(series.(id))||!isreal(series.(id))),error('GXTXT:AnalysisUnits','strict unit expression requires real numeric series: %s',id);endif
    scaled.(id)=series.(id).*parsed.scale;
  endfor
  receipt=gxtxt_unit_expression_dimensions_v1(expr,units,output_unit);
  dimensions=receipt.dimensions;
  out=gxtxt_analysis_op_expression(expr,scaled);
  if(!isempty(strtrim(output_unit)))
    target=gxtxt_unit_parse(output_unit);
    if(!strcmp(target.kind,'linear')),error('GXTXT:AnalysisUnits','strict unit arithmetic does not support semantic/non-linear output unit %s',output_unit);endif
    if(!isequal(orderfields(dimensions),orderfields(target.dims))),error('GXTXT:AnalysisUnits','expression result is incompatible with requested unit %s',output_unit);endif
    out=out./target.scale;out_unit=output_unit;
  else
    out_unit=receipt.dimension_label;
  endif
endfunction
