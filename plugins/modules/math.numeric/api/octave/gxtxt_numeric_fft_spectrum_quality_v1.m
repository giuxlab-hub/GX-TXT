function R=gxtxt_numeric_fft_spectrum_quality_v1(x,dt,options)
% Public owner of the retained coherent-gain-corrected FFT lobe estimator.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<3),options=struct();endif
  if(!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric:InvalidArguments','options must be a scalar struct');endif
  allowed={'window','fundamental_mode','fundamental_hz','track_harmonics','spur_search','guard_bins','detrend'};
  if(any(!ismember(fieldnames(options),allowed))),error('GXTXT:Numeric:InvalidPolicy','unknown FFT quality option');endif
  if(!isnumeric(x)||!isvector(x)||!isreal(x)||numel(x)<8||any(!isfinite(x(:)))),error('GXTXT:Numeric:InvalidOperand','FFT quality requires at least eight finite real samples');endif
  if(!isnumeric(dt)||!isreal(dt)||!isscalar(dt)||!isfinite(dt)||dt<=0),error('GXTXT:Numeric:InvalidGrid','sample step must be finite and positive');endif
  window=option(options,'window','hann');mode=option(options,'fundamental_mode','auto_peak');f0=option(options,'fundamental_hz',NaN);
  harmonics=option(options,'track_harmonics',10);spur=option(options,'spur_search','all_nonfundamental');guard=option(options,'guard_bins',2);detrend=option(options,'detrend','mean');
  if(!ischar(mode)||!any(strcmp(mode,{'auto_peak','explicit'}))||!ischar(spur)||!any(strcmp(spur,{'all_nonfundamental','nonharmonic_only'}))),error('GXTXT:Numeric:InvalidPolicy','unknown fundamental or spur search policy');endif
  if(strcmp(mode,'explicit')&&(!isnumeric(f0)||!isscalar(f0)||!isreal(f0)||!isfinite(f0)||f0<=0)),error('GXTXT:Numeric:InvalidFrequency','explicit fundamental must be positive and finite');endif
  if(!isscalar(harmonics)||!isreal(harmonics)||!isfinite(harmonics)||harmonics<2||harmonics!=fix(harmonics)||harmonics>65536||!isscalar(guard)||!isreal(guard)||!isfinite(guard)||guard<0||guard!=fix(guard)||guard>=floor(numel(x)/2)),error('GXTXT:Numeric:InvalidPolicy','invalid bounded harmonic count or guard width');endif
  R=calculate(x(:),dt,window,mode,f0,harmonics,spur,guard,detrend);
  R.method='coherent_gain_corrected_fft_lobe_rss';R.window=window;R.fundamental_mode=mode;R.spur_search=spur;R.guard_bins=guard;R.track_harmonics=harmonics;R.detrend=detrend;
  R.normalization='single_sided_peak_amplitude_with_dc_nyquist_halved';R.level_floor='realmin';
  orders=(2:(numel(R.harm_amp)+1))';
  C=gxtxt_numeric_harmonic_components_v1(orders,orders*R.f0,R.harm_freq(:),R.harm_amp(:),struct('fundamental_amplitude',R.fund_amp,'level_floor','none','component_method','fft_lobe_rss'));
  for key=fieldnames(C)',R.(key{1})=C.(key{1});endfor
endfunction
function value=option(options,key,default),value=default;if(isfield(options,key)),value=options.(key);endif;endfunction
function R=calculate(x,dt,window,fund_mode,fund_hz,track_harm,spur_search,guard,detrend_mode)
  numeric_fn='gxtxt_numeric_v1';
  N=numel(x);
  if(N<8), error('GXTXT:Numeric: need at least 8 samples, got %d',N); endif
  fs=1.0/dt; df=fs/N;

  % This is the established FFT calculation from analysis.fft_spectrum 2.0.0.
  % Temporal Set integration changes only which contiguous source rows become x.
  D=feval(numeric_fn,'detrend',x,struct('method',detrend_mode,'nonfinite','error'));xw=D.values;
  W=feval(numeric_fn,'window',window,N,struct('sampling','symmetric'));w=W.values;
  cg=W.coherent_gain;
  F=feval(numeric_fn,'fft',xw.*w,struct('nfft',N,'normalization','backward','nonfinite','error'));
  Xf=complex(F.real,F.imaginary);
  Nh=floor(N/2)+1;
  Xf=Xf(1:Nh);
  amp=abs(Xf)*2.0/(N*cg);
  amp(1)=amp(1)/2.0;
  if(mod(N,2)==0), amp(end)=amp(end)/2.0; endif

  dc_guard=max(1,guard);
  if(strcmp(fund_mode,'explicit') && isfinite(fund_hz) && fund_hz>0)
    fbin=round(fund_hz/df);
  else
    search=amp; search(1:dc_guard+1)=0;
    [~,fbin0]=max(search); fbin=fbin0-1;
  endif
  fbin=max(1,min(fbin,Nh-1));
  A0=lobe_amp(amp,fbin,guard);
  f0=fbin*df;
  mag_dbc=20*log10(max(amp,realmin)/A0);

  harm_bins=[]; harm_amp=[]; harm_freq=[];
  for k=2:track_harm
    hb=fbin*k;
    if(hb>Nh-1), break; endif
    pk=peak_bin(amp,hb,max(guard,2));
    harm_bins(end+1)=pk; harm_amp(end+1)=lobe_amp(amp,pk,guard); harm_freq(end+1)=pk*df;
  endfor
  if(isempty(harm_amp)), thd_lin=0; else thd_lin=sqrt(sum(harm_amp.^2))/A0; endif
  if(thd_lin>0), thd_db=20*log10(thd_lin); thd_pct=thd_lin*100; else thd_db=-Inf; thd_pct=0; endif

  excl=false(Nh,1); excl(1:dc_guard+1)=true;
  excl=mark_lobe(excl,fbin,guard);
  if(strcmp(spur_search,'nonharmonic_only'))
    for i=1:numel(harm_bins), excl=mark_lobe(excl,harm_bins(i),guard); endfor
  endif
  cand=amp; cand(excl)=0;
  [worst_amp,wi]=max(cand); worst_bin=wi-1; worst_freq=worst_bin*df;
  if(worst_amp>0), sfdr_db=20*log10(A0/worst_amp); worst_dbc=20*log10(worst_amp/A0); else sfdr_db=Inf; worst_dbc=-Inf; endif

  ndmask=true(Nh,1); ndmask(1:dc_guard+1)=false; ndmask=clear_lobe(ndmask,fbin,guard);
  nd_pow=sum(amp(ndmask).^2);
  if(nd_pow>0), sinad_db=10*log10(A0^2/nd_pow); enob=(sinad_db-1.76)/6.02; else sinad_db=Inf; enob=Inf; endif

  nf=amp(ndmask); if(isempty(nf)), noise_floor=0; else noise_floor=fft_median(numeric_fn,nf); endif
  noise_floor_dbc=20*log10(max(noise_floor,realmin)/A0);
  R=struct('N',N,'fs',fs,'df',df,'coherent_gain',cg,'amp',amp,'Nh',Nh, ...
           'fund_bin',fbin,'fund_amp',A0,'f0',f0,'magnitude_dbc',mag_dbc, ...
           'harm_bins',harm_bins,'harm_amp',harm_amp,'harm_freq',harm_freq, ...
           'thd_ratio',thd_lin,'thd_db',thd_db,'thd_pct',thd_pct,'sfdr_db',sfdr_db,'worst_dbc',worst_dbc, ...
           'worst_amp',worst_amp,'worst_freq',worst_freq,'sinad_db',sinad_db,'enob',enob, ...
           'noise_floor',noise_floor,'noise_floor_dbc',noise_floor_dbc);
endfunction

function a=lobe_amp(amp,bin0,guard)
  Nh=numel(amp); lo=max(1,bin0+1-guard); hi=min(Nh,bin0+1+guard);
  a=sqrt(sum(amp(lo:hi).^2));
endfunction

function pk=peak_bin(amp,bin0,win)
  Nh=numel(amp); lo=max(1,bin0+1-win); hi=min(Nh,bin0+1+win);
  seg=amp(lo:hi); [~,mi]=max(seg); pk=(lo+mi-1)-1;
endfunction

function m=mark_lobe(m,bin0,guard)
  Nh=numel(m); lo=max(1,bin0+1-guard); hi=min(Nh,bin0+1+guard); m(lo:hi)=true;
endfunction
function m=clear_lobe(m,bin0,guard)
  Nh=numel(m); lo=max(1,bin0+1-guard); hi=min(Nh,bin0+1+guard); m(lo:hi)=false;
endfunction

function v=fft_median(numeric_fn,x)
  s=feval(numeric_fn,'statistics',double(x(:)),struct());v=s.median;
endfunction
