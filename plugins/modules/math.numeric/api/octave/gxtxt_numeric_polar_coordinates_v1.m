% SPDX-License-Identifier: GPL-3.0-or-later
% Scientific polar coordinates use an explicit frame and explicit branch policy.
function out=gxtxt_numeric_polar_coordinates_v1(operation,a,b,options)
  if(nargin<4),options=struct();endif
  if(!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric','polar frame must be a scalar options structure');endif
  allowed={'origin','theta_zero','clockwise','angle_unit','unwrap_policy','angle_cut'};
  if(any(!ismember(fieldnames(options),allowed))),error('GXTXT:Numeric','unknown polar coordinate option');endif
  frame=struct('origin',[0,0],'theta_zero',0,'clockwise',false,'angle_unit','rad','unwrap_policy','cut','angle_cut',0);
  for key=fieldnames(options).',frame.(key{1})=options.(key{1});endfor
  if(!isnumeric(frame.origin)||numel(frame.origin)!=2||any(!isfinite(frame.origin(:)))||!isnumeric(frame.theta_zero)||!isscalar(frame.theta_zero)||!isfinite(frame.theta_zero))
    error('GXTXT:Numeric','polar origin and theta-zero direction must be finite');
  endif
  if(!isscalar(frame.clockwise)||!any(frame.clockwise==[0,1])),error('GXTXT:Numeric','polar clockwise flag must be a boolean');endif
  frame.clockwise=logical(frame.clockwise);
  if(!any(strcmp(frame.angle_unit,{'rad','deg'}))||!any(strcmp(frame.unwrap_policy,{'cut','continuous'}))||!isscalar(frame.angle_cut)||!isnumeric(frame.angle_cut)||!isfinite(frame.angle_cut))
    error('GXTXT:Numeric','polar angle unit, branch policy or cut is invalid');
  endif
  a=double(a(:));b=double(b(:));
  if(numel(a)!=numel(b)||any(!isfinite(a))||any(!isfinite(b))),error('GXTXT:Numeric','polar conversion needs finite paired coordinates');endif
  factor=1;if(strcmp(frame.angle_unit,'deg')),factor=180/pi;endif
  period=2*pi*factor;direction=1;if(frame.clockwise),direction=-1;endif
  if(!isfinite(frame.angle_cut+period)||frame.angle_cut+period<=frame.angle_cut),error('GXTXT:Numeric','polar cut cannot represent its angular period');endif
  if(strcmp(operation,'polar_coordinates'))
    dx=a-frame.origin(1);dy=b-frame.origin(2);radius=hypot(dx,dy);
    if(any(!isfinite(radius))),error('GXTXT:Numeric','polar radius exceeds finite numeric range');endif
    angle=direction*(atan2(dy,dx)-frame.theta_zero)*factor;
    relative=mod(angle-frame.angle_cut,period);
    tolerance=8*eps(period);
    relative(relative<=tolerance | relative>=period-tolerance)=0;
    angle=frame.angle_cut+relative;
    if(strcmp(frame.unwrap_policy,'continuous')&&!isempty(angle))
      unwrapped=gxtxt_numeric_v1('unwrap',angle,struct('period',period));angle=unwrapped.values;
    endif
    out=struct('theta',angle,'radius',radius,'points',[angle,radius],'angle_undefined',radius==0,'frame',frame,'period',period);
  elseif(strcmp(operation,'cartesian_coordinates'))
    if(any(b<0)),error('GXTXT:Numeric','polar radius must be nonnegative');endif
    angle=frame.theta_zero+direction*a/factor;
    x=frame.origin(1)+b.*cos(angle);y=frame.origin(2)+b.*sin(angle);
    if(any(!isfinite(x))||any(!isfinite(y))),error('GXTXT:Numeric','Cartesian polar output exceeds finite numeric range');endif
    out=struct('x',x,'y',y,'points',[x,y],'frame',frame);
  else,error('GXTXT:Numeric','unknown polar coordinate conversion');endif
endfunction
