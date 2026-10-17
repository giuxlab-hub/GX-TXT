# SPDX-License-Identifier: GPL-3.0-or-later
import sys,json
from pathlib import Path
import h5py,numpy as np
from scipy import stats
session=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve();assert '_private_dev106' in session.parts and '_private_dev106' in out.parts and not out.exists()
base=session/'datasets/publications'
def read(name):
 with h5py.File(base/(name+'.h5')) as f:return {k:f['data'][k][:] for k in f['data']}
def text(v):return v.decode() if isinstance(v,bytes) else str(v)
a=read('stats_input');x=a['x'];y=a['y'];g=a['group'];w=a['weight'];checks={}
def close(name,actual,expected,rtol=1e-9,atol=1e-10):
 actual=np.asarray(actual,dtype=float);expected=np.asarray(expected,dtype=float);ok=bool(np.allclose(actual,expected,rtol=rtol,atol=atol,equal_nan=True));checks[name]={'pass':ok,'max_absolute_error':float(np.nanmax(np.abs(actual-expected))) if actual.size else 0};assert ok,(name,actual,expected)
d=read('statistics.descriptive.summary')
for variable,v in [('x',x),('y',y)]:
 for statistic,expected in [('mean',v.mean()),('minimum',v.min()),('maximum',v.max()),('median',np.median(v)),('variance_sample',v.var(ddof=1)),('variance_population',v.var()),('rms',np.sqrt(np.mean(v*v)))]:
  i=next(i for i in range(len(d['value'])) if text(d['variable_id'][i])==variable and text(d['statistic'][i])==statistic);close('descriptive_'+variable+'_'+statistic,d['value'][i],expected)
d=read('statistics.grouped.summary')
for i in range(len(d['mean'])):
 v=(x if text(d['variable_id'][i])=='x' else y)[g==d['group_numeric_value'][i]];close(f'grouped_mean_{i}',d['mean'][i],v.mean());close(f'grouped_count_{i}',d['count'][i],len(v))
d=read('statistics.weighted.summary');mean=np.average(x,weights=w);close('weighted_mean',d['weighted_mean'][0],mean);close('weighted_population_variance',d['weighted_variance_population'][0],np.average((x-mean)**2,weights=w));close('weighted_effective_n',d['effective_n'][0],w.sum()**2/np.sum(w*w))
d=read('statistics.correlation.pairs');vectors={'x':x,'y':y}
for i in range(len(d['pearson'])):
 left=vectors[text(d['left_variable_id'][i])];right=vectors[text(d['right_variable_id'][i])];close(f'pearson_{i}',d['pearson'][i],stats.pearsonr(left,right).statistic);close(f'spearman_{i}',d['spearman'][i],stats.spearmanr(left,right).statistic)
d=read('statistics.distribution.bins');edges=np.r_[d['left_edge'],d['right_edge'][-1]];close('distribution_bin_counts',d['count'],np.histogram(x,bins=edges)[0]);close('distribution_count_conserved',d['count'].sum(),len(x))
d=read('statistics.outliers.flags');q=np.quantile(x,[.25,.75],method='linear');lo=q[0]-1.5*(q[1]-q[0]);hi=q[1]+1.5*(q[1]-q[0]);close('outlier_lower',d['lower_limit'],np.repeat(lo,len(x)));close('outlier_upper',d['upper_limit'],np.repeat(hi,len(x)));close('outlier_flags',d['is_outlier'],(x<lo)|(x>hi))
d=read('statistics.tests.result');reference=stats.ttest_1samp(x,0);close('one_sample_t',d['statistic'][0],reference.statistic);close('one_sample_t_p',d['p_value'][0],reference.pvalue,atol=1e-14)
d=read('statistics.anova.test');reference=stats.f_oneway(*[x[g==group] for group in np.unique(g)]);close('anova_F',d['f_statistic'][0],reference.statistic);close('anova_p',d['p_value'][0],reference.pvalue)
z=np.column_stack([x,y]);z=(z-z.mean(axis=0))/z.std(axis=0,ddof=1);eigenvalues=np.linalg.eigvalsh(np.cov(z,rowvar=False))[::-1];d=read('statistics.pca.components');close('pca_eigenvalues',d['eigenvalue'],eigenvalues);close('pca_explained_ratio',d['explained_ratio'],eigenvalues/eigenvalues.sum())
d=read('statistics.resampling.summary');close('resampling_observed_mean',d['observed'][0],x.mean());distribution=read('statistics.resampling.distribution')['statistic'];assert len(distribution)==int(d['replicates'][0])==1000 and np.isfinite(distribution).all();checks['resampling_real_replicates']={'pass':True,'count':len(distribution),'qualification':'Observed statistic independently checked; Octave seeded replicate sequence is retained, not equated with a different Python RNG'}
report={'status':'PASS','providers':10,'checks':checks,'source':'actual ten disabled-provider GUI outputs, independent NumPy/SciPy definitions'};out.write_text(json.dumps(report,indent=2)+'\n');print('PASS ten statistical providers:',len(checks),'independent checks')
