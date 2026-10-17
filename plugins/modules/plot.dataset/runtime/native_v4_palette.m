% SPDX-License-Identifier: GPL-3.0-or-later
% Bounded mathematical palette intake only. No figure, axes, plotting toolkit,
% Gnuplot process or legacy Plot Dataset rendering code is loaded or called.
args=argv();name=args{1};n=str2double(args{2});
if(isempty(regexp(name,'^[A-Za-z][A-Za-z0-9_]*$','once'))||!isfinite(n)||n<2||n>256||fix(n)!=n),error('Invalid native palette request');endif
try
  colors=feval(name,n);
  if(!isnumeric(colors)||!isequal(size(colors),[n 3])||any(!isfinite(colors(:)))||any(colors(:)<0)||any(colors(:)>1)),error('Invalid mathematical RGB palette');endif
catch
  colors=viridis(n);
  printf('# Unknown colormap: existing Plot policy retains the default viridis palette.\n');
end_try_catch
for k=1:n,printf('%.17g %.17g %.17g\n',colors(k,1),colors(k,2),colors(k,3));endfor
