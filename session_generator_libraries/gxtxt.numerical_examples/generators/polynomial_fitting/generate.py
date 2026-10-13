#!/usr/bin/env python3
import argparse,csv,random,sys
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--target-session',required=True); p.add_argument('--library-id'); p.add_argument('--generator-id'); a=p.parse_args()
root=Path(a.target_session); rng=random.Random(1972); c3,c2,c1,c0=0.5,-2.0,1.5,3.0
with (root/'raw'/'polynomial_fitting.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.writer(f); w.writerow(['x','y'])
 for i in range(61):
  x=-3.0+i*0.1; y=c3*x**3+c2*x**2+c1*x+c0+rng.gauss(0.0,0.08); w.writerow([f'{x:.8g}',f'{y:.12g}'])
(root/'metadata'/'ground_truth.txt').write_text('model=y=c3*x^3+c2*x^2+c1*x+c0+noise\nc3=0.5\nc2=-2\nc1=1.5\nc0=3\nnoise=Gaussian sigma 0.08\nseed=1972\n',encoding='utf-8')
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from recipe import configure
configure(root,'polynomial_fitting.csv','regression.polynomial.source','demo.numeric.regression',
          {'x':'independent','y':'measured'}, {'x':'x','measured':'y'},
          {'selection':'','fit_mode':'polynomial','polynomial_degree':'3','weight_semantics':'relative','output_dataset_id':'demo.numeric.regression.result'})
print('Generated deterministic polynomial-fitting dataset.')
