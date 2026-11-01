% Scientific comparison preparation; no Dataset, renderer or persistence owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_numeric_comparison_curves_v1(mode,x1,y1,x2,y2,opts)
  if(!isstruct(opts)),error('GXTXT:Numeric:Comparison','Options must be a structure');endif
  allowed={'normalization','offset','denominator_floor'};
  if(any(!ismember(fieldnames(opts),allowed))),error('GXTXT:Numeric:Comparison','Unknown comparison option');endif
  if(!any(strcmp(mode,{'overlay','top_bottom','stacked','difference','ratio'})))
    error('GXTXT:Numeric:Comparison','Unknown comparison mode');
  endif
  [x1,y1]=curve(x1,y1);
  normalization='none';if(isfield(opts,'normalization')),normalization=opts.normalization;endif
  offset=0;if(isfield(opts,'offset')),offset=number(opts.offset);endif
  floor=0;if(isfield(opts,'denominator_floor')),floor=number(opts.denominator_floor);endif
  if(floor<0||!any(strcmp(normalization,{'none','minmax'})))
    error('GXTXT:Numeric:Comparison','Invalid normalization or denominator floor');
  endif
  if(!strcmp(mode,'stacked')&&offset!=0),error('GXTXT:Numeric:Comparison','Offset is only a stacked display transform');endif
  if(any(strcmp(mode,{'difference','ratio'})))
    if(!strcmp(normalization,'none')),error('GXTXT:Numeric:Comparison','Derived comparison uses raw scientific values');endif
    [x2,y2]=curve(x2,y2);
    low=max(min(x1),min(x2));high=min(max(x1),max(x2));
    if(low>=high),error('GXTXT:Numeric:Comparison','Sources have no nonzero common domain');endif
    keep=x1>=low&x1<=high;x=x1(keep);a=y1(keep);
    if(numel(x)<2),error('GXTXT:Numeric:Comparison','Common first-source grid has fewer than two samples');endif
    if(x2(1)>x2(end)),x2=flipud(x2);y2=flipud(y2);endif
    % interp1 retains NaN brackets. Never drop missing Y then bridge its gap.
    b=interp1(x2,y2,x,'linear',NaN);
    % A missing neighbor must not erase an independently present exact knot.
    % Interior interpolated points still retain their missing bracket as gaps.
    [exact,location]=ismember(x,x2);b(exact)=y2(location(exact));
    invalid=!isfinite(a)|!isfinite(b);
    if(strcmp(mode,'difference')),values=a-b;
    else invalid|=abs(b)<=floor;values=a./b;endif
    invalid|=!isfinite(values);values(invalid)=NaN;
    out=struct('x',x,'values',values,'invalid_count',sum(invalid),...
      'domain_min',low,'domain_max',high,'method','linear_intersection_first_source_grid',...
      'normalization','none','offset',0,'denominator_floor',floor,...
      'canonical_values_modified',false);
  else
    x=x1;values=y1;finite=isfinite(values);
    if(!any(finite)),error('GXTXT:Numeric:Comparison','Source has no finite Y samples');endif
    if(strcmp(normalization,'minmax'))
      lo=min(values(finite));hi=max(values(finite));
      if(hi==lo),values(finite)=0;else values(finite)=(values(finite)-lo)/(hi-lo);endif
    endif
    values(finite)+=offset;values(!finite)=NaN;
    out=struct('x',x,'values',values,'invalid_count',sum(!isfinite(values)),...
      'domain_min',min(x),'domain_max',max(x),'method','source_grid_display_only',...
      'normalization',normalization,'offset',offset,'denominator_floor',floor,...
      'canonical_values_modified',false);
  endif
endfunction
function [x,y]=curve(x,y)
  if(!isnumeric(x)||!isnumeric(y)||!isreal(x)||!isreal(y)||!isvector(x)||!isvector(y)||numel(x)!=numel(y)||numel(x)<2||numel(x)>65536)
    error('GXTXT:Numeric:Comparison','Curve requires 2..65536 actual X/Y samples');
  endif
  x=x(:);y=y(:);
  if(any(!isfinite(x))||!(all(diff(x)>0)||all(diff(x)<0)))
    error('GXTXT:Numeric:Comparison','X must be finite, strictly ascending or descending, without duplicates');
  endif
endfunction
function result=number(value)
  if(ischar(value)),value=str2double(value);endif
  if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value))
    error('GXTXT:Numeric:Comparison','Comparison parameter must be finite');
  endif
  result=double(value);
endfunction
