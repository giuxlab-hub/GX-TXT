"""Dataset-scale domain coordination over public CORE numerical/transport APIs."""
# SPDX-License-Identifier: GPL-3.0-or-later
import csv,json,os
from pathlib import Path
import numpy as np
from gxtxt import gxtxt_api_call as call

METHODS=('quality.basic','correlation.auto','correlation.cross','spectral.periodogram','spectral.welch','spectral.asd','spectral.coherence','spectral.frf_h1','spectral.frf_h2','analytic.envelope','analytic.phase','analytic.instantaneous_frequency','filter.causal','filter.zero_phase','multirate.decimate')
def array(value):
    a=np.asarray(value,dtype=np.float64).reshape(-1)
    return {'kind':'array','shape':[a.size,1],'real':a}
def scalar(value):return array([value])
def options(values):return {'kind':'struct','fields':{key:({'kind':'text','value':value} if isinstance(value,str) else scalar(value)) for key,value in values.items()}}
EMPTY={'kind':'empty'}
def run(context):
    p=context.parameters;method=p['operation']
    if method not in METHODS:raise ValueError('Unsupported guided Signal operation')
    source=p['dataset_id'];primary=p['primary'];secondary=p.get('secondary','');time_id=p.get('time','')
    metadata=call('CANONICAL_DATASET_API_v2','describe',[source]);variables={v['variable_id']:v for v in metadata['variables']}
    count=int(metadata.get('row_count',0));chosen=list(dict.fromkeys([x for x in (primary,secondary,time_id) if x]))
    if count<3:raise ValueError('Signal requires at least three declared rows')
    if count*8*len(chosen)>int(os.environ.get('GXTXT_SIGNAL_INPUT_BUDGET','2147483648')):raise ValueError('Requested full-resolution inputs exceed the managed 2 GiB input budget; no truncation occurred')
    signals={}
    for index,name in enumerate(chosen):
        v=variables.get(name)
        if not v or str(v.get('rank'))!='1' or v.get('dtype')=='string':raise ValueError(f'Variable {name} must be rank-one numeric')
        signals[name]=np.memmap(context.scratch/f'signal-{index}.bin',dtype='float64',mode='w+',shape=(count,))
    for start in range(0,count,65536):
        n=min(65536,count-start);chunk=call('CANONICAL_DATASET_API_v2','read_range',[source,chosen,start,n])
        for name in chosen:
            values=np.asarray(chunk[name]['values']).reshape(-1)
            if len(values)!=n or not np.isfinite(values).all():raise ValueError('Incomplete or nonfinite full-resolution signal input')
            if values.dtype.kind in 'iu' and np.any(np.abs(values.astype(np.longdouble))>2**53):raise ValueError('Integer input cannot be represented exactly as binary64')
            signals[name][start:start+n]=values
        print(f'@@GXTXT_PROGRESS Signal input {start+n}/{count}',flush=True)
    rate=float(p.get('sample_rate',0));t0=0.;times=None
    if time_id:
        times=signals[time_id];v=variables[time_id]
        if v.get('value_kind')!='elapsed_time':
            plan=call('UNIT_REGISTRY_API_v1','affine_plan',[v.get('unit',''),'s'])
            if not plan.get('affine'):raise ValueError('Time conversion requires a public affine Unit Registry plan')
            for start in range(0,count,65536):times[start:start+65536]=times[start:start+65536]*float(plan['scale'])+float(plan['offset'])
        t0=float(times[0]);dt=(float(times[-1])-t0)/(count-1)
        if dt<=0:raise ValueError('Time axis must increase')
        previous=None
        for start in range(0,count,65536):
            block=np.asarray(times[start:start+65536]);index=np.arange(start,start+len(block));deviation=np.max(np.abs(block-(t0+index*dt)))
            if deviation>1e-6*dt or np.any(np.diff(block)<=0) or previous is not None and block[0]<=previous:raise ValueError('Nonuniform or nonincreasing time axis; no resampling was performed')
            previous=float(block[-1])
        measured=1/dt
        if rate>0 and abs(rate-measured)/measured>1e-6:raise ValueError('Declared rate conflicts with measured time axis')
        rate=measured
    x=signals[primary];a=array(x);b=EMPTY;c=EMPTY;opts={}
    if method in {'correlation.cross','spectral.coherence','spectral.frf_h1','spectral.frf_h2'}:
        if not secondary or secondary==primary:raise ValueError('This method requires two distinct aligned signal Variables')
        b=array(signals[secondary])
    if method.startswith('spectral.') or method in {'analytic.instantaneous_frequency','filter.causal','filter.zero_phase','multirate.decimate'}:
        if rate<=0:raise ValueError('Supply a measured time axis or a positive declared sample rate')
    if method.startswith('spectral.'):
        c=scalar(rate);window=int(p['window']);overlap=float(p['overlap'])
        if method!='spectral.periodogram' and not 8<=window<=count:raise ValueError('Welch window must be in 8..full row count')
        opts={'nfft':2**int(np.ceil(np.log2(max(256,count if method=='spectral.periodogram' else window))))}
        if method!='spectral.periodogram':opts.update(window=window,overlap=overlap)
    if method.startswith('correlation.'):
        opts={'normalization':p['normalization']}
        if rate>0:opts['sample_rate']=rate
    if method=='analytic.instantaneous_frequency':b=scalar(rate)
    if method.startswith('filter.'):
        cutoff=float(p['cutoff']);order=int(p['order'])
        if not 0<cutoff<rate/2:raise ValueError('Cutoff must lie strictly between 0 and Nyquist')
        design=call('SIGNAL_API_v1','design.butterworth',[scalar(order),scalar(cutoff/(rate/2)),EMPTY,options({'band':'low','domain':'discrete'})])
        if not design.get('stable'):raise ValueError('Public filter design is unstable')
        a={'kind':'struct','fields':{'numerator':array(design['numerator_real']),'denominator':array(design['denominator_real'])}};b=array(x)
    if method=='multirate.decimate':b=scalar(int(p['decimation']));opts={'sample_rate':rate,'start_time':t0}
    print(f'@@GXTXT_PROGRESS Signal provider {method}; all {count} rows',flush=True)
    result=call('SIGNAL_API_v1',method,[a,b,c,options(opts)])
    current=call('CANONICAL_DATASET_API_v2','describe',[source])
    if current!=metadata:raise ValueError('Canonical source metadata changed during scientific execution')
    primary_unit=variables[primary].get('unit','');columns={};units={}
    mapping={
      'spectral.periodogram':['frequency_hz','psd_real','psd_imaginary'],'spectral.welch':['frequency_hz','psd_real','psd_imaginary'],
      'spectral.asd':['frequency_hz','asd'],'spectral.coherence':['frequency_hz','value_real'],
      'spectral.frf_h1':['frequency_hz','value_real','value_imaginary'],'spectral.frf_h2':['frequency_hz','value_real','value_imaginary'],
      'correlation.auto':['lags','value_real','value_imaginary'],'correlation.cross':['lags','value_real','value_imaginary'],
      'analytic.envelope':['amplitude'],'analytic.phase':['phase_rad'],'analytic.instantaneous_frequency':['frequency_hz'],
      'filter.causal':['value_real'],'filter.zero_phase':['value_real'],'multirate.decimate':['time','value_real']}
    if method in mapping:
        for key in mapping[method]:
            if key not in result:raise ValueError(f'Public provider omitted {key}')
            columns[key]=np.asarray(result[key]).reshape(-1)
        lengths={len(v) for v in columns.values()}
        if len(lengths)!=1 or not next(iter(lengths)):raise ValueError('Provider result columns have inconsistent or empty shapes')
        n=next(iter(lengths))
        if method.startswith(('analytic.','filter.')):
            columns={'time_seconds':times if times is not None else t0+np.arange(n)/rate,**columns} if rate>0 else {'sample_index':np.arange(n),**columns}
        for key in columns:
            if key in ('frequency_hz',):units[key]='Hz'
            elif key in ('time','time_seconds'):units[key]='s'
            elif key in ('lags','sample_index') or method=='spectral.coherence':units[key]='1'
            elif key=='phase_rad':units[key]='rad'
            elif method.startswith(('analytic.envelope','filter.','multirate.')):units[key]=primary_unit
            else:units[key]=''
        target=context.output/'signal_result.csv'
        with target.open('x',newline='',encoding='utf-8') as stream:
            writer=csv.writer(stream,lineterminator='\n');writer.writerow(columns)
            for start in range(0,n,4096):
                data=[np.asarray(v[start:start+4096]) for v in columns.values()]
                if any(not np.isfinite(v).all() for v in data):raise ValueError('Result contains undefined/nonfinite scientific values; nothing was published')
                writer.writerows(zip(*data))
        context.publish_output(target.name,'signal_result','csv',[dict(id=k,dtype='float64',unit=units[k]) for k in columns])
    summary=dict(validation='public_signal_provider_completed',operation=method,source_dataset_id=source,source_variables=chosen,full_input_rows=count,sample_rate_hz=rate,sampling='measured' if time_id else 'declared' if rate else 'unavailable',columns=list(columns),units=units,scalar_fields={k:float(v) if isinstance(v,(int,float,np.number)) else str(v)[:512] for k,v in result.items() if np.asarray(v).size<=1},unit_qualification='Blank derived units are unavailable; real/imaginary components are not mislabeled magnitude or phase')
    summary_path=context.output/'signal_summary.json';summary_path.write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    context.publish_output(summary_path.name,'summary','json');context.summary(summary)
