# SPDX-License-Identifier: GPL-3.0-or-later
import sys,json
from pathlib import Path
import numpy as np
from scipy import signal
root=Path(sys.argv[1]).resolve()
assert '_private_dev106' in root.parts
jobs={}
for p in root.glob('Sessions/*/analysis/scripts/*/signal_summary.json'):
 d=json.loads(p.read_text());jobs[d['operation']]=(p.parent,d)
n=next(iter(jobs.values()))[1]['full_input_rows'];t=np.arange(n)/1000;x=np.sin(np.arange(n)*.1)+.1*np.cos(np.arange(n)*.02);y=2*np.sin(np.arange(n)*.1)+.3*np.cos(np.arange(n)*.02)
results={}
def check(method,cols,ref,rtol=1e-7,atol=1e-9):
 p,d=jobs[method];a=np.genfromtxt(p/'signal_result.csv',delimiter=',',names=True);actual=np.column_stack([a[c] for c in cols]);ref=np.asarray(ref);ref=ref[:,None] if ref.ndim==1 else ref
 assert actual.shape==ref.shape,(method,actual.shape,ref.shape)
 err=float(np.max(np.abs(actual-ref)));ok=bool(np.allclose(actual,ref,rtol=rtol,atol=atol));results[method]={'pass':ok,'max_absolute_error':err,'rows':len(actual),'rtol':rtol,'atol':atol}
 if not ok:print('FAIL',method,err)
q=jobs['quality.basic'][1]['scalar_fields'];qref={'n':n,'rms':np.sqrt(np.mean(x*x)),'peak':np.max(np.abs(x)),'peak_to_peak':np.ptp(x),'crest_factor':np.max(np.abs(x))/np.sqrt(np.mean(x*x)),'dc_real':x.mean(),'dc_imaginary':0};results['quality.basic']={'pass':all(np.isclose(q[k],v,rtol=1e-10,atol=1e-12) for k,v in qref.items()),'reference':qref}
for method,b in [('correlation.auto',x),('correlation.cross',y)]:
 v=signal.correlate(x,b,mode='full',method='fft')/(np.linalg.norm(x)*np.linalg.norm(b));check(method,['lags','value_real','value_imaginary'],np.column_stack([np.arange(-n+1,n),v,np.zeros(len(v))]),atol=1e-10)
nfft=2**int(np.ceil(np.log2(max(256,n))));f,psd=signal.periodogram(x,fs=1000,window=np.hamming(n),nfft=nfft,detrend=False,scaling='density');check('spectral.periodogram',['frequency_hz','psd_real'],np.column_stack([f,psd]))
used=128*((n-256)//128)+256;xx=x[:used]-x[:used].mean();yy=y[:used]-y[:used].mean();opts=dict(fs=1000,window=np.hamming(256),nperseg=256,noverlap=128,nfft=256,detrend=False,scaling='density');f,px=signal.welch(xx,**opts);_,py=signal.welch(yy,**opts);_,cross=signal.csd(xx,yy,**opts)
check('spectral.welch',['frequency_hz','psd_real'],np.column_stack([f,px]));check('spectral.asd',['frequency_hz','asd'],np.column_stack([f,np.sqrt(px)]));check('spectral.coherence',['frequency_hz','value_real'],np.column_stack([f,np.abs(cross)**2/(px*py)]))
for m,v in [('spectral.frf_h1',cross/px),('spectral.frf_h2',py/np.conj(cross))]:check(m,['frequency_hz','value_real','value_imaginary'],np.column_stack([f,v.real,v.imag]))
a=signal.hilbert(x);phase=np.unwrap(np.angle(a));check('analytic.envelope',['amplitude'],np.abs(a));check('analytic.phase',['phase_rad'],phase);check('analytic.instantaneous_frequency',['frequency_hz'],np.gradient(phase)*1000/(2*np.pi))
b,den=signal.butter(3,.02);check('filter.causal',['value_real'],signal.lfilter(b,den,x),atol=2e-8);check('filter.zero_phase',['value_real'],signal.filtfilt(b,den,x,padlen=9),atol=2e-8)
b,den=signal.cheby1(8,.05,.4);dec=signal.filtfilt(b,den,x,padlen=24)[::2];check('multirate.decimate',['time','value_real'],np.column_stack([t[::2],dec]),atol=2e-8)
report={'pass':len(results)==15 and all(v['pass'] for v in results.values()),'independent_reference':'NumPy/SciPy, full records, Octave documented symmetric Hamming and pad conventions','samples':n,'methods':results};(root/'independent-reference.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));sys.exit(0 if report['pass'] else 1)
