function R=csx_compute_window(x,y,dt_seconds,nfft,window_name,detrend_mode,numeric_api)
% Compute one one-sided pair of auto/cross spectral estimates.
% Convention: Pxy = conj(X).*Y, so H1=Pxy/Pxx estimates Y/X.
% Generic transforms, detrending, windows and frequency coordinates come from NUMERIC_API.
% SPDX-License-Identifier: GPL-3.0-or-later
  x=x(:);y=y(:);L=numel(x);
  if(L!=numel(y)||L<2),error('analysis.cross_spectral_transfer: paired window requires equal X/Y lengths >= 2');endif
  if(any(!isfinite(x))||any(!isfinite(y))),error('analysis.cross_spectral_transfer: non-finite samples are not allowed');endif
  if(!isfinite(dt_seconds)||dt_seconds<=0),error('analysis.cross_spectral_transfer: sample spacing must be positive');endif
  if(!isfinite(nfft)||nfft!=fix(nfft)||nfft<L),error('analysis.cross_spectral_transfer: NFFT must be an integer >= window sample count');endif
  if(nargin<7||isempty(numeric_api)),error('analysis.cross_spectral_transfer: public NUMERIC_API function is required');endif
  Dx=feval(numeric_api,'detrend',x,struct('method',detrend_mode,'nonfinite','error'));Dy=feval(numeric_api,'detrend',y,struct('method',detrend_mode,'nonfinite','error'));
  W=feval(numeric_api,'window',window_name,L,struct('sampling','symmetric'));w=double(W.values(:));U=double(W.power_sum);
  if(!isfinite(U)||U<=0),error('analysis.cross_spectral_transfer: invalid FFT window power normalization');endif
  fs=1/dt_seconds;
  Fx=feval(numeric_api,'fft',double(Dx.values(:)).*w,struct('nfft',nfft,'normalization','backward','nonfinite','error'));
  Fy=feval(numeric_api,'fft',double(Dy.values(:)).*w,struct('nfft',nfft,'normalization','backward','nonfinite','error'));
  Ox=feval(numeric_api,'one_sided',Fx.real,Fx.imaginary,struct('nfft',nfft,'scaling','none'));
  Oy=feval(numeric_api,'one_sided',Fy.real,Fy.imaginary,struct('nfft',nfft,'scaling','none'));
  X=complex(double(Ox.real(:)),double(Ox.imaginary(:)));Y=complex(double(Oy.real(:)),double(Oy.imaginary(:)));Nh=numel(X);
  G=feval(numeric_api,'frequency_grid',fs,nfft,struct('representation','one_sided','ordering','fft'));frequency=double(G.frequency(:));
  if(numel(frequency)!=Nh),error('analysis.cross_spectral_transfer: NUMERIC_API frequency grid size mismatch');endif
  scale=1/(fs*U);Pxx=(abs(X).^2)*scale;Pyy=(abs(Y).^2)*scale;Pxy=(conj(X).*Y)*scale;
  interior=2:Nh;if(mod(nfft,2)==0&&Nh>=2),interior=2:(Nh-1);endif
  if(!isempty(interior)),Pxx(interior)=2*Pxx(interior);Pyy(interior)=2*Pyy(interior);Pxy(interior)=2*Pxy(interior);endif
  R=struct('Pxx',Pxx(:),'Pyy',Pyy(:),'Pxy',Pxy(:),'frequency',frequency,'sample_count',L,'nfft',nfft,'bin_count',Nh,'fs',fs,'df',double(G.df),'window_power_sum',U);
endfunction
