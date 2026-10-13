function B=fractional_octave_band_definitions(source_lo_hz,source_hi_hz,min_positive_hz,bands_per_octave,range_mode,min_hz,max_hz)
% Exact base-10 fractional-octave band definitions around 1 kHz.
% G = 10^(3/10); fc(k)=1000*G^(k/N); edges=fc*G^(+-1/(2N)).
% SPDX-License-Identifier: GPL-3.0-or-later
  N=round(bands_per_octave);if(!any(N==[1 3 6])),error('analysis.fractional_octave_spectrum: bands_per_octave must be 1, 3, or 6');endif
  if(!(isfinite(source_lo_hz)&&isfinite(source_hi_hz)&&source_hi_hz>source_lo_hz)),error('analysis.fractional_octave_spectrum: invalid source frequency support');endif
  mode=lower(strtrim(range_mode));if(strcmp(mode,'auto'))
    lo=max(source_lo_hz,max(min_positive_hz,realmin));hi=source_hi_hz;
  elseif(strcmp(mode,'explicit'))
    if(!(isfinite(min_hz)&&isfinite(max_hz)&&min_hz>0&&max_hz>min_hz)),error('analysis.fractional_octave_spectrum: explicit frequency range must satisfy 0 < min < max');endif
    lo=max(source_lo_hz,min_hz);hi=min(source_hi_hz,max_hz);
  else error('analysis.fractional_octave_spectrum: invalid range mode');endif
  if(hi<=lo),error('analysis.fractional_octave_spectrum: selected range has no overlap with source spectrum');endif
  G=10^(3/10);k0=floor(N*log(lo/1000)/log(G))-3;k1=ceil(N*log(hi/1000)/log(G))+3;
  ks=(k0:k1)';fc=1000.*(G.^(ks./N));fac=G^(1/(2*N));flo=fc./fac;fhi=fc.*fac;
  keep=(flo>=lo-64*eps(max(lo,1)))&(fhi<=hi+64*eps(max(hi,1)))&(flo>=source_lo_hz-64*eps(max(source_lo_hz,1)))&(fhi<=source_hi_hz+64*eps(max(source_hi_hz,1)));
  if(!any(keep)),error('analysis.fractional_octave_spectrum: no complete fractional-octave bands fit inside the selected/source range');endif
  B=struct('bands_per_octave',N,'G',G,'band_number',ks(keep),'center_hz',fc(keep),'lower_hz',flo(keep),'upper_hz',fhi(keep));B.bandwidth_hz=B.upper_hz-B.lower_hz;
endfunction
