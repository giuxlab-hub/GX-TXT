% API-owned adapter to the public Octave Unit Registry conversion function.
% SPDX-License-Identifier: GPL-3.0-or-later
args=argv();
if(numel(args)!=5),error('usage: unit_convert_adapter.m <input> <output> <count> <source-unit> <target-unit>');endif
here=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(here));
addpath(fullfile(root,'core','octave','units'));
addpath(fullfile(root,'core','octave','io'));
input=args{1};output=args{2};count=str2double(args{3});
if(!isfinite(count)||count<0||count!=fix(count)),error('invalid conversion count');endif
fid=fopen(input,'rb','ieee-le');if(fid<0),error('cannot read conversion input');endif
unwind_protect
  values=fread(fid,count,'*double');
unwind_protect_cleanup
  fclose(fid);
end_unwind_protect
if(numel(values)!=count),error('incomplete conversion input');endif
converted=gxtxt_unit_convert(values,args{4},args{5});
fid=fopen(output,'wb','ieee-le');if(fid<0),error('cannot write conversion result');endif
unwind_protect
  if(fwrite(fid,converted(:),'double')!=count),error('incomplete conversion output');endif
unwind_protect_cleanup
  fclose(fid);
end_unwind_protect
